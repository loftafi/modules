pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var input_dictionary: ?[]const u8 = null;
    var output_dictionary: ?[]const u8 = null;
    var mode: Dictionary.SaveMode = .all_words;
    var byzantine_read: bool = false;
    var nestle_read: bool = false;

    var args = init.minimal.args.iterate();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-i")) {
            input_dictionary = args.next() orelse {
                help();
                return;
            };
            continue;
        }
        if (std.mem.eql(u8, arg, "-o")) {
            output_dictionary = args.next() orelse {
                help();
                return;
            };
            continue;
        }
        if (std.mem.eql(u8, arg, "--all_vocab")) {
            mode = .gnt_words;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gnt_vocab")) {
            mode = .gnt_words;
            continue;
        }
        if (std.mem.eql(u8, "byz", arg)) {
            byzantine_read = true;
            continue;
        }
        if (std.mem.eql(u8, "nestle", arg)) {
            nestle_read = true;
            continue;
        }
        help();
        return;
    }

    if (input_dictionary == null) {
        help();
        return;
    }

    // Load the dictionary of words before loading text modules
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    var dictionary = try Dictionary.create(arena.allocator());
    errdefer dictionary.destroy(arena.allocator());
    try dictionary.loadFile(arena.allocator(), gpa, io, input_dictionary.?);

    if (byzantine_read) {
        var module = Module.init();
        var byzantine_reader = try byzantine.reader().init(gpa, io, true);
        try module.read(gpa, io, &byzantine_reader);
        try module.saveText(gpa, io);
        try module.saveBinary(gpa, io);
    }

    if (nestle_read) {
        var module = Module.init();
        var nestle_reader = try nestle.reader().init(gpa, io, true);
        try module.read(gpa, io, &nestle_reader);
        try module.saveText(gpa, io);
        try module.saveBinary(gpa, io);
    }

    if (output_dictionary) |out|
        try dictionary.saveBinaryFile(arena.allocator(), io, .cwd(), out, .all_words);
}

fn help() void {
    print("Specify a valid command.\n", .{});
    print("  dictionary -i [intput_dictionary] -o [output_dictinary] --all_vocab --gnt_vocab [byz] [nestle]\n", .{});
    print("\n", .{});
    print("  dictionary -i resources/dictionary/dictionary.txt -o generated/dictionary.bin by \n", .{});
    print("\n", .{});
}

const std = @import("std");
const debug = std.log.debug;
const print = std.debug.print;

const praxis = @import("praxis");
const Dictionary = praxis.Dictionary;

const modules = @import("modules");
const Module = modules.Module;
const byzantine = modules.byzantine;
const nestle = modules.nestle;
