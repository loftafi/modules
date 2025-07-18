pub const max_token_guard: usize = 10000000;

/// A module is a sequence of paragraphs that we will display to a reader.
pub const Module = struct {
    paragraphs: std.ArrayListUnmanaged(Paragraph) = .empty,
    verses: std.ArrayListUnmanaged(Verse) = .empty,
    module: []const u8 = "",

    pub fn init() Module {
        return .{
            .paragraphs = .empty,
            .verses = .empty,
            .module = "",
        };
    }

    pub fn read(self: *Module, allocator: Allocator, reader: anytype) !void {
        var paragraphs: std.ArrayListUnmanaged(Paragraph) = .empty;
        var all_verses: std.ArrayListUnmanaged(Verse) = .empty;
        var paragraph_verses: std.ArrayListUnmanaged(Verse) = .empty;
        var text: std.ArrayListUnmanaged(u8) = .empty;
        var token_count: usize = 0;
        var annotation_skip = false;

        self.module = @tagName(reader.module());
        debug("reading {s} module data", .{self.module});

        while (true) {
            if (token_count > max_token_guard) break;
            const t = reader.next(allocator) catch |e| {
                std.log.err("Failed reading {s} module. '{s}' {any}", .{
                    @tagName(reader.module()),
                    reader.debug_slice(),
                    e,
                });
                return e;
            };
            if (annotation_skip == true and t != .variant_end) {
                continue;
            }
            switch (t) {
                .paragraph => {
                    if (text.items.len == 0) continue;
                    try paragraphs.append(allocator, .{
                        .text = try allocator.dupe(u8, text.items),
                        .verses = paragraph_verses,
                        .words = .empty,
                    });
                    text = .empty;
                    paragraph_verses = .empty;
                },
                .verse => {
                    if (text.items.len > 0) try text.append(allocator, ' ');
                    const ref = reader.reference();
                    if (ref.verse == 1) {
                        try text.writer(allocator).print("{d}:{d}", .{
                            ref.chapter,
                            ref.verse,
                        });
                    } else {
                        try text.writer(allocator).print("{d}", .{
                            ref.verse,
                        });
                    }
                    //try text.appendSlice(allocator, try reader.value());
                    try paragraph_verses.append(allocator, .{
                        .reference = reader.reference(),
                        .paragraph = paragraphs.items.len,
                        .index = text.items.len,
                    });
                    try all_verses.append(allocator, .{
                        .reference = reader.reference(),
                        .paragraph = paragraphs.items.len,
                        .index = text.items.len,
                    });
                },
                .word => {
                    if (text.items.len > 0) try text.append(allocator, ' ');
                    try text.appendSlice(allocator, reader.greek());
                    if (reader.punctuation()) |punctuation| {
                        try text.appendSlice(allocator, punctuation);
                    }
                },
                .strongs => {
                    //
                },
                .parsing => {
                    //
                },
                .variant_end => {
                    annotation_skip = false;
                },
                .variant_mark, .variant_alt => {
                    annotation_skip = true;
                },
                .eof => {
                    if (text.items.len > 0) {
                        try paragraphs.append(allocator, .{
                            .text = try allocator.dupe(u8, text.items),
                            .verses = paragraph_verses,
                            .words = .empty,
                        });
                    }
                    break;
                },
                .unknown => {
                    unreachable;
                },
                .unexpected_character => {
                    std.log.err(
                        "Failed reading {s} module. '{s}' UnexpectedCharacter",
                        .{ @tagName(reader.module()), reader.debug_slice() },
                    );
                    return error.UnexpectedCharacter;
                },
            }
            token_count += 1;
        }
        self.paragraphs = paragraphs;
        self.verses = all_verses;

        debug("found {d} tokens, {d} paragraphs, {d} verses in {s} module data", .{
            token_count,
            paragraphs.items.len,
            all_verses.items.len,
            @tagName(reader.module()),
        });
    }

    pub fn saveText(self: *Module, allocator: Allocator) !void {
        const filename = try std.fmt.allocPrint(allocator, "generated/{s}.txt", .{self.module});
        debug("generating {s}", .{filename});
        defer allocator.free(filename);
        const file = try std.fs.cwd().createFile(filename, .{ .truncate = true });
        defer file.close();
        var reference: Reference = .unknown;
        for (self.paragraphs.items) |paragraph| {
            if (paragraph.verses.items.len > 0) {
                if (reference.book != paragraph.verses.items[0].reference.book) {
                    debug("generating next paragraph.verses={d} for {s} ({any})", .{
                        paragraph.verses.items.len,
                        filename,
                        paragraph.verses.items[0].reference.module,
                    });
                    reference = paragraph.verses.items[0].reference;
                    const info = reference.book.info();
                    try file.writer().print("# {s}", .{info.english});
                    try file.writeAll("\n\n");
                }
            }
            try file.writeAll(paragraph.text);
            try file.writeAll("\n\n");
        }
        return;
    }

    pub fn saveBinary(self: *Module, allocator: Allocator) !void {
        const filename = try std.fmt.allocPrint(allocator, "generated/{s}.bin", .{self.module});
        defer allocator.free(filename);
        const file = try std.fs.cwd().createFile(filename, .{ .truncate = true });
        defer file.close();
        for (self.paragraphs.items) |paragraph| {
            //try file.writeAll(paragraph.words.items);
            try file.writeAll(paragraph.text);
            try file.writeAll("\n\n");
        }
        return;
    }
};

