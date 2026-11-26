pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var input_dictionary: ?[]const u8 = null;
    var output_dictionary: ?[]const u8 = null;
    var mode: Dictionary.SaveMode = .all_words;
    var byzantine_out: ?[]const u8 = null;
    var nestle_out: ?[]const u8 = null;

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
            mode = .all_words;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gnt_vocab")) {
            mode = .gnt_words;
            continue;
        }
        if (std.mem.eql(u8, "-byz", arg)) {
            byzantine_out = args.next() orelse {
                help();
                return;
            };
            continue;
        }
        if (std.mem.eql(u8, "-nestle", arg)) {
            nestle_out = args.next() orelse {
                help();
                return;
            };
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
    defer arena.deinit();
    var dictionary = try Dictionary.create(arena.allocator());
    defer dictionary.destroy();
    try dictionary.loadFile(gpa, io, input_dictionary.?);

    if (byzantine_out) |folder| {
        var output_dir = try std.Io.Dir.cwd().openDir(io, folder, .{});
        defer output_dir.close(io);
        var module: Module = .empty;
        defer module.deinit(gpa);
        var reader = try Byzantine.reader().init(gpa, io, true);
        defer reader.deinit(gpa);
        try module.import(gpa, io, &reader);
        try module.saveText(gpa, io, &output_dir);
        try module.saveBinary(gpa, io, &output_dir);
    }

    if (nestle_out) |folder| {
        var output_dir = try std.Io.Dir.cwd().openDir(io, folder, .{});
        defer output_dir.close(io);
        var module: Module = .empty;
        defer module.deinit(gpa);
        var reader = try Nestle.reader().init(gpa, io, true);
        defer reader.deinit(gpa);
        try module.import(gpa, io, &reader);
        try module.saveText(gpa, io, &output_dir);
        try module.saveBinary(gpa, io, &output_dir);
    }

    if (output_dictionary) |out|
        try dictionary.saveBinaryFile(arena.allocator(), io, .cwd(), out, mode);
}

fn help() void {
    print("Specify a valid command:\n", .{});
    print("  modules -i [intput_dictionary] -o [output_dictinary] --all_vocab --gnt_vocab [-byz outdir] [-nestle outdir]\n", .{});
    print("\n", .{});
    print("  modules -i resources/dictionary/dictionary.txt -o generated/dictionary.bin\n", .{});
    print("  modules -i resources/dictionary/dictionary.txt -byz generated \n", .{});
    print("\n", .{});
}

const std = @import("std");
const debug = std.log.debug;
const print = std.debug.print;

const praxis = @import("praxis");
const Dictionary = praxis.Dictionary;

const modules = @import("modules");
const Module = modules.Module;
const Byzantine = modules.Byzantine;
const Nestle = modules.Nestle;
