const std = @import("std");

const Enemy = @import("../../map/Enemy.zig");
const Entity = @import("../../map/Entity.zig");
const Metadata = @import("../behavior.zig").BehaviorMetadata;
const logic = @import("../logic.zig");
const loot = @import("../loot.zig");

pub const Crocodile = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Crocodile",
    };

    pub fn death(_: *Crocodile, host: *Enemy) !void {
        loot.dropCards(host, &.{
            .{ .name = "Thick Plating", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Inpenetrable Ward", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Heavy Strikes", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Arcane Incantations", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Vital Essence", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Font of Magic", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Nimble Feet", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Time Distortion", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Enhanced Fortitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Boundless Aptitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
        });
        loot.dropResources(host, &.{
            .{ .name = "Tiny Magisteel Alloy", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Pine Driftwood", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Solid Magma", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
        });
        loot.dropCurrency(host, &.{.{ .type = .gold, .chance = 1.0 / 20.0, .min = 10, .max = 17, .threshold = 0.001 }});
        loot.dropPortals(host, &.{.{ .name = "Crown Cove", .chance = 1.0 / 10.0 }});
    }

    pub fn tick(_: *Crocodile, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.follow(@src(), host, dt, .{
            .speed = 3.0,
            .acquire_range = 9.0,
            .cooldown = 2.0 * std.time.us_per_s,
        })) logic.wander(@src(), host, dt, 2.5);

        logic.aoe(@src(), host, dt, .{
            .radius = 3.0,
            .magic_dmg = 80,
            .conditions = &.{.{ .type = .slowed, .duration = 0.5 * std.time.us_per_s }},
            .cooldown = 0.6 * std.time.us_per_s,
            .color = 0x01361F,
        });
        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 12.0,
            .proj_index = 0,
            .count = 3,
            .radius = 16.0,
            .cooldown = 0.6 * std.time.us_per_s,
        });
    }
};

pub const SpikeBall = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Spike Ball",
    };

    pub fn death(_: *SpikeBall, host: *Enemy) !void {
        loot.dropCards(host, &.{
            .{ .name = "Thick Plating", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Inpenetrable Ward", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Heavy Strikes", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Arcane Incantations", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Vital Essence", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Font of Magic", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Nimble Feet", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Time Distortion", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Enhanced Fortitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Boundless Aptitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
        });
        loot.dropResources(host, &.{
            .{ .name = "Tiny Magisteel Alloy", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Pine Driftwood", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Solid Magma", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
        });
        loot.dropCurrency(host, &.{.{ .type = .gold, .chance = 1.0 / 20.0, .min = 10, .max = 17, .threshold = 0.001 }});
        loot.dropPortals(host, &.{.{ .name = "Crown Cove", .chance = 1.0 / 10.0 }});
    }

    pub fn tick(_: *SpikeBall, host: *Enemy, time: i64, dt: i64) !void {
        logic.wander(@src(), host, dt, 2.5);
        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 36.0,
            .proj_index = 0,
            .count = 10,
            .radius = 16.0,
            .cooldown = 0.4 * std.time.us_per_s,
        });
    }
};

pub const GoblinGrunt = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Goblin Grunt",
    };

    pub fn death(_: *GoblinGrunt, host: *Enemy) !void {
        loot.dropCards(host, &.{
            .{ .name = "Thick Plating", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Inpenetrable Ward", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Heavy Strikes", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Arcane Incantations", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Vital Essence", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Font of Magic", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Nimble Feet", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Time Distortion", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Enhanced Fortitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Boundless Aptitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
        });
        loot.dropResources(host, &.{
            .{ .name = "Tiny Magisteel Alloy", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Pine Driftwood", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Solid Magma", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
        });
        loot.dropCurrency(host, &.{.{ .type = .gold, .chance = 1.0 / 20.0, .min = 10, .max = 17, .threshold = 0.001 }});
        loot.dropPortals(host, &.{.{ .name = "Crown Cove", .chance = 1.0 / 10.0 }});
    }

    pub fn tick(_: *GoblinGrunt, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.charge(@src(), host, dt, .{
            .speed = 6.0,
            .range = 9.0,
            .cooldown = 1.0 * std.time.us_per_s,
        })) logic.wander(@src(), host, dt, 1.65);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 4.0,
            .proj_index = 0,
            .count = 3,
            .radius = 16.0,
            .cooldown = 0.9 * std.time.us_per_s,
        });
    }
};

