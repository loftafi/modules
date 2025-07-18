pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    // Load the dictionary of words before loading text modules
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    var dictionary = try Dictionary.create(arena.allocator());
    errdefer dictionary.destroy(arena.allocator());
    try dictionary.loadFile(arena.allocator(), "resources/dictionary/dictionary.txt");
    try dictionary.saveBinaryFile("generated/dictionary.bin", false);

    var module = Module.init();
    var byzantine_reader = try byzantine.reader().init(allocator, true);
    try module.read(allocator, &byzantine_reader);
    try module.saveText(allocator);
    try module.saveBinary(allocator);

    module = Module.init();
    var nestle_reader = try nestle.reader().init(allocator, true);
    try module.read(allocator, &nestle_reader);
    try module.saveText(allocator);
    try module.saveBinary(allocator);
}

const std = @import("std");
const debug = std.log.debug;

const praxis = @import("praxis");
const Dictionary = praxis.Dictionary;

const Module = @import("modules.zig").Module;
const byzantine = @import("byzantine.zig");
const nestle = @import("nestle.zig");
