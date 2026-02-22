pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Load the dictionary of words before loading text modules
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    var dictionary = try Dictionary.create(arena.allocator());
    errdefer dictionary.destroy(arena.allocator());
    try dictionary.loadFile(
        arena.allocator(),
        gpa,
        io,
        "resources/dictionary/dictionary.txt",
    );
    try dictionary.saveBinaryFile(
        arena.allocator(),
        io,
        .cwd(),
        "generated/dictionary.bin",
        .all_words,
    );

    var module = Module.init();
    var byzantine_reader = try byzantine.reader().init(gpa, io, true);
    try module.read(gpa, io, &byzantine_reader);
    try module.saveText(gpa, io);
    try module.saveBinary(gpa, io);

    module = Module.init();
    var nestle_reader = try nestle.reader().init(gpa, io, true);
    try module.read(gpa, io, &nestle_reader);
    try module.saveText(gpa, io);
    try module.saveBinary(gpa, io);
}

const std = @import("std");
const debug = std.log.debug;

const praxis = @import("praxis");
const Dictionary = praxis.Dictionary;

const Module = @import("module.zig").Module;

const byzantine = @import("byzantine.zig");
const nestle = @import("nestle.zig");
