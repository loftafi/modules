pub const folder = "resources/kjtr";
pub const file = "KJTR.tsv";

pub fn reader() type {
    return struct {
        const Self = @This();
        data: []u8,
        parser: KjtrParser,
        files_index: usize,

        pub fn init(allocator: Allocator) !Self {
            const dir = try std.fs.cwd().openDir(folder, .{});
            const data = try load_file_bytes(allocator, dir, file);
            var parser = KjtrParser.init(data);
            parser.current_verse.module = .kjtr;
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

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.sbl;
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

const KjtrParser = struct {
    /// A pointer to the original buffer.
    original: []const u8,

    /// This is a pointer to the data buffer that is advanced as we read.
    data: []const u8,

    /// Internal state tracking of variant markers.
    column: u8,

    /// Track which verse we are reading
    current_verse: Reference = undefined,

    carryover: ?Token = null,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []const u8) KjtrParser {
        return .{
            .data = data,
            .original = data,
            .column = 0,
            .current_verse = .{
                .module = .sbl,
                .book = .unknown,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *KjtrParser) !Token {
        if (self.carryover != null) {
            const t = self.carryover.?;
            self.carryover = null;
            return t;
        }

        if (self.data.len == 0) return .{ .eof = {} };

        if (false) {
            // Current version does not include paragraphs
            const lines = self.skip_space();
            if (lines > 1) {
                return .{ .paragraph = {} };
            }
        }

        // Send the verse column/tag first.
        //
        //   40001001   ¶Βίβλος βιβλοσ  βίβλος  9760  N  ....NFS
        var value = self.read_field();
        if (self.column == 0) {
            if (value.len != 8) {
                return .{ .invalid_token = value };
            }
            if (!is_ascii_digit(value[0]) or !is_ascii_digit(value[1]) or
                !is_ascii_digit(value[2]) or !is_ascii_digit(value[3]) or
                !is_ascii_digit(value[4]) or !is_ascii_digit(value[5]) or
                !is_ascii_digit(value[6]) or !is_ascii_digit(value[7]))
            {
                return .{ .invalid_token = value };
            }
            const book_no: u16 = (self.data[0] - '0') * 10 + (self.data[1] - '0');
            const ref: Reference = .{
                .module = self.current_verse.module,
                .book = try praxis.Book.from_u16(book_no + 39),
                .chapter = (self.data[2] - '0') * 100 + (self.data[3]) * 10 + (self.data[4] - '0'),
                .verse = (self.data[5] - '0') * 100 + (self.data[6] - '0') * 10 + (self.data[7] - '0'),
            };
            self.column += 1;
            if (!ref.eql(&self.current_verse)) {
                // If this is a new verse, send it.
                self.current_verse = ref;
                return .{ .verse = ref };
            }
        }

        if (self.column == 1) {
            self.column += 1;
            if (std.mem.startsWith(u8, value, "¶")) {
                const m = "¶".len;
                value = value[m..];
                self.carryover = .{ .word = .{
                    .text = value,
                    .word = value,
                } };
                return .{ .paragraph = {} };
            }
            return .{ .word = .{
                .text = value,
                .word = value,
            } };
        }

        if (self.column == 2) {
            value = self.read_field();
            self.column += 1;
        }
        if (self.column == 3) {
            value = self.read_field();
            self.column += 1;
        }

        if (self.column == 4) {
            self.column += 1;
            return .{ .strongs = [2]u16{ 0, 0 } };
        }

        self.column = 0;

        // Merge crrent and next field
        const value2 = self.read_field();
        value.len = value2.ptr + value2.len - value.ptr;

        const parsing = parse_tag(value) catch |f| {
            std.log.err("Invalid parsing string {s}. Error {s}", .{ value, f });
            return .{ .invalid_token = value };
        };
        return .{ .parsing = parsing };
    }

    /// Pass over whitespace and comments. Return the number of lines skipped.
    /// two consecutive line endings might be considered a paragraph in some
    /// data files.
    fn skip_space(self: *KjtrParser) usize {
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

    inline fn advance(self: *KjtrParser) void {
        self.data.len -= 1;
        self.data.ptr += 1;
    }

    fn read_field(self: *KjtrParser) []const u8 {
        _ = self.skip_space();
        var word: []const u8 = "";
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
            self.advance();
        }
        value.len = end;
        if (std.mem.endsWith(u8, value, "’")) {
            const a = "᾽";
            value[value.len - 3] = a[0];
            value[value.len - 2] = a[1];
            value[value.len - 1] = a[2];
        }
        word = value;
        if (self.data.len > 0) {
            if (self.data[0] == '\t') {
                self.advance();
            } else if (self.data[0] == '\n') {
                self.advance();
            } else if (self.data[0] == '\r') {
                self.advance();
            }
        }
        return value;
    }

    pub fn debug_slice(self: *KjtrParser) []const u8 {
        if (self.data.len == 0) return "";
        const show = @min(20, self.data.len);
        return self.data[0..show];
    }
};

// Return a version of a string without trailing punctuation.
pub fn punctuation(text: []const u8) []const u8 {
    var word = text;
    while (word.len > 1 and is_kjtr_punctuation(word[word.len - 1])) {
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
fn is_kjtr_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-';
}

test "basic" {
    var p = KjtrParser.init(&"010101 N- ----NSF- Βίβλος Βίβλος βίβλος βίβλος".*);
    var v = try ev(.verse, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.parsing, try p.next());
    _ = try ev(.eof, try p.next());

    p = KjtrParser.init(&
        \\40001001\t¶Βίβλος\tβιβλοσ\tβίβλος\t9760\tN\t....NFS
        \\40001001\tγενέσεως\tγενεσεωσ\tγένεσις\t10780\tN\t....GFS
        \\40001001\tἸησοῦ\t=ιυ\tἸησοῦς\t24240\tN\t....GMS
        \\51023034\tΧριστοῦ,\t=χυ\tχριστός\t55470\tN\t....GMS
    .*);
    v = try ev(.verse, try p.next());
    try ee(praxis.Book.matthew, v.book);
    try ee(1, p.chapter);
    try ee(1, p.verse);
    _ = try ee(.paragraph, try p.next());
    v = try ee(.word, try p.next());
    try es("Βίβλος", p.word);
    try es("Βίβλος", p.value);
    _ = try ee(.parsing, try p.next());
    _ = try ee(.word, try p.next());
    try es("γενέσεως", p.word);
    try es("γενέσεως", p.value);
    _ = try ee(.parsing, try p.next());
    v = try ee(.word, try p.next());
    try es("Ἰησοῦ,", p.value);
    try es("Ἰησοῦ", p.word);
    _ = try ee(.parsing, try p.next());
    v = try ee(.word, try p.next());
    try es("Χριστοῦ,", p.value);
    try es("Χριστοῦ", p.word);
    _ = try ee(.parsing, try p.next());
    v = try ee(.verse, try p.next());
    try ee(praxis.Book.colossians, p.book);
    try ee(23, p.chapter);
    try ee(34, p.verse);
    _ = try ee(.word, try p.next());
    _ = try ee(.parsing, try p.next());
    _ = try ee(.eof, try p.next());
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
const Allocator = std.mem.Allocator;

const praxis = @import("praxis");
const Parsing = praxis.Parsing;
const Reference = praxis.Reference;
const BetacodeType = praxis.BetacodeType;
const parse_tag = praxis.parse;
const betacode_to_greek = praxis.betacode_to_greek;

const modules = @import("modules.zig");
const load_file_bytes = modules.load_file_bytes;
const Module = modules.Module;
const Paragraph = modules.Paragraph;
const Verse = modules.Verse;
const Word = modules.Word;
const Token = modules.Token;
const extract_book_from_filename = modules.extract_book_from_filename;

const ee = std.testing.expectEqual;
const es = std.testing.expectEqualStrings;
const ev = @import("byzantine.zig").ev;
