const std = @import("std");

/// The version information for this library. This is hardcoded for now but
/// in the future we will parse this from configure.ac.
pub const Version = struct {
    pub const major = "2";
    pub const minor = "9";
    pub const micro = "12";

    pub fn number() []const u8 {
        return comptime major ++ "0" ++ minor ++ "0" ++ micro;
    }

    pub fn string() []const u8 {
        return comptime "\"" ++ number() ++ "\"";
    }

    pub fn dottedString() []const u8 {
        return comptime "\"" ++ major ++ "." ++ minor ++ "." ++ micro ++ "\"";
    }
};

/// This is the type returned by create.
pub const Library = struct {
    step: *std.build.LibExeObjStep,

    /// statically link this library into the given step
    pub fn link(self: Library, other: *std.build.LibExeObjStep) void {
        self.addIncludePaths(other);
        other.linkLibrary(self.step);
    }

    /// only add the include dirs to the given step. This is useful if building
    /// a static library that you don't want to fully link in the code of this
    /// library.
    pub fn addIncludePaths(self: Library, other: *std.build.LibExeObjStep) void {
        _ = self;
        other.addIncludePath(.{ .path = include_dir });
        other.addIncludePath(.{ .path = override_include_dir });
    }
};

/// Compile-time options for the library. These mostly correspond to
/// options exposed by the native build system used by the library.
pub const Options = struct {
    // These options are all defined in libxml2's configure.c and correspond
    // to `--with-X` options for `./configure`. Their defaults are properly set.
    c14n: bool = true,
    catalog: bool = true,
    debug: bool = true,
    ftp: bool = false,
    history: bool = true,
    html: bool = true,
    iconv: bool = true,
    icu: bool = false,
    iso8859x: bool = true,
    legacy: bool = false,
    mem_debug: bool = false,
    minimum: bool = true,
    output: bool = true,
    pattern: bool = true,
    push: bool = true,
    reader: bool = true,
    regexp: bool = true,
    run_debug: bool = false,
    sax1: bool = true,
    schemas: bool = true,
    schematron: bool = true,
    thread: bool = true,
    thread_alloc: bool = false,
    tree: bool = true,
    valid: bool = true,
    writer: bool = true,
    xinclude: bool = true,
    xpath: bool = true,
    xptr: bool = true,
    xptr_locs: bool = false,
    modules: bool = true,
    lzma: bool = true,
    zlib: bool = true,
};

/// Create this library. This is the primary API users of build.zig should
/// use to link this library to their application. On the resulting Library,
/// call the link function and given your own application step.
pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
) !Library {
    const ret = b.addStaticLibrary(.{
        .name = "xml2",
        .target = target,
        .optimize = optimize,
    });

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        // Version info, hardcoded
        comptime "-DLIBXML_VERSION=" ++ Version.number(),
        comptime "-DLIBXML_VERSION_STRING=" ++ Version.string(),
        "-DLIBXML_VERSION_EXTRA=\"\"",
        comptime "-DLIBXML_DOTTED_VERSION=" ++ Version.dottedString(),

        // These might now always be true (particularly Windows) but for
        // now we just set them all. We should do some detection later.
        "-DSEND_ARG2_CAST=",
        "-DGETHOSTBYNAME_ARG_CAST=",
        "-DGETHOSTBYNAME_ARG_CAST_CONST=",

        // Always on
        "-DLIBXML_STATIC=1",
        "-DLIBXML_AUTOMATA_ENABLED=1",
        "-DWITHOUT_TRIO=1",
    });

    if (!target.isWindows()) {
        try flags.appendSlice(&.{
            "-DHAVE_ARPA_INET_H=1",
            "-DHAVE_ARPA_NAMESER_H=1",
            "-DHAVE_DL_H=1",
            "-DHAVE_NETDB_H=1",
            "-DHAVE_NETINET_IN_H=1",
            "-DHAVE_PTHREAD_H=1",
            "-DHAVE_SHLLOAD=1",
            "-DHAVE_SYS_DIR_H=1",
            "-DHAVE_SYS_MMAN_H=1",
            "-DHAVE_SYS_NDIR_H=1",
            "-DHAVE_SYS_SELECT_H=1",
            "-DHAVE_SYS_SOCKET_H=1",
            "-DHAVE_SYS_TIMEB_H=1",
            "-DHAVE_SYS_TIME_H=1",
            "-DHAVE_SYS_TYPES_H=1",
        });
    }

    // Option-specific changes
    if (opts.history) {
        try flags.appendSlice(&.{
            "-DHAVE_LIBHISTORY=1",
            "-DHAVE_LIBREADLINE=1",
        });
    }
    if (opts.mem_debug) {
        try flags.append("-DDEBUG_MEMORY_LOCATION=1");
    }
    if (opts.regexp) {
        try flags.append("-DLIBXML_UNICODE_ENABLED=1");
    }
    if (opts.run_debug) {
        try flags.append("-DLIBXML_DEBUG_RUNTIME=1");
    }
    if (opts.thread) {
        try flags.append("-DHAVE_LIBPTHREAD=1");
    }

    // Enable our `./configure` options. For bool-type fields we translate
    // it to the `LIBXML_{field}_ENABLED` C define where field is uppercased.
    inline for (std.meta.fields(@TypeOf(opts))) |field| {
        if (field.type == bool and @field(opts, field.name)) {
            var nameBuf: [32]u8 = undefined;
            const name = std.ascii.upperString(&nameBuf, field.name);
            const define = try std.fmt.allocPrint(b.allocator, "-DLIBXML_{s}_ENABLED=1", .{name});
            try flags.append(define);
        }
    }

    // C files
    ret.addCSourceFiles(.{ .files = srcs, .flags = flags.items });

    ret.addIncludePath(.{ .path = include_dir });
    ret.addIncludePath(.{ .path = override_include_dir });
    if (target.isWindows()) {
        ret.addIncludePath(.{ .path = win32_include_dir });
        ret.linkSystemLibrary("ws2_32");
    } else {
        ret.addIncludePath(.{ .path = posix_include_dir });
    }
    ret.linkLibC();

    return Library{ .step = ret };
}

