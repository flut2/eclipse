const std = @import("std");
const assert = std.debug.assert;

const Diagnostic = @import("Diagnostic.zig");
pub const Error = Diagnostic.Error.ZigError;
const dynamic = @import("dynamic.zig");
const Value = dynamic.Value;
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;

const Parser = @This();

gpa: std.mem.Allocator,
code: [:0]const u8,
opts: ParseOptions,
tokenizer: Tokenizer,
state: State = .start,

pub const ParseOptions = struct {
    diagnostic: ?*Diagnostic = null,
    copy_strings: CopyStrings = .always,

    pub const CopyStrings = enum {
        to_unescape,
        always,
    };
};

const Container = enum {
    start,
    @"struct",
    dyn,
    array,
};

const State = enum {
    start,
    struct_lb_or_comma,
    field_dot,
};

pub fn addError(p: *Parser, err: Diagnostic.Error) Diagnostic.Error.ZigError {
    if (p.opts.diagnostic) |d| {
        try d.errors.append(p.gpa, err);
    }
    return err.zigError();
}

fn lexemes(comptime tags: []const Token.Tag) []const []const u8 {
    comptime var out: []const []const u8 = &.{};
    inline for (tags) |t| {
        const next_tag: []const []const u8 = &.{comptime t.lexeme()};
        out = out ++ next_tag;
    }
    return out;
}

/// Use an arena allocator to avoid leaking allocations when complex types
/// are involved.
pub fn parseLeaky(
    comptime T: type,
    gpa: std.mem.Allocator,
    code: [:0]const u8,
    opts: ParseOptions,
) Error!T {
    var parser: Parser = .{
        .gpa = gpa,
        .code = code,
        .opts = opts,
        .tokenizer = .{ .want_comments = false },
    };

    const result = try parser.parseValue(T, parser.next());

    const extra = parser.next();
    if (extra.tag != .eof) {
        return parser.addError(.{
            .unexpected = .{
                .name = "EOF",
                .sel = extra.loc.getSelection(code),
                .expected = lexemes(&.{.eof}),
            },
        });
    }

    return result;
}

/// Used when implementng `ziggy.parse()` for a type
pub fn parseValue(
    self: *Parser,
    comptime T: type,
    first_tok: Token,
) Error!T {
    const info = @typeInfo(T);

    switch (info) {
        .pointer => |ptr| switch (ptr.size) {
            .Slice => switch (ptr.child) {
                u8 => return self.parseBytes(T, first_tok),
                else => return self.parseArray(T, first_tok),
            },
            .One => {
                const v: T = try self.gpa.create(ptr.child);
                errdefer self.gpa.destroy(v);

                v.* = try self.parseValue(ptr.child, first_tok);
                return v;
            },
            else => @compileError("Unable to parse pointer to many / C: " ++ @typeName(T)),
        },
        .bool => return self.parseBool(first_tok),
        .int => return self.parseInt(T, first_tok),
        .float => return self.parseFloat(T, first_tok),
        .@"struct" => {
            if (@hasDecl(T, "ziggy_options") and @hasDecl(T.ziggy_options, "parse")) {
                return T.ziggy_options.parse(self, first_tok);
            }
            return self.parseStruct(T, first_tok);
        },
        .@"union" => {
            if (@hasDecl(T, "ziggy_options") and @hasDecl(T.ziggy_options, "parse")) {
                return T.ziggy_options.parse(self, first_tok);
            }
            return self.parseUnion(T, first_tok);
        },
        .@"enum" => {
            if (@hasDecl(T, "ziggy_options") and @hasDecl(T.ziggy_options, "parse")) {
                return T.ziggy_options.parse(self, first_tok);
            }
            return self.parseEnum(T, first_tok);
        },
        .optional => |opt| {
            if (first_tok.tag == .null) {
                return null;
            } else {
                // this *has* to be a return try
                return try self.parseValue(opt.child, first_tok);
            }
        },
        .array => return try self.parseStaticArray(T, first_tok),
        else => @compileError("TODO"),
    }
}

