pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    // Load the dictionary of words before loading text modules
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    var dictionary = try Dictionary.create(arena.allocator());
    errdefer dictionary.destroy(arena.allocator());
    try dictionary.loadFile(arena.allocator(), "resources/dictionary/dictionary.txt");
    try dictionary.saveBinaryFile("resources/dictionary/dictionary.bin", false);

    var byzantine_reader = try byzantine.reader().init(allocator);
    var module = Module{};
    try module.read(allocator, &byzantine_reader);
    try module.saveText();
    try module.saveBinary();

    var nestle_reader = try nestle.reader().init(allocator);
    module = Module{};
    try module.read(allocator, &nestle_reader);
    try module.saveText();
    try module.saveBinary();
}

const std = @import("std");
const debug = std.log.debug;

const praxis = @import("praxis");
const Dictionary = praxis.Dictionary;

const Module = @import("modules.zig").Module;
const byzantine = @import("byzantine.zig");
const nestle = @import("nestle.zig");
