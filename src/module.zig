/// An arbitrarily large number of tokens that should be impossible to reach.
/// If we hit this number the tokenizer is likly not performing correctly.
pub const max_token_guard: usize = 10000000;

/// A module is a sequence of paragraphs that we will display to a reader.
pub const Module = struct {
    module: praxis.Module,

    /// A list of all paragraphs in the module, along with internal
    /// verse number markers.
    paragraphs: std.ArrayList(Paragraph),

    /// A list of all verses in the module.
    verses: std.ArrayList(Verse),

    /// An empty module to prepare for calling `read()`
    pub const empty: Module = .{
        .module = .unknown,
        .paragraphs = .empty,
        .verses = .empty,
    };

    pub fn deinit(self: *Module, gpa: Allocator) void {
        for (self.paragraphs.items) |*paragraph| {
            paragraph.deinit(gpa);
        }
        self.paragraphs.deinit(gpa);
        self.verses.deinit(gpa);
    }

    /// Fill the contents of this module using a custom `reader` that
    /// understands the data format of that content source.
    pub fn import(
        self: *Module,
        allocator: Allocator,
        io: std.Io,
        reader: anytype,
    ) !void {
        var verses: ArrayList(Verse) = .empty;
        var words: ArrayList(Word) = .empty;
        defer verses.deinit(allocator);
        defer words.deinit(allocator);

        var text: std.Io.Writer.Allocating = .init(allocator);
        defer text.deinit();

        self.module = reader.module();
        debug("reading {s} module data", .{self.module});

        var token_count: usize = 0;
        var annotation_skip = false;
        while (true) {
            if (token_count > max_token_guard) break;
            const t = verse_paragrah_flipper(allocator, io, reader) catch |e| {
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
                    if (text.written().len == 0) continue;
                    try self.paragraphs.append(allocator, .{
                        .text = try allocator.dupe(u8, text.written()),
                        .verses = try verses.toOwnedSlice(allocator),
                        .words = try words.toOwnedSlice(allocator),
                    });
                    text.clearRetainingCapacity();
                    verses = .empty;
                    words = .empty;
                },
                .verse => {
                    if (text.written().len > 0) try text.writer.writeByte(' ');
                    const ref = t.verse;
                    if (ref.verse == 1) {
                        try text.writer.print("{d}:{d}", .{
                            ref.chapter,
                            ref.verse,
                        });
                    } else {
                        try text.writer.print("{d}", .{
                            ref.verse,
                        });
                    }
                    //try text.appendSlice(allocator, try reader.value());
                    try verses.append(allocator, .{
                        .reference = t.verse,
                        .paragraph = @as(u32, @intCast(self.paragraphs.items.len)),
                        .index = text.written().len,
                    });
                    try self.verses.append(allocator, .{
                        .reference = t.verse,
                        .paragraph = @as(u32, @intCast(self.paragraphs.items.len)),
                        .index = text.written().len,
                    });
                },
                .word => {
                    // word token  text is a slice of a temporary buffer.
                    // append word bytes to paragraph along with `Word`
                    // index/slice pointers to the word.
                    if (text.written().len > 0) try text.writer.writeByte(' ');
                    const i = text.written().len;
                    try text.writer.writeAll(t.word.text);
                    try words.append(allocator, .{
                        .text_start = @as(u16, @intCast(i)),
                        .text_end = @as(u16, @intCast(i + t.word.text.len)),
                        .word_start = @as(u16, @intCast(i)),
                        .word_end = @as(u16, @intCast(i + t.word.text.len)),
                        .parsing = .default,
                    });
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
                    if (text.written().len > 0) {
                        try self.paragraphs.append(allocator, .{
                            .text = try allocator.dupe(u8, text.written()),
                            .verses = try verses.toOwnedSlice(allocator),
                            .words = try words.toOwnedSlice(allocator),
                        });
                        verses = .empty;
                        words = .empty;
                    }
                    break;
                },
                .unknown => {
                    unreachable;
                },
                .invalid_token => {
                    std.log.err(
                        "Failed reading {s} module. '{s}' invalid_token",
                        .{ @tagName(reader.module()), reader.debug_slice() },
                    );
                    return error.UnexpectedCharacter;
                },
            }
            token_count += 1;
        }

        debug("found {d} tokens, {d} paragraphs, {d} verses in {s} module data", .{
            token_count,
            self.paragraphs.items.len,
            self.verses.items.len,
            @tagName(reader.module()),
        });
    }

    /// Output a module in a plain human readable text format.
    pub fn saveText(
        self: *Module,
        allocator: Allocator,
        io: std.Io,
        folder: *std.Io.Dir,
    ) (Allocator.Error || std.Io.File.OpenError || std.Io.Writer.Error)!void {
        const filename = try allocator.print("{t}.txt", .{self.module});
        defer allocator.free(filename);
        info("outputting text module {t} to {s}", .{ self.module, filename });

        const file = try folder.createFile(io, filename, .{ .truncate = true });
        defer file.close(io);
        var buffer: [1024 * 5]u8 = undefined;
        var out = file.writer(io, &buffer);
        var writer = &out.interface;

        var reference: Reference = .unknown;
        for (self.paragraphs.items) |paragraph| {
            if (paragraph.verses.len > 0) {
                if (reference.book != paragraph.verses[0].reference.book) {
                    debug("generating next paragraph.verses={d} for {s} ({any})", .{
                        paragraph.verses.len,
                        filename,
                        paragraph.verses[0].reference.module,
                    });
                    reference = paragraph.verses[0].reference;
                    const book_info = reference.book.info();
                    try writer.print("# {s}", .{book_info.english});
                    try writer.writeAll("\n\n");
                }
            }
            try writer.writeAll(paragraph.text);
            try writer.writeAll("\n\n");
        }
        try writer.flush();
        debug("generated {s}", .{filename});
    }

    /// Save the module in a binary format.
    pub fn saveBinary(
        self: *Module,
        allocator: Allocator,
        io: std.Io,
        folder: *std.Io.Dir,
    ) (std.Io.Writer.Error||std.Io.File.OpenError||Allocator.Error)!void {
        const filename = try allocator.print("{t}.bin", .{self.module});
        defer allocator.free(filename);
        info("outputting binary module {t} to {s}", .{ self.module, filename });

        const file = try folder.createFile(io, filename, .{ .truncate = true });
        defer file.close(io);

        var buffer: [1024 * 5]u8 = undefined;
        var out = file.writer(io, &buffer);
        var writer = &out.interface;

        try self.writeBinary(writer);
        try writer.flush();

        debug("generated {s}", .{filename});
    }

    /// Write the module to a writer in binary format.
    fn writeBinary(
        self: *Module,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        var header: [6]u8 = undefined;
        header[0] = @as(u8, @intCast(praxis.random.random(255)));
        header[1] = @as(u8, @intCast(praxis.random.random(255)));
        header[2] = @as(u8, @intCast(praxis.random.random(255)));
        header[3] = header[0] ^ 99;
        header[4] = header[1] ^ 109;
        header[5] = header[2] ^ 213;
        try writer.writeAll(&header);
        try writer.writeByte(1);

        try writer.writeInt(u16, @as(u16, @backingInt(self.module)), .little);
        try writer.writeInt(u32, @as(u32, @intCast(self.paragraphs.items.len)), .little);

        for (self.paragraphs.items) |paragraph| {
            try paragraph.writeBinary(writer);
        }
    }

    /// Read a binary module file
    pub fn loadBinary(
        self: *Module,
        gpa: Allocator,
        io: std.Io,
    ) Allocator.Error!void {
        const filename = try gpa.print("generated/{t}.bin", .{self.module});
        defer gpa.free(filename);
        const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
        defer file.close(io);
        var buffer: [1024 * 5]u8 = undefined;
        const reader = file.reader(io, &buffer);
        self.readBinary(gpa, reader);
    }

    fn readBinary(self: *Module, gpa: Allocator, reader: *std.Io.Reader) (std.Io.Reader.Error || Error)!void {
        var header: [6]u8 = undefined;
        try reader.readSliceAll(&header);

        const version = try reader.takeByte();
        if (version != 1) return Error.InvalidModuleVersion;
        const module: praxis.Module = @fromBackingInt(@intCast(try reader.takeInt(u16, .little)));

        const paragraph_counter: u32 = try reader.takeInt(u32, .little);
        const verse_counter: u32 = try reader.takeInt(u32, .little);
        var paragraphs: []Paragraph = try gpa.alloc(Paragraph, paragraph_counter);
        for (0..paragraph_counter) |i| {
            paragraphs[i] = try Paragraph.readBinary(reader, gpa, module, i);
            verse_counter += paragraphs[i].verses.len;
        }

        var verses: []Verse = try gpa.alloc(Verse, verse_counter);
        var index: usize = 0;
        for (paragraphs) |paragraph| {
            @memcpy(verses[index..], paragraph.verses);
            index += paragraph.verses.len;
        }

        self.module = module;
        if (self.paragraphs.len > 0) gpa.free(self.paragraphs);
        if (self.verses.len > 0) gpa.free(self.verses);
        self.paragraphs = paragraphs;
    }
};