fn parseEnum(
    self: *Parser,
    comptime T: type,
    first_tok: Token,
) Error!T {
    // Skip over "@<enumtype>("
    _ = try self.nextMust(.identifier);
    _ = try self.nextMust(.lp);

    const token = try self.nextMust(.string);
    const enum_str = std.mem.trim(u8, token.loc.src(self.code), "\"");

    // Skip over ")"
    _ = try self.nextMust(.rp);

    return std.meta.stringToEnum(T, enum_str) orelse {
        return self.addError(.{
            .unknown_field = .{
                .name = first_tok.loc.src(self.code),
                .sel = first_tok.loc.getSelection(self.code),
            },
        });
    };
}

fn parseUnion(
    self: *Parser,
    comptime T: type,
    first_tok: Token,
) Error!T {
    // When a top-level struct omits curlies, the first
    // token will be a dot. Is such case we don't want
    // to expect a closing right bracket.
    const info = @typeInfo(T).@"union";
    comptime {
        if (info.tag_type == null) {
            @compileError("union '" ++ @typeName(T) ++ "' must be tagged");
        }

        for (info.fields) |f| {
            switch (@typeInfo(f.type)) {
                .@"struct", .@"union", .@"enum", .optional, .array, .bool, .int, .float => {},
                .pointer => |p| {
                    if (p.size == .C or p.size == .Many) @compileError("Many/C pointers are not supported");
                },
                else => {
                    @compileError("Unhandled union case for '" ++ @typeName(T) ++ "': " ++ f.type);
                },
            }
        }
    }

    // TODO: check identifier for conformance
    try self.must(first_tok, .identifier);
    const case_name = first_tok.loc.src(self.code);
    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, case_name)) switch (@typeInfo(field.type)) {
            .@"struct" => return @unionInit(T, field.name, try self.parseValue(field.type, self.next())),
            else => {
                try self.must(self.next(), .lb);
                defer self.must(self.next(), .rb) catch @panic("cba doing this properly");
                return @unionInit(T, field.name, try self.parseValue(field.type, self.next()));
            },
        };
    }

    return self.addError(.{
        .unknown_field = .{
            .name = first_tok.loc.src(self.code),
            .sel = first_tok.loc.getSelection(self.code),
        },
    });
}
fn parseStruct(
    self: *Parser,
    comptime T: type,
    first_tok: Token,
) Error!T {
    // When a top-level struct omits curlies, the first
    // token will be a dot. Is such case we don't want
    // to expect a closing right bracket.
    const need_closing_rb = first_tok.tag != .dot;
    const info = @typeInfo(T).@"struct";

    var tok = first_tok;
    if (tok.tag == .identifier) {
        // TODO: check identifier for conformance
        tok = self.next();
    }
    if (tok.tag == .lb) {
        tok = self.next();
    }

    // TODO: optimization: turn this into an array of bools when
    //       diagnocstics are disabled
    var fields_seen = [_]?Token.Loc{null} ** info.fields.len;
    var val: T = undefined;
    while (true) {
        if (need_closing_rb) {
            try self.mustAny(tok, &.{ .dot, .rb });
        } else {
            try self.mustAny(tok, &.{ .dot, .eof });
        }

        if (tok.tag != .dot) {
            try self.finalizeStruct(
                T,
                info,
                &val,
                &fields_seen,
                tok,
            );
            return val;
        }

        // we found the start of a field
        assert(tok.tag == .dot);

        const ident = try self.nextMust(.identifier);
        _ = try self.nextMust(.eql);
        const field_name = ident.loc.src(self.code);
        inline for (info.fields, 0..) |f, idx| {
            if (std.mem.eql(u8, f.name, field_name)) {
                if (fields_seen[idx]) |first_loc| {
                    return self.addError(.{
                        .duplicate_field = .{
                            .name = ident.loc.src(self.code),
                            .sel = ident.loc.getSelection(self.code),
                            .original = first_loc.getSelection(self.code),
                        },
                    });
                }
                fields_seen[idx] = ident.loc;
                @field(val, f.name) = try self.parseValue(f.type, self.next());
                break;
            }
        } else {
            return self.addError(.{
                .unknown_field = .{
                    .name = ident.loc.src(self.code),
                    .sel = ident.loc.getSelection(self.code),
                },
            });
        }

        tok = self.next();
        if (tok.tag == .comma) {
            tok = self.next();
        } else {
            if (need_closing_rb) {
                try self.mustAny(tok, &.{ .comma, .rb });
            } else {
                try self.mustAny(tok, &.{ .comma, .rb, .eof });
            }
        }
    }
}

