//! Support reading the cntr files that use the following format.
//!
//! KJTR:
//! Verse      Modern    Koine      Lemma   ESN     Role  Morphology
//! 40001001   ¶Βίβλος   βιβλοσ     βίβλος  9760    N     ....NFS
//! 40001001   γενέσεως  γενεσεωσ   γένεσις 10780   N     ....GFS
//! 40001001   Ἰησοῦ     =ιυ        Ἰησοῦς  24240   N     ....GMS
//! 40001001   Χριστοῦ,  =χυ        χριστός 55470   N     ....GMS
//! 40001002   ἐγέννησεν εγεννησεν  γεννάω  10800   V       IAA3..S
//!
//! SR:
//! Verse      Text      Koine    Lemma   ESN     Role    Morphology
//! 40001001   ¶Βίβλος   βιβλοσ   βίβλος  09760   N       ....NFS
//! 40001001   γενέσεως  γενεσεωσ γένεσις 10780   N       ....GFS
//! 40001001   ˚Ἰησοῦ    =ιυ      Ἰησοῦς  24240   N       ....GMS
//! 40001001   ˚Χριστοῦ, =χυ      χριστός 55470   N       ....GMS

pub const folder = "resources/kjtr";
pub const file = "KJTR.tsv";

const parsing_field_length: usize = 8;

