pub const folder = "resources/sbl";

pub const files = [_][]const u8{
    "61-Mt-morphgnt.txt",  "62-Mk-morphgnt.txt",  "63-Lk-morphgnt.txt",
    "64-Jn-morphgnt.txt",  "65-Ac-morphgnt.txt",  "66-Ro-morphgnt.txt",
    "67-1Co-morphgnt.txt", "68-2Co-morphgnt.txt", "69-Ga-morphgnt.txt",
    "70-Eph-morphgnt.txt", "71-Php-morphgnt.txt", "72-Col-morphgnt.txt",
    "73-1Th-morphgnt.txt", "74-2Th-morphgnt.txt", "75-1Ti-morphgnt.txt",
    "76-2Ti-morphgnt.txt", "77-Tit-morphgnt.txt", "78-Phm-morphgnt.txt",
    "79-Heb-morphgnt.txt", "80-Jas-morphgnt.txt", "81-1Pe-morphgnt.txt",
    "82-2Pe-morphgnt.txt", "83-1Jn-morphgnt.txt", "84-2Jn-morphgnt.txt",
    "85-3Jn-morphgnt.txt", "86-Jud-morphgnt.txt", "87-Re-morphgnt.txt",
};

pub fn reader() type {
    return struct {
        const Self = @This();
        data: []u8,
        parser: SblParser,
        files_index: usize,

        pub fn init(allocator: Allocator) !Self {
            const dir = try std.fs.cwd().openDir(folder, .{ .iterate = false });
            const data = try load_file_bytes(allocator, dir, files[0]);
            var parser = SblParser.init(data);
            parser.reference.module = .sbl;
            parser.reference.book = extract_book_from_filename(sbl_book_name(files[0]));
            return .{
                .data = data,
                .parser = parser,
                .files_index = 0,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
        }

        pub fn value(self: *Self) ![]const u8 {
            return self.parser.value;
        }

        pub fn word(self: *Self) ![]const u8 {
            return self.parser.word;
        }

        pub fn greek(self: *Self) []const u8 {
            return self.parser.word;
        }

        pub fn next(self: *Self, allocator: Allocator) !TextToken {
            var token = try self.parser.next();
            if (token == .eof and self.files_index < files.len) {
                const dir = try std.fs.cwd().openDir(folder, .{});
                allocator.free(self.data);
                self.data = try load_file_bytes(allocator, dir, files[self.files_index]);
                self.parser = SblParser.init(self.data);
                self.parser.reference.book = extract_book_from_filename(sbl_book_name(files[self.files_index]));
                token = try self.parser.next();
                self.files_index += 1;
            }
            return token;
        }

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.sbl;
        }

        pub fn reference(self: *Self) praxis.Reference {
            return self.parser.reference;
        }

        pub fn punctuation(self: *Self) ?[]const u8 {
            return self.parser.punctuation();
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

const SblParser = struct {
    /// This is a pointer to the data buffer that is advanced as we read.
    data: []const u8,

    /// A pointer to the original buffer.
    original: []const u8,

    /// The text value of each recognised token
    value: []const u8,

    /// If a token is a `word`, then this variable contains
    /// the word minus any punctuation.
    word: []const u8,

    /// Internal state tracking of variant markers.
    column: u8,

    /// Track which verse we are reading
    verse_tag: []const u8,
    reference: Reference = undefined,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []const u8) SblParser {
        return .{
            .data = data,
            .original = data,
            .value = "",
            .word = "",
            .column = 0,
            .verse_tag = "",
            .reference = .{
                .module = .sbl,
                .book = .unknown,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *SblParser) !TextToken {
        if (self.data.len == 0) return .eof;
        self.value = self.data;

        if (false) {
            // Current version does not include paragraphs
            const lines = self.skip_space();
            if (lines > 1) {
                self.value.len = self.data.ptr - self.value.ptr;
                return .paragraph;
            }
        }

        // Send the verse column/tag first.
        //
        //   010101 N- ----NSF- Βίβλος Βίβλος βίβλος βίβλος
        if (self.column == 0) {
            if (self.data.len < 6) {
                return error.unexpected_character;
            }
            self.value = self.data[0..6];
            self.word = self.value;
            self.column = 19;
            if (!std.mem.eql(u8, self.value, self.verse_tag)) {
                const book_no: u16 = (self.data[0] - '0') * 10 + (self.data[1] - '0');
                self.reference.book = try praxis.Book.from_u16(book_no + 39);
                self.reference.chapter = (self.data[2] - '0') * 10 + (self.data[3] - '0');
                self.reference.verse = (self.data[4] - '0') * 10 + (self.data[5] - '0');
                self.verse_tag = self.value;
                return .verse;
            }
        }

        // Send the word token second.
        if (self.column == 19) {
            if (self.data.len >= 20) {

                // Read a word into the `word` value,
                // not including any punctuation.
                self.word = self.data[19..];
                var j: usize = 0;
                while (j < self.word.len and
                    !is_eol(self.word[j]) and
                    !is_ascii_whitespace(self.word[j]) and
                    !is_sbl_punctuation(self.word[j]))
                    j += 1;
                self.word.len = j;

                // Extend the value to contain the word and any punctuation.
                self.value = self.data[19..];
                var i: usize = j;
                while (i < self.value.len and is_sbl_punctuation(self.value[i]))
                    i += 1;
                self.value.len = i;

                self.column = 7;
                return .word;
            }
            return error.unexpected_character;
        }

        // Send the parsing column third
        if (self.column == 7) {
            if (self.data.len >= 18) {
                self.value = self.data[7..18];
                self.word = self.value;
                // Advance to next line before returning.
                self.column = 0;
                while (self.data.len > 0 and !is_eol(self.data[0])) {
                    self.advance();
                }
                if (self.data.len > 0 and is_eol(self.data[0]))
                    self.advance();
                return .parsing;
            }
            return error.unexpected_character;
        }

        // Reaching this point indicates a bug in the above algorithm.
        unreachable;
    }

    /// Pass over whitespace and comments. Return the number of lines skipped.
    /// two consecutive line endings might be considered a paragraph in some
    /// data files.
    fn skip_space(self: *SblParser) usize {
        var cr: usize = 0;
        var lf: usize = 0;
        while (self.data.len > 0) {
            if (is_ascii_whitespace(self.data[0])) {
                if (self.data[0] == '\n') cr += 1;
                if (self.data[0] == '\r') lf += 1;
                self.advance();
                continue;
            }
            if (self.data[0] == '#') {
                while (self.data.len > 0 and !is_eol(self.data[0])) {
                    self.advance();
                }
                if (self.data[0] == '\n' and (self.data.len > 1 and self.data[1] == '\r')) {
                    self.advance();
                    self.advance();
                } else if (self.data[0] == '\r' and (self.data.len > 1 and self.data[1] == '\n')) {
                    self.advance();
                    self.advance();
                } else if (self.data.len > 0 and is_eol(self.data[0])) {
                    self.advance();
                }
                continue;
            }
            break;
        }
        return @max(cr, lf);
    }

    inline fn advance(self: *SblParser) void {
        self.data.len -= 1;
        self.data.ptr += 1;
    }

    pub fn punctuation(self: *SblParser) ?[]const u8 {
        const trailing = self.value.len - self.word.len;
        if (trailing == 0) return null;
        return self.value[(self.value.len - trailing)..];
    }

    pub fn debug_slice(self: *SblParser) []const u8 {
        if (self.data.len == 0) return "";
        const show = @min(20, self.data.len);
        return self.data[0..show];
    }
};

fn is_ascii_whitespace(c: u8) bool {
    return (c <= 32);
}

fn is_eol(c: u8) bool {
    return c == '\n' or c == '\r';
}

// Conservatively only accept punctuation we have seen in data sources.
fn is_sbl_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-';
}

fn sbl_book_name(name: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase("64-Jn-morphgnt.txt", name)) {
        return "64-Jh-morphgnt.txt";
    }
    return name;
}

test "basic" {
    var p = SblParser.init(&"010101 N- ----NSF- Βίβλος Βίβλος βίβλος βίβλος".*);
    try ee(.verse, p.next());
    try ee(.word, p.next());
    try ee(.parsing, p.next());
    try ee(.eof, p.next());

    p = SblParser.init(&
        \\010101 N- ----NSF- Βίβλος Βίβλος βίβλος βίβλος
        \\010101 N- ----GSF- γενέσεως γενέσεως γενέσεως γένεσις
        \\010101 N- ----GSM- Ἰησοῦ, Ἰησοῦ Ἰησοῦ Ἰησοῦς
        \\122334 N- ----NSF- Βίβλος Βίβλος βίβλος βίβλος
    .*);
    try ee(.verse, p.next());
    try es("010101", p.value);
    try ee(praxis.Book.matthew, p.reference.book);
    try ee(1, p.reference.chapter);
    try ee(1, p.reference.verse);
    try ee(.word, p.next());
    try es("Βίβλος", p.word);
    try es("Βίβλος", p.value);
    try ee(.parsing, p.next());
    try ee(.word, p.next());
    try es("γενέσεως", p.word);
    try es("γενέσεως", p.value);
    try ee(.parsing, p.next());
    try ee(.word, p.next());
    try es("Ἰησοῦ,", p.value);
    try es("Ἰησοῦ", p.word);
    try ee(.parsing, p.next());
    try ee(.verse, p.next());
    try es("122334", p.value);
    try ee(praxis.Book.colossians, p.reference.book);
    try ee(23, p.reference.chapter);
    try ee(34, p.reference.verse);
    try ee(.word, p.next());
    try ee(.parsing, p.next());
    try ee(.eof, p.next());
}

test "test_parse_sbl_files" {
    if (false) {
        const allocator = std.testing.allocator;
        var token_count: usize = 0;

        var p = try reader().init(allocator);
        defer p.deinit(allocator);

        while (true) {
            const token = p.next(allocator) catch |e| {
                std.log.err("Failed parsing {s}. Error {any}", .{
                    @tagName(p.module()),
                    e,
                });
                try std.testing.expect(false);
                break;
            };
            token_count += 1;
            if (.eof == token) {
                break;
            }
            if (.unexpected_character == token) {
                try std.testing.expect(false);
                break;
            }
        }
        try std.testing.expectEqual(485770, token_count);
    }
}

const std = @import("std");
const BoundedArray = std.BoundedArray;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const warn = std.log.warn;
const Allocator = std.mem.Allocator;

const praxis = @import("praxis");
const Parsing = praxis.Parsing;
const Reference = praxis.Reference;
const BetacodeType = praxis.BetacodeType;
const parse_tag = praxis.parse;
const betacode_to_greek = praxis.betacode_to_greek;

const modules = @import("modules.zig");
const load_file_bytes = modules.load_file_bytes;
const TextToken = modules.TextToken;
const Module = modules.Module;
const Paragraph = modules.Paragraph;
const Verse = modules.Verse;
const Word = modules.Word;
const extract_book_from_filename = modules.extract_book_from_filename;

const ee = std.testing.expectEqual;
const es = std.testing.expectEqualStrings;