pub const GoblinGuard = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Goblin Guard",
    };

    pub fn death(_: *GoblinGuard, host: *Enemy) !void {
        loot.dropCards(host, &.{
            .{ .name = "Thick Plating", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Inpenetrable Ward", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Heavy Strikes", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Arcane Incantations", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Vital Essence", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Font of Magic", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Nimble Feet", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Time Distortion", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Enhanced Fortitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
            .{ .name = "Boundless Aptitude", .chance = 1.0 / 50.0, .threshold = 0.01 },
        });
        loot.dropResources(host, &.{
            .{ .name = "Tiny Magisteel Alloy", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Pine Driftwood", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
            .{ .name = "Solid Magma", .chance = 1.0 / 10.0, .min = 5, .max = 10, .threshold = 0.01 },
        });
        loot.dropCurrency(host, &.{.{ .type = .gold, .chance = 1.0 / 20.0, .min = 10, .max = 17, .threshold = 0.001 }});
        loot.dropPortals(host, &.{.{ .name = "Crown Cove", .chance = 1.0 / 10.0 }});
    }

    pub fn tick(_: *GoblinGuard, host: *Enemy, time: i64, dt: i64) !void {
        if (!(logic.orbit(host, dt, .{
            .speed = 3.0,
            .radius = 2.0,
            .acquire_range = 6.0,
            .target_name = "Crocodile",
        }) or logic.orbit(host, dt, .{
            .speed = 2.5,
            .radius = 2.0,
            .acquire_range = 6.0,
            .target_name = "Spike Ball",
        }))) logic.wander(@src(), host, dt, 1.4);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 5.0,
            .proj_index = 0,
            .count = 2,
            .radius = 16.0,
            .cooldown = 0.8 * std.time.us_per_s,
        });
    }
};

pub const ForestFirefly = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Forest Firefly",
    };

    pub fn tick(_: *ForestFirefly, host: *Enemy, _: i64, dt: i64) !void {
        logic.wander(@src(), host, dt, 2.5);
    }
};

pub const Imp = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Imp",
    };

    pub fn death(_: *Imp, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Crimson Chasm", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *Imp, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.charge(@src(), host, dt, .{
            .speed = 6.0,
            .range = 13.0,
            .cooldown = 0.4 * std.time.us_per_s,
        })) logic.wander(@src(), host, dt, 2.1);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 8.0,
            .proj_index = 0,
            .count = 5,
            .radius = 13.0,
            .cooldown = 0.8 * std.time.us_per_s,
        });
    }
};

pub const LivingFlame = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Living Flame",
    };

    pub fn death(_: *LivingFlame, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Crimson Chasm", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *LivingFlame, host: *Enemy, time: i64, dt: i64) !void {
        logic.wander(@src(), host, dt, 2.2);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 51.0,
            .proj_index = 0,
            .count = 8,
            .radius = 16.0,
            .cooldown = 0.2 * std.time.us_per_s,
        });

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 72.0,
            .proj_index = 0,
            .count = 5,
            .radius = 16.0,
            .cooldown = 0.8 * std.time.us_per_s,
        });
    }
};

pub const DemonMage = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Demon Mage",
    };

    pub fn death(_: *DemonMage, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Crimson Chasm", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *DemonMage, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.orbit(host, dt, .{
            .speed = 3.85,
            .radius = 1.0,
            .acquire_range = 9.0,
            .target_name = "Imp",
        })) logic.wander(@src(), host, dt, 2.15);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 3.0,
            .proj_index = 0,
            .count = 5,
            .radius = 16.0,
            .cooldown = 0.6 * std.time.us_per_s,
        });
    }
};