pub const Error = error{
    InvalidModuleVersion,
    InvalidModuleData,
};

var vp_carry: ?Token = null;

fn verse_paragrah_flipper(allocator: Allocator, io: std.Io, reader: anytype) !Token {
    const token = try reader.next(allocator, io);
    if (vp_carry != null) {
        const t = vp_carry.?;
        vp_carry = null;
        return t;
    }
    if (token == .verse) {
        const next = try reader.next(allocator, io);
        if (next == .paragraph) {
            vp_carry = token;
            return next;
        } else {
            vp_carry = next;
            return token;
        }
    }
    return token;
}

/// A paragraph is a small unit of text that belongs to a module.
/// A paragraph contains of words that can be tagged. Verse numbers
/// are attached to words in a paragraph.
pub const Paragraph = struct {
    /// Base text of the paragraph.
    text: []const u8,

    /// A pointer to each word in the paragraph.
    words: []Word,

    /// List of verse markers that appear in this paragraph
    verses: []Verse,

    pub fn deinit(self: *Paragraph, gpa: Allocator) void {
        gpa.free(self.text);
        gpa.free(self.words);
        gpa.free(self.verses);
        self.* = undefined;
    }

    pub fn writeBinary(self: *const Paragraph, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeInt(u32, @as(u32, @intCast(self.text.len)), .little);
        try writer.writeAll(self.text);
        try writer.writeInt(u16, @as(u16, @intCast(self.words.len)), .little);
        for (self.words) |word| {
            try writer.writeInt(u16, @as(u16, @intCast(word.text_start)), .little);
            try writer.writeInt(u16, @as(u16, @intCast(word.text_end)), .little);
            try writer.writeInt(u16, @as(u16, @intCast(word.word_start)), .little);
            try writer.writeInt(u16, @as(u16, @intCast(word.word_end)), .little);
            try writer.writeInt(u32, @as(u32, @backingInt(word.parsing)), .little);
        }
        try writer.writeInt(u16, @as(u16, @intCast(self.verses.len)), .little);
        for (self.verses) |verse| {
            try writer.writeInt(u16, @as(u16, @intCast(verse.index)), .little);
            try writer.writeInt(u16, @as(u16, @backingInt(verse.reference.book)), .little);
            try writer.writeInt(u16, @as(u16, @intCast(verse.reference.chapter)), .little);
            try writer.writeInt(u16, @as(u16, @intCast(verse.reference.verse)), .little);
        }
    }

    pub fn readBinary(
        reader: *std.Io.Reader,
        gpa: Allocator,
        module: praxis.Module,
        paragraph_counter: u32,
    ) (std.Io.Reader.Error || Allocator.Error)!Paragraph {
        const len = try reader.takeInt(u32, .little);
        var text = try gpa.alloc(u8, len);
        reader.readSliceAll(&text);
        const word_count = try reader.takeInt(u16, .little);
        var words = try gpa.alloc(Word, word_count);
        for (0..word_count) |i| {
            words[i] = .{
                .text_start = try reader.takeInt(u16, .little),
                .text_end = try reader.takeInt(u16, .little),
                .word_start = try reader.takeInt(u16, .little),
                .word_end = try reader.takeInt(u16, .little),
                .parsing = try reader.takeInt(u32, .little),
            };
        }
        const verse_count = try reader.takeInt(u16, .little);
        var verses = try gpa.alloc(Verse, verse_count);
        for (0..verse_count) |i| {
            verses[i] = .{
                .reference = .{
                    .module = module,
                    .book = @fromBackingInt(@intCast(try reader.takeInt(u16, .little))),
                    .chapter = try reader.takeInt(u16, .little),
                    .verse = try reader.takeInt(u16, .little),
                },
                .paragraph = paragraph_counter,
                .index = try reader.takeInt(u16, .little),
            };
        }
    }
};

