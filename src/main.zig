pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Load the dictionary of words before loading text modules
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    var dictionary = try Dictionary.create(arena.allocator());
    errdefer dictionary.destroy(arena.allocator());
    try dictionary.loadFile(arena.allocator(), "resources/dictionary/dictionary.txt");
    try dictionary.saveBinaryFile("generated/dictionary.bin", false);

    var module = Module.init();
    var byzantine_reader = try byzantine.reader().init(gpa, init.io, true);
    try module.read(gpa, &byzantine_reader);
    try module.saveText(gpa);
    try module.saveBinary(gpa);

    module = Module.init();
    var nestle_reader = try nestle.reader().init(gpa, init.io, true);
    try module.read(gpa, &nestle_reader);
    try module.saveText(gpa);
    try module.saveBinary(gpa);
}

const std = @import("std");
const debug = std.log.debug;

const praxis = @import("praxis");
const Dictionary = praxis.Dictionary;

const Module = @import("modules.zig").Module;
const byzantine = @import("byzantine.zig");
const nestle = @import("nestle.zig");