pub const DemonArcher = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Demon Archer",
    };

    pub fn death(_: *DemonArcher, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Crimson Chasm", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *DemonArcher, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.orbit(host, dt, .{
            .speed = 3.85,
            .radius = 1.0,
            .acquire_range = 9.0,
            .target_name = "Living Flame",
        })) logic.wander(@src(), host, dt, 2.15);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 3.0,
            .proj_index = 0,
            .count = 5,
            .radius = 16.0,
            .cooldown = 0.6 * std.time.us_per_s,
        });
    }
};

pub const JackalWarrior = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Jackal Warrior",
    };

    pub fn death(_: *JackalWarrior, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Dusty Dune", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *JackalWarrior, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.charge(@src(), host, dt, .{
            .speed = 6.0,
            .range = 13.0,
            .cooldown = 0.4 * std.time.us_per_s,
        })) logic.wander(@src(), host, dt, 2.25);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 15.0,
            .proj_index = 0,
            .count = 7,
            .radius = 16.0,
            .cooldown = 0.6 * std.time.us_per_s,
        });
    }
};

pub const JackalPriest = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Jackal Priest",
    };

    pub fn death(_: *JackalPriest, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Dusty Dune", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *JackalPriest, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.orbit(host, dt, .{
            .speed = 3.85,
            .radius = 1.0,
            .acquire_range = 9.0,
            .target_name = "Jackal Archer",
        })) logic.wander(@src(), host, dt, 2.25);

        _ = logic.heal(@src(), host, dt, .{
            .range = 10.0,
            .amount = 250,
            .target_name = "Jackal Warrior",
            .cooldown = 1.0 * std.time.us_per_s,
        }) or logic.heal(@src(), host, dt, .{
            .range = 10.0,
            .amount = 250,
            .target_name = "Jackal Archer",
            .cooldown = 1.0 * std.time.us_per_s,
        }) or logic.heal(@src(), host, dt, .{
            .range = 10.0,
            .amount = 250,
            .target_name = "Regal Mummy",
            .cooldown = 1.0 * std.time.us_per_s,
        });

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 45.0,
            .proj_index = 0,
            .count = 8,
            .radius = 16.0,
            .cooldown = 1.0 * std.time.us_per_s,
        });
    }
};

pub const JackalArcher = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Jackal Archer",
    };

    pub fn death(_: *JackalArcher, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Dusty Dune", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *JackalArcher, host: *Enemy, time: i64, dt: i64) !void {
        if (!logic.follow(@src(), host, dt, .{
            .speed = 3.0,
            .acquire_range = 9.0,
            .cooldown = 1.0 * std.time.us_per_s,
        })) logic.wander(@src(), host, dt, 2.5);

        logic.shoot(@src(), host, time, dt, .{
            .shoot_angle = 5.0,
            .proj_index = 0,
            .count = 4,
            .radius = 16.0,
            .cooldown = 0.3 * std.time.us_per_s,
        });
    }
};

pub const RegalMummy = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Regal Mummy",
    };

    pub fn death(_: *RegalMummy, host: *Enemy) !void {
        loot.dropPortals(host, &.{.{ .name = "Dusty Dune", .chance = 1.0 / 20.0 }});
    }

    pub fn tick(_: *RegalMummy, host: *Enemy, _: i64, dt: i64) !void {
        if (!logic.follow(@src(), host, dt, .{
            .speed = 3.0,
            .acquire_range = 9.0,
            .cooldown = 1.0 * std.time.us_per_s,
        })) logic.wander(@src(), host, dt, 2.5);

        logic.aoe(@src(), host, dt, .{
            .radius = 3.0,
            .magic_dmg = 150,
            .cooldown = 0.3 * std.time.us_per_s,
            .conditions = &.{.{ .type = .slowed, .duration = 0.1 * std.time.us_per_s }},
            .color = 0x01361F,
        });
    }
};
