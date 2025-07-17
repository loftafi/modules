pub const max_token_guard: usize = 10000000;

pub fn read(allocator: *Allocator, reader: anytype) !Module {
    var paragraphs: std.ArrayListUnmanaged(Paragraph) = .empty;
    var verses: std.ArrayListUnmanaged(Verse) = .empty;
    var text: std.ArrayListUnmanaged(u8) = .empty;
    var token_count: usize = 0;
    var annotation_skip = false;

    while (true) {
        if (token_count > max_token_guard) break;
        const t = reader.next() catch |e| {
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
                paragraphs.append(.{
                    .text = allocator.dupe(u8, text.items),
                    .words = .empty,
                });
                text.clearAndRetainCapacity();
            },
            .verse => {
                if (text.items.len > 0)
                    text.append(allocator, ' ');
                text.appendSlice(allocator, reader.value());
                verses.append(.{
                    .reference = .{},
                    .paragraph = paragraphs.items.len,
                    .index = text.items.len,
                });
            },
            .word => {
                if (text.items.len > 0)
                    text.append(allocator, ' ');
                text.appendSlice(allocator, reader.value());
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
                    paragraphs.append(.{
                        .text = allocator.dupe(u8, text.items),
                        .words = .empty,
                    });
                }
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
    return .{
        .paragraphs = paragraphs,
        .verses = verses,
    };
}

/// A module is a sequence of paragraphs that we will display to a reader.
pub const Module = struct {
    paragraphs: std.ArrayListUnmanaged(Paragraph),
    verses: std.ArrayListUnmanaged(Verse),

    pub fn save_text(allocator: *Allocator) !Module {
        _ = allocator;
    }

    pub fn save_binary(allocator: *Allocator) !Module {
        _ = allocator;
    }
};

/// A paragraph is a small unit of text that belongs to a module.
/// a paragraph consists of words that can be tagged.
pub const Paragraph = struct {
    /// Base text of the paragraph.
    text: []const u8,

    /// A pointer to each word in the paragraph.
    words: std.ArrayListUnmanaged(Word),
};

/// A verse is a marker or bookmark into paragraphs of a module.
pub const Verse = struct {
    reference: Reference,

    /// Index to which paragraph in a module this verse points to.
    paragraph: usize,

    /// Index to which character in a paragraph this verse points to.
    index: usize,
};

/// A word is a slice of the paragraph data.
pub const Word = struct {
    text: []const u8,
    word: []const u8,
};

pub const TextToken = enum {
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
    if (i >= filename.len)
        return .unknown;

    var j: usize = i;
    while (j < filename.len and filename[j] != '.' and filename[j] != '-')
        j += 1;

    return praxis.Book.parse(filename[i..j]).value;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const praxis = @import("praxis");
const Reference = praxis.Reference;