// TODO: allocate memory to copy fields_seen and pass it all to diagnostic
fn finalizeStruct(
    self: *Parser,
    comptime T: type,
    info: std.builtin.Type.Struct,
    val: *T,
    fields_seen: []const ?Token.Loc,
    struct_end: Token,
) Error!void {
    inline for (info.fields, 0..) |field, idx| {
        if (fields_seen[idx] == null) {
            if (field.default_value) |ptr| {
                const dv_ptr: *const field.type = @alignCast(@ptrCast(ptr));
                @field(val, field.name) = dv_ptr.*;
            } else {
                return self.addError(.{
                    .missing_field = .{
                        .name = field.name,
                        .sel = struct_end.loc.getSelection(self.code),
                    },
                });
            }
        }
    }
}

pub fn parseBool(self: *Parser, true_or_false: Token) !bool {
    try self.mustAny(true_or_false, &.{ .true, .false });
    return switch (true_or_false.tag) {
        .true => true,
        .false => false,
        else => unreachable,
    };
}

pub fn parseInt(self: *Parser, comptime T: type, num: Token) !T {
    assert(@typeInfo(T) == .int);

    const src = num.loc.src(self.code);
    if (src.len >= 10 and std.mem.eql(u8, src[0..3], "\"0x")) {
        return std.fmt.parseInt(T, src[1..9], 0) catch {
            return self.addError(.overflow);
        };
    }

    try self.must(num, .integer);
    return std.fmt.parseInt(T, src, 0) catch {
        return self.addError(.overflow);
    };
}

pub fn parseFloat(self: *Parser, comptime T: type, num: Token) !T {
    assert(@typeInfo(T) == .float);

    try self.must(num, .float);
    return std.fmt.parseFloat(T, num.loc.src(self.code)) catch {
        return self.addError(.overflow);
    };
}

pub fn parseBytes(self: *Parser, comptime T: type, token: Token) !T {
    try self.mustAny(token, &.{ .string, .at, .line_string });

    switch (token.tag) {
        .string => return token.loc.unescape(self.gpa, self.code),
        .at => {
            _ = try self.nextMust(.identifier);
            _ = try self.nextMust(.lp);
            const str = try self.nextMust(.string);
            _ = try self.nextMust(.rp);

            return str.loc.unescape(self.gpa, self.code);
        },
        .line_string => {
            var str = std.ArrayList(u8).init(self.gpa);
            errdefer str.deinit();

            var current = token;
            while (current.tag == .line_string) {
                try str.appendSlice(current.loc.src(self.code)[2..]);

                if (self.peek().tag != .line_string) break;

                try str.append('\n');
                current = self.next();
            }
            return str.toOwnedSlice();
        },
        else => unreachable,
    }
}

fn parseStaticArray(self: *Parser, comptime T: type, lsb: Token) !T {
    const info = @typeInfo(T).array;

    try self.must(lsb, .lsb);

    var tok = self.next();
    var list: std.ArrayListUnmanaged(info.child) = .{};
    errdefer list.deinit(self.gpa);

    while (true) {
        if (tok.tag == .rsb) {
            return (try list.toOwnedSlice(self.gpa))[0..info.len].*;
        }

        try list.append(
            self.gpa,
            try self.parseValue(info.child, tok),
        );

        tok = self.next();
        if (tok.tag == .comma) {
            tok = self.next();
        } else {
            try self.must(tok, .rsb);
        }
    }
}

fn parseArray(self: *Parser, comptime T: type, lsb: Token) !T {
    const info = @typeInfo(T).pointer;
    assert(info.size == .Slice);

    try self.must(lsb, .lsb);

    var tok = self.next();
    var list: std.ArrayListUnmanaged(info.child) = .{};
    errdefer list.deinit(self.gpa);

    while (true) {
        if (tok.tag == .rsb) {
            return list.toOwnedSlice(self.gpa);
        }

        try list.append(
            self.gpa,
            try self.parseValue(info.child, tok),
        );

        tok = self.next();
        if (tok.tag == .comma) {
            tok = self.next();
        } else {
            try self.must(tok, .rsb);
        }
    }
}