pub fn reader() type {
    return struct {
        const Self = @This();
        data: []u8,
        parser: CntrParser,
        files_index: usize,

        pub fn init(
            allocator: Allocator,
            module_tag: praxis.Module,
        ) !Self {
            const dir = try std.fs.cwd().openDir(folder, .{});
            const data = try load_file_bytes(allocator, dir, file);
            var parser = CntrParser.init(data, module_tag);
            parser.current_verse.module = module_tag;
            return .{
                .data = data,
                .parser = parser,
                .files_index = 0,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
        }

        pub fn next(self: *Self, _: Allocator) !Token {
            const token = try self.parser.next();
            return token;
        }

        pub fn module(self: *Self) praxis.Module {
            return self.parser.current_verse.module;
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

const CntrParser = struct {
    /// A pointer to the original buffer.
    original: []const u8,

    /// This is a pointer to the data buffer that is advanced as we read.
    data: []const u8,

    /// Internal state tracking of variant markers.
    column: Column,

    /// Track which verse we are reading
    current_verse: Reference = undefined,

    carryover: ?Token = null,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []const u8, module_tag: praxis.Module) CntrParser {
        return .{
            .data = data,
            .original = data,
            .column = .verse,
            .current_verse = .{
                .module = module_tag,
                .book = .unknown,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *CntrParser) !Token {
        if (self.carryover != null) {
            const t = self.carryover.?;
            self.carryover = null;
            return t;
        }

        if (self.column == .verse) {
            // Skip lines that don't start with numbers
            if (self.data.len > 0 and !is_ascii_digit(self.data[0])) {
                self.skip_comment_line();
            }
        }

        if (self.data.len == 0) return .{ .eof = {} };

        // Send the verse column/tag first.
        //
        //   40001001   ¶Βίβλος βιβλοσ  βίβλος  9760  N  ....NFS
        var value = self.read_field();
        if (self.column == .verse) {
            if (value.len != parsing_field_length) {
                return .{ .invalid_token = value };
            }
            if (!is_ascii_digit(value[0]) or !is_ascii_digit(value[1]) or
                !is_ascii_digit(value[2]) or !is_ascii_digit(value[3]) or
                !is_ascii_digit(value[4]) or !is_ascii_digit(value[5]) or
                !is_ascii_digit(value[6]) or !is_ascii_digit(value[7]))
            {
                return .{ .invalid_token = value };
            }
            const book_no: u16 = (value[0] - '0') * 10 + (value[1] - '0');
            const ref: Reference = .{
                .module = self.current_verse.module,
                .book = try praxis.Book.from_u16(book_no),
                .chapter = (value[2] - '0') * 100 + (value[3] - '0') * 10 + (value[4] - '0'),
                .verse = (value[5] - '0') * 100 + (value[6] - '0') * 10 + (value[7] - '0'),
            };
            self.column = .text;
            if (!ref.eql(&self.current_verse)) {
                // If this is a new verse, send it.
                self.current_verse = ref;
                return .{ .verse = ref };
            }
            value = self.read_field();
        }

        if (self.column == .text) {
            self.column = .normalised;
            if (std.mem.startsWith(u8, value, "¶")) {
                const m = "¶".len;
                value = value[m..];
                self.carryover = .{ .word = .{
                    .text = value,
                    .word = punctuation(value),
                } };
                return .{ .paragraph = {} };
            }
            return .{ .word = .{
                .text = value,
                .word = punctuation(value),
            } };
        }

        if (self.column == .normalised) {
            value = self.read_field();
            self.column = .lexical_form;
        }
        if (self.column == .lexical_form) {
            value = self.read_field();
            self.column = .strongs;
        }

        if (self.column == .strongs) {
            self.column = .parsing;
            var field = value;
            var sn1: u16 = 0;
            while (field.len > 0 and is_ascii_digit(field[0])) {
                sn1 = sn1 * 10 + (field[0] - '0');
                field = field[1..];
            }
            return .{ .strongs = [2]u16{ sn1, 0 } };
        }

        self.column = .verse;

        // Merge current and next field
        const value2 = self.read_field();
        value.len = value2.ptr + value2.len - value.ptr;

        const parsing = parse_tag(value) catch |f| {
            std.log.err("Invalid parsing string {s}. Error {any}", .{ value, f });
            return .{ .invalid_token = value };
        };
        return .{ .parsing = parsing };
    }

    fn skip_comment_line(self: *CntrParser) void {
        while (self.data.len > 0 and !is_eol(self.data[0])) {
            self.data = self.data[1..];
        }
        while (self.data.len > 0 and is_eol(self.data[0])) {
            self.data = self.data[1..];
        }
    }

    /// Pass over whitespace and comments. Return the number of lines skipped.
    /// two consecutive line endings might be considered a paragraph in some
    /// data files.
    fn skip_space(self: *CntrParser) usize {
        var cr: usize = 0;
        var lf: usize = 0;
        while (self.data.len > 0) {
            if (is_ascii_whitespace(self.data[0])) {
                if (self.data[0] == '\n') cr += 1;
                if (self.data[0] == '\r') lf += 1;
                self.data = self.data[1..];
                continue;
            }
            if (self.data[0] == '#') {
                while (self.data.len > 0 and !is_eol(self.data[0])) {
                    self.data = self.data[1..];
                }
                if (self.data[0] == '\n' and (self.data.len > 1 and self.data[1] == '\r')) {
                    self.data = self.data[2..];
                } else if (self.data[0] == '\r' and (self.data.len > 1 and self.data[1] == '\n')) {
                    self.data = self.data[2..];
                } else if (self.data.len > 0 and is_eol(self.data[0])) {
                    self.data = self.data[1..];
                }
                continue;
            }
            break;
        }
        return @max(cr, lf);
    }

    fn read_field(self: *CntrParser) []const u8 {
        _ = self.skip_space();
        var value: []u8 = @constCast(self.data);
        value.len = 0;
        var end: usize = 0;
        while (self.data.len > 0) {
            if (self.data[0] == '\t' or self.data[0] == '\n' or
                self.data[0] == '\r' or self.data[0] == 0)
                break;
            if (self.data[0] != ' ') {
                end = value.len + 1;
            }
            value.len += 1;
            self.data = self.data[1..];
        }
        value.len = end;
        if (std.mem.endsWith(u8, value, "’")) {
            const a = "᾽";
            value[value.len - 3] = a[0];
            value[value.len - 2] = a[1];
            value[value.len - 1] = a[2];
        }
        if (self.data.len > 0) {
            if (self.data[0] == '\t') {
                self.data = self.data[1..];
            } else if (self.data[0] == '\n') {
                self.data = self.data[1..];
            } else if (self.data[0] == '\r') {
                self.data = self.data[1..];
            }
        }
        return value;
    }

    pub fn debug_slice(self: *CntrParser) []const u8 {
        if (self.data.len == 0) return "";
        const show = @min(20, self.data.len);
        return self.data[0..show];
    }
};

const Column = enum(u8) {
    verse = 1,
    text = 2,
    normalised = 3,
    lexical_form = 4,
    strongs = 5,
    parsing = 6,
};

// Return a version of a string without trailing punctuation.
pub fn punctuation(text: []const u8) []const u8 {
    var word = text;
    while (word.len > 1 and is_cntr_punctuation(word[word.len - 1])) {
        word.len -= 1;
    }
    return word;
}

fn is_ascii_whitespace(c: u8) bool {
    return (c <= 32);
}

fn is_ascii_digit(c: u8) bool {
    return (c >= '0' and c <= '9');
}

fn is_eol(c: u8) bool {
    return c == '\n' or c == '\r';
}

// Conservatively only accept punctuation we have seen in data sources.
fn is_cntr_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-' or c == '!';
}

test "cntr_basic" {
    var p = CntrParser.init(&"40001001\t¶Βίβλος\tβιβλοσ\tβίβλος\t9760\tN\t....NFS ".*, .kjtr);
    var v = try ev(.verse, try p.next());
    _ = try ev(.paragraph, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.strongs, try p.next());
    _ = try ev(.parsing, try p.next());
    _ = try ev(.eof, try p.next());

    p = CntrParser.init(&("40001001\t¶Βίβλος\tβιβλοσ\tβίβλος\t9760\tN\t....NFS\n" ++
        "40001001\tγενέσεως\tγενεσεωσ\tγένεσις\t10780\tN\t....GFS\n" ++
        "40001001\tἸησοῦ.\t=ιυ\tἸησοῦς\t24240\tN\t....GMS\n" ++
        "51023034\tΧριστοῦ,\t=χυ\tχριστός\t55470\tN\t....GMS\n").*, .sr);
    v = try ev(.verse, try p.next());
    try ee(praxis.Book.matthew, v.verse.book);
    try ee(1, v.verse.chapter);
    try ee(1, v.verse.verse);
    _ = try ev(.paragraph, try p.next());
    v = try ev(.word, try p.next());
    try es("Βίβλος", v.word.word);
    try es("Βίβλος", v.word.text);
    v = try ev(.strongs, try p.next());
    try ee(9760, v.strongs[0]);
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("γενέσεως", v.word.word);
    try es("γενέσεως", v.word.text);
    v = try ev(.strongs, try p.next());
    try ee(10780, v.strongs[0]);
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("Ἰησοῦ", v.word.word);
    try es("Ἰησοῦ.", v.word.text);
    v = try ev(.strongs, try p.next());
    try ee(24240, v.strongs[0]);
    _ = try ev(.parsing, try p.next());
    v = try ev(.verse, try p.next());
    try ee(praxis.Book.colossians, v.verse.book);
    try ee(23, v.verse.chapter);
    try ee(34, v.verse.verse);
    v = try ev(.word, try p.next());
    try es("Χριστοῦ", v.word.word);
    try es("Χριστοῦ,", v.word.text);
    v = try ev(.strongs, try p.next());
    try ee(55470, v.strongs[0]);
    _ = try ev(.parsing, try p.next());
    _ = try ev(.eof, try p.next());
}

test "special_punctuation" {
    var p = CntrParser.init(&("42019040\tκράξουσιν.”\tκραξουσιν\tκράζω\t28960\tV\tIFA3..P\n" ++
        "42019041\t¶Καὶ\tκαι\tκαί\t25320\tC\t.......").*, .kjtr);
    var v = try ev(.verse, try p.next());
    try ee(19, v.verse.chapter);
    v = try ev(.word, try p.next());
    _ = try ev(.strongs, try p.next());
    _ = try ev(.parsing, try p.next());
    v = try ev(.verse, try p.next());
    try ee(19, v.verse.chapter);
    _ = try ev(.paragraph, try p.next());
    v = try ev(.word, try p.next());
    _ = try ev(.strongs, try p.next());
    _ = try ev(.parsing, try p.next());
    _ = try ev(.eof, try p.next());
}

test "chop_punctuation" {
    try es("hello", punctuation("hello."));
    try es("και", punctuation("και,"));
}

test "test_parse_kjtr_file" {
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
const err = std.log.err;
const Allocator = std.mem.Allocator;

const praxis = @import("praxis");
const Parsing = praxis.Parsing;
const Reference = praxis.Reference;
const BetacodeType = praxis.BetacodeType;
const parse_tag = praxis.parse_cntr;
const betacode_to_greek = praxis.betacode_to_greek;

const modules = @import("modules.zig");
const load_file_bytes = modules.load_file_bytes;
const Paragraph = modules.Paragraph;
const Verse = modules.Verse;
const Word = modules.Word;
const Token = modules.Token;
const extract_book_from_filename = modules.extract_book_from_filename;

const ee = std.testing.expectEqual;
const es = std.testing.expectEqualStrings;
const ev = @import("test.zig").ev;