/// A paragraph is a small unit of text that belongs to a module.
/// a paragraph consists of words that can be tagged.
pub const Paragraph = struct {
    /// Base text of the paragraph.
    text: []const u8 = "",

    /// A pointer to each word in the paragraph.
    words: std.ArrayListUnmanaged(Word) = .empty,

    /// List of verse markers that appear in this paragraph
    verses: std.ArrayListUnmanaged(Verse) = .empty,
};

/// A verse is a marker or bookmark into paragraphs of a module.
pub const Verse = struct {
    reference: Reference = .unknown,

    /// Index to which paragraph in a module this verse points to.
    paragraph: usize = 0,

    /// Index to which character in a paragraph this verse points to.
    index: usize = 0,
};

/// A word is a slice of the paragraph data.
pub const Word = struct {
    text: []const u8 = "",
    word: []const u8 = "",
};

pub const TextToken = enum {
    unknown,
    verse,
    word,
    strongs,
    parsing,
    paragraph,
    variant_mark,
    variant_alt,
    variant_end,
    unexpected_character,
    eof,
};

pub fn load_file_bytes(
    allocator: Allocator,
    dir: std.fs.Dir,
    filename: []const u8,
) ![]u8 {
    const file = dir.openFile(
        filename,
        .{ .mode = .read_only },
    ) catch |e| {
        std.log.err("Resource file missing: {s}", .{filename});
        return e;
    };
    defer file.close();
    const stat = try file.stat();
    return try file.readToEndAlloc(allocator, stat.size);
}

pub fn remove_bom(data: []u8) []u8 {
    if (data.len >= 3) {
        if (data[0] == 239 and data[1] == 187 and data[2] == 191) {
            return data[3..];
        }
    }
    return data;
}

pub fn extract_book_from_filename(filename: []const u8) praxis.Book {
    var i: usize = 0;
    while (i < filename.len and filename[i] != '_' and filename[i] != '-')
        i += 1;
    i += 1;
    if (i >= filename.len) {
        err("Unable to convert filename {s} into book name.", .{
            filename,
        });
        return praxis.Book.unknown;
    }

    var j: usize = i;
    while (j < filename.len and filename[j] != '.' and filename[j] != '-')
        j += 1;

    const info = praxis.Book.parse(filename[i..j]);
    if (info.value == praxis.Book.unknown) {
        err("Unable to convert filename {s} value {s} into book name.", .{
            filename,
            filename[i..j],
        });
    }
    return info.value;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const err = std.log.err;
const debug = std.log.debug;

const praxis = @import("praxis");
const Reference = praxis.Reference;