pub fn next(self: *Parser) Token {
    return self.tokenizer.next(self.code);
}
pub fn nextNoEof(
    self: *Parser,
) !Token {
    const tok = self.next();
    if (tok.tag == .eof) return self.addError(.{
        .unexpected = .{
            .name = tok.tag.lexeme(),
            .sel = tok.loc.getSelection(self.code),
            .expected = &.{},
        },
    });
    return tok;
}

pub fn peek(self: *Parser) Token {
    var t = self.tokenizer;
    return t.next(self.code);
}

pub fn nextMust(self: *Parser, comptime tag: Token.Tag) !Token {
    return self.nextMustAny(&.{tag});
}

pub fn nextMustAny(
    self: *Parser,
    comptime tags: []const Token.Tag,
) !Token {
    const next_tok = self.next();
    try self.mustAny(next_tok, tags);
    return next_tok;
}

pub fn must(
    self: *Parser,
    tok: Token,
    comptime tag: Token.Tag,
) !void {
    return self.mustAny(tok, &.{tag});
}

pub fn mustAny(
    self: *Parser,
    tok: Token,
    comptime tags: []const Token.Tag,
) !void {
    for (tags) |t| {
        if (t == tok.tag) break;
    } else {
        return self.addError(.{
            .unexpected = .{
                .name = tok.tag.lexeme(),
                .sel = tok.loc.getSelection(self.code),
                .expected = lexemes(tags),
            },
        });
    }
}

test "struct - basics" {
    const case =
        \\.foo = "bar",
        \\.bar = false,
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    const c = try parseLeaky(Case, std.testing.allocator, case, .{});
    try std.testing.expectEqualStrings("bar", c.foo);
    try std.testing.expectEqual(false, c.bar);
}

test "struct - top level curlies" {
    const case =
        \\{
        \\   .foo = "bar",
        \\   .bar = false,
        \\}
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    const c = try parseLeaky(Case, std.testing.allocator, case, .{});
    try std.testing.expectEqualStrings("bar", c.foo);
    try std.testing.expectEqual(false, c.bar);
}

test "struct - missing bottom curly" {
    const case =
        \\{
        \\   .foo = "bar",
        \\   .bar = false,
        \\
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = parseLeaky(Case, std.testing.allocator, case, opts);
    try std.testing.expectError(error.Syntax, result);
    try std.testing.expectFmt(
        \\line: 4 col: 1
        \\unexpected 'EOF', expected: '.' or '}'
        \\
    , "{}", .{diag});
}

test "struct - syntax error" {
    const case =
        \\.foo = "bar",
        \\.bar = .false,
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = parseLeaky(Case, std.testing.allocator, case, opts);
    try std.testing.expectError(error.Syntax, result);
    try std.testing.expectFmt(
        \\line: 2 col: 8
        \\unexpected '.', expected: 'true' or 'false'
        \\
    , "{}", .{diag});
}

test "struct - missing comma" {
    const case =
        \\.foo = "bar"
        \\.bar = false,
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = parseLeaky(Case, std.testing.allocator, case, opts);
    try std.testing.expectError(error.Syntax, result);
    try std.testing.expectFmt(
        \\line: 2 col: 1
        \\unexpected '.', expected: ',' or '}' or 'EOF'
        \\
    , "{}", .{diag});
}

test "struct - optional comma" {
    const case =
        \\.foo = "bar",
        \\.bar = false
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    const c = try parseLeaky(Case, std.testing.allocator, case, .{});
    try std.testing.expectEqualStrings("bar", c.foo);
    try std.testing.expectEqual(false, c.bar);
}

test "struct - missing field" {
    const case =
        \\.foo = "bar",
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = parseLeaky(Case, std.testing.allocator, case, opts);
    try std.testing.expectError(error.Syntax, result);
    try std.testing.expectFmt(
        \\line: 1 col: 14
        \\missing field: 'bar'
    , "{}", .{diag});
}

test "struct - duplicate field" {
    const case =
        \\.foo = "bar",
        \\.bar = false,
        \\.foo = "bar",
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = parseLeaky(Case, std.testing.allocator, case, opts);
    try std.testing.expectError(error.Syntax, result);
    try std.testing.expectFmt(
        \\line: 3 col: 2
        \\duplicate field 'foo', first definition here: line: 1 col: 2
        \\
    , "{}", .{diag});
}

test "struct - unknown field" {
    const case =
        \\.foo = "bar",
        \\.bar = false,
        \\.baz = "oops",
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = parseLeaky(Case, std.testing.allocator, case, opts);
    try std.testing.expectError(error.Syntax, result);
    try std.testing.expectFmt(
        \\line: 3 col: 2
        \\unknown field 'baz'
    , "{}", .{diag});
}

test "string" {
    const case =
        \\
        \\ "foo"
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky([]const u8, std.testing.allocator, case, opts);
    try std.testing.expectEqualStrings("foo", result);
}

test "custom string literal" {
    const case =
        \\
        \\ @date("2020-07-06T00:00:00")
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky([]const u8, std.testing.allocator, case, opts);
    try std.testing.expectEqualStrings("2020-07-06T00:00:00", result);
}

test "int basics" {
    const case =
        \\
        \\ 1042
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky(usize, std.testing.allocator, case, opts);
    try std.testing.expectEqual(1042, result);
}

test "float basics" {
    const case =
        \\
        \\ 10.42
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky(f64, std.testing.allocator, case, opts);
    try std.testing.expectEqual(10.42, result);
}

test "array basics" {
    const case =
        \\
        \\ [1, 2, 3]
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky([]usize, std.testing.allocator, case, opts);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 3 }, result);
}

