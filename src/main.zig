pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var byzantine_reader = try byzantine.reader().init(allocator);
    const byzantine_module = try module.read(allocator, &byzantine_reader);
    byzantine_module.save_text("generated/");
    byzantine_module.save_binary("generated/");

    var nestle_reader = try nestle.reader().init(allocator);
    const nestle_module = try module.read(allocator, &nestle_reader);
    nestle_module.save_text("generated/");
    nestle_module.save_binary("generated/");

    // Additional non-public domain modules
    var sbl_reader = try sbl.reader().init(allocator);
    const sbl_module = try module.read(allocator, &sbl_reader);
    sbl_module.save_text("generated/");
    sbl_module.save_binary("generated/");
}

const std = @import("std");

const module = @import("modules.zig");
const byzantine = @import("byzantine.zig");
const nestle = @import("nestle.zig");

// Additional modules that are not public domain
const sbl = @import("sbl.zig");