/// Directories with our includes.
const include_dir = thisDir() ++ "/libxml2/include";
const override_include_dir = thisDir() ++ "/override/include";
const posix_include_dir = thisDir() ++ "/override/config/posix";
const win32_include_dir = thisDir() ++ "/override/config/win32";

const srcs = &.{
    thisDir() ++ "/libxml2/buf.c",
    thisDir() ++ "/libxml2/c14n.c",
    thisDir() ++ "/libxml2/catalog.c",
    thisDir() ++ "/libxml2/chvalid.c",
    thisDir() ++ "/libxml2/debugXML.c",
    thisDir() ++ "/libxml2/dict.c",
    thisDir() ++ "/libxml2/encoding.c",
    thisDir() ++ "/libxml2/entities.c",
    thisDir() ++ "/libxml2/error.c",
    thisDir() ++ "/libxml2/globals.c",
    thisDir() ++ "/libxml2/hash.c",
    thisDir() ++ "/libxml2/HTMLparser.c",
    thisDir() ++ "/libxml2/HTMLtree.c",
    thisDir() ++ "/libxml2/legacy.c",
    thisDir() ++ "/libxml2/list.c",
    thisDir() ++ "/libxml2/nanoftp.c",
    thisDir() ++ "/libxml2/nanohttp.c",
    thisDir() ++ "/libxml2/parser.c",
    thisDir() ++ "/libxml2/parserInternals.c",
    thisDir() ++ "/libxml2/pattern.c",
    thisDir() ++ "/libxml2/relaxng.c",
    thisDir() ++ "/libxml2/SAX.c",
    thisDir() ++ "/libxml2/SAX2.c",
    thisDir() ++ "/libxml2/schematron.c",
    thisDir() ++ "/libxml2/threads.c",
    thisDir() ++ "/libxml2/tree.c",
    thisDir() ++ "/libxml2/uri.c",
    thisDir() ++ "/libxml2/valid.c",
    thisDir() ++ "/libxml2/xinclude.c",
    thisDir() ++ "/libxml2/xlink.c",
    thisDir() ++ "/libxml2/xmlIO.c",
    thisDir() ++ "/libxml2/xmlmemory.c",
    thisDir() ++ "/libxml2/xmlmodule.c",
    thisDir() ++ "/libxml2/xmlreader.c",
    thisDir() ++ "/libxml2/xmlregexp.c",
    thisDir() ++ "/libxml2/xmlsave.c",
    thisDir() ++ "/libxml2/xmlschemas.c",
    thisDir() ++ "/libxml2/xmlschemastypes.c",
    thisDir() ++ "/libxml2/xmlstring.c",
    thisDir() ++ "/libxml2/xmlunicode.c",
    thisDir() ++ "/libxml2/xmlwriter.c",
    thisDir() ++ "/libxml2/xpath.c",
    thisDir() ++ "/libxml2/xpointer.c",
    thisDir() ++ "/libxml2/xzlib.c",
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