test "array trailing comma" {
    const case =
        \\
        \\ [1, 2, 3, ]
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky([]usize, std.testing.allocator, case, opts);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 3 }, result);
}

test "comments are ignored" {
    const case =
        \\.foo = "bar",
        \\// This is false because I say so
        \\.bar = false,
    ;

    const Case = struct {
        foo: []const u8,
        bar: bool,
    };

    const c = try parseLeaky(Case, std.testing.allocator, case, .{});
    try std.testing.expectEqualStrings("bar", c.foo);
    try std.testing.expectEqual(false, c.bar);
}

test "optional - string" {
    const case =
        \\
        \\ "foo"
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky(?[]const u8, std.testing.allocator, case, opts);
    try std.testing.expectEqualStrings("foo", result.?);
}

test "optional - null" {
    const case =
        \\
        \\ null
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky(?[]const u8, std.testing.allocator, case, opts);
    try std.testing.expect(result == null);
}

test "tagged string" {
    const case =
        \\
        \\ @tagname("foo")
        \\
    ;

    var diag: Diagnostic = .{ .path = null };
    defer diag.deinit(std.testing.allocator);

    const opts: ParseOptions = .{ .diagnostic = &diag };

    const result = try parseLeaky([]const u8, std.testing.allocator, case, opts);
    try std.testing.expectEqualStrings("foo", result);
}

test "unions" {
    const case =
        \\.dep1 = Remote {
        \\    .url = "https://github.com",
        \\    .hash = @sha512("123..."),
        \\},
        \\.dep2 =  Local {
        \\    .path = "../super"
        \\},
    ;

    const Project = struct {
        dep1: Dependency,
        dep2: Dependency,
        pub const Dependency = union(enum) {
            Remote: struct {
                url: []const u8,
                hash: []const u8,
            },
            Local: struct {
                path: []const u8,
            },
        };
    };

    const c = try parseLeaky(Project, std.testing.allocator, case, .{});
    try std.testing.expect(c.dep1 == .Remote);
    try std.testing.expectEqualStrings("https://github.com", c.dep1.Remote.url);
    try std.testing.expectEqualStrings("123...", c.dep1.Remote.hash);
    try std.testing.expect(c.dep2 == .Local);
    try std.testing.expectEqualStrings("../super", c.dep2.Local.path);
}

test "multiline string" {
    const just_str =
        \\.outer = Stri {
        \\  .str =
        \\    \\fst
        \\    \\snd
        \\  ,
        \\}
    ;

    const MultiStr = struct { outer: struct {
        str: []const u8,
    } };

    const c = try parseLeaky(MultiStr, std.testing.allocator, just_str, .{});
    try std.testing.expectEqualStrings("fst\nsnd", c.outer.str);
}