/// A verse is a marker or bookmark into paragraphs of a module.
pub const Verse = struct {
    reference: Reference,

    /// Index to which paragraph in a module this verse points to.
    paragraph: u32,

    /// Index to which character in a paragraph this verse points to.
    index: usize,
};

/// A word is a slice of the paragraph text.
pub const Word = struct {
    /// The first character of a word with any preceeding or trailing punctuation.
    text_start: u16,
    /// The end of a word with any trailing punctuation.
    text_end: u16,

    /// The first character of the word, skipping any punctuation.
    word_start: u16,
    /// The end of the word, excluding any trailing punctuation.
    word_end: u16,

    /// User or module provided parsing
    parsing: praxis.Parsing,

    pub fn text(self: *const Word, data: []const u8) []const u8 {
        return data[self.text_start..self.text_end];
    }

    pub fn word(self: *const Word, data: []const u8) []const u8 {
        return data[self.word_start..self.word_end];
    }
};

/// A word is a slice of the paragraph text.
pub const ImportedWord = struct {
    /// Word from imported source, including any leading or trailing punctuation.
    text: []const u8,

    /// Word from imported source not including trailing or leading punctuation.
    word: []const u8,
};

pub const TokenType = enum {
    unknown,
    verse,
    word,
    strongs,
    parsing,
    paragraph,
    variant_mark,
    variant_alt,
    variant_end,
    invalid_token,
    eof,
};

pub const Token = union(TokenType) {
    unknown: void,
    verse: Reference,
    word: ImportedWord,
    strongs: [2]u16,
    parsing: praxis.Parsing,
    paragraph: void,
    variant_mark: void,
    variant_alt: void,
    variant_end: void,
    invalid_token: []const u8,
    eof: void,
};

pub fn load_file_bytes(
    allocator: Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    filename: []const u8,
) ![]u8 {
    return try dir.readFileAlloc(io, filename, allocator, .unlimited);
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

    const book_info = praxis.Book.parse(filename[i..j]);
    if (book_info == .unknown) {
        err("Unable to convert filename {s} value {s} into book name.", .{
            filename,
            filename[i..j],
        });
    }
    return book_info;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const err = std.log.err;
const info = std.log.info;
const debug = std.log.debug;

const praxis = @import("praxis");
const Reference = praxis.Reference;
