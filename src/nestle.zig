//! Read the nestle data file.
//!
//!  BCV        text     func_morph  form_morph  strongs lemma   normalized
//!  Matt 1:1   Βίβλος   N-NSF   N-NSF   976     βίβλος  Βίβλος
//!  Matt 1:1   γενέσεως N-GSF   N-GSF   1078    γένεσις γενέσεως
//!  Matt 1:1   Ἰησοῦ    N-GSM   N-GSM   2424    Ἰησοῦς  Ἰησοῦ

const filename = "Nestle1904.csv";
const folder = "resources/nestle1904";

pub fn reader() type {
    return struct {
        const Self = @This();
        data: []u8 = "",
        parser: NestleParser,
        verbose: bool = false,

        pub fn init(allocator: Allocator, verbose: bool) !Self {
            const dir = try std.fs.cwd().openDir(folder, .{});
            const data = try load_file_bytes(allocator, dir, filename);
            return .{
                .data = data,
                .parser = NestleParser.init(modules.remove_bom(data)),
                .verbose = verbose,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
        }

        pub fn next(self: *Self, _: Allocator) !Token {
            return self.parser.next();
        }

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.nestle;
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

const NestleParser = struct {
    /// This is a pointer to the data buffer that is advanced as we read.
    data: []u8 = "",

    /// A pointer to the original buffer.
    original: []const u8 = "",

    // The Nestle data is 6 columns per line.
    column: Column = .verse,

    current_verse: Reference = .unknown,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []u8) NestleParser {
        return .{
            .data = data[0..data.len],
            .original = data,
            .column = .verse,
            .current_verse = .{
                .module = .nestle,
                .book = .unknown,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *NestleParser) !Token {
        _ = self.skip_space();
        if (self.data.len == 0) return .eof;
        var value = self.read_field();

        // If first column is "BCV" this is a header row, skip it.
        if (self.column == .verse and std.mem.eql(u8, "BCV", value)) {
            _ = self.read_field();
            _ = self.read_field();
            _ = self.read_field();
            _ = self.read_field();
            _ = self.read_field();
            _ = self.read_field();
            value = self.read_field();
        }

        // Depending on the column, a different token type is returned.
        switch (self.column) {
            .verse => {
                self.column = .text;
                var reference = praxis.parse_reference(value) catch |f| {
                    std.log.err("Failed parsing {s}. {any}", .{ value, f });
                    return .{ .invalid_token = value };
                };
                if (self.current_verse.verse != reference.verse or self.current_verse.chapter != reference.chapter) {
                    reference.module = .nestle;
                    self.current_verse = reference;
                    return .{ .verse = reference };
                }
                return self.next();
            },
            .text => {
                self.column = .func_parsing;
                return .{ .word = .{
                    .text = value,
                    .word = remove_punctuation(value),
                } };
            },
            .normalised => unreachable,
            .lemma => unreachable,
            .func_parsing => {
                self.column = .strongs; // skip form parsing column
                value = self.read_field();
                const parsing = parse_tag(value) catch |f| {
                    std.log.err("Faild parsing {s}. {any}", .{ value, f });
                    return .{ .invalid_token = value };
                };
                return .{ .parsing = parsing };
            },
            .form_parsing => unreachable,
            .strongs => {
                self.column = .verse;
                // Skip last two columns
                _ = self.read_field();
                _ = self.read_field();
                return self.read_strongs_field(value);
            },
        }
    }

    fn read_field(self: *NestleParser) []const u8 {
        _ = self.skip_space();
        var word: []const u8 = "";
        var value: []u8 = self.data;
        value.len = 0;
        var end: usize = 0;
        while (self.data.len > 0) {
            if (self.data[0] == '\t' or self.data[0] == '\n' or self.data[0] == '\r' or self.data[0] == 0)
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

    fn read_strongs_field(self: *NestleParser, text: []const u8) Token {
        var field: []u8 = @constCast(text);
        _ = self.skip_space();
        var sn: [2]u16 = .{ 0, 0 };

        if (is_ascii_number(field[0])) {
            sn[0] = field[0] - '0';
            field = field[1..];
            while (field.len > 0 and is_ascii_number(field[0])) {
                sn[0] *= 10;
                sn[0] += field[0] - '0';
                field = field[1..];
            }
            if (field.len > 0 and field[0] == '&') {
                field = field[1..];
                while (field.len > 0 and is_ascii_number(field[0])) {
                    sn[1] *= 10;
                    sn[1] += field[0] - '0';
                    field = field[1..];
                }
            }
        }
        _ = self.skip_space();
        if (field.len > 0) {
            return .{ .invalid_token = field };
        }

        return .{ .strongs = sn };
    }

    /// Pass over whitespace and comments. Return the number of lines skipped.
    /// two consecutive line endings might be considered a paragraph in some
    /// data files.
    fn skip_space(self: *NestleParser) usize {
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

    fn advance(self: *NestleParser) void {
        self.data.len -= 1;
        self.data.ptr += 1;
    }

    pub fn debug_slice(self: *NestleParser) []const u8 {
        if (self.data.len == 0) return "";
        const show = @min(20, self.data.len);
        return self.data[0..show];
    }
};

inline fn remove_punctuation(text: []const u8) []const u8 {
    var word = text;
    while (word.len > 0 and is_punctuation(word[word.len - 1])) {
        word.len -= 1;
    }
    return word;
}

fn is_ascii_whitespace(c: u8) bool {
    return (c <= 32);
}

fn is_ascii_number(c: u8) bool {
    return (c >= '0' and c <= '9');
}

fn is_eol(c: u8) bool {
    return c == '\n' or c == '\r';
}

// Conservatively only accept punctuation we have seen in data sources.
fn is_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-';
}

const Column = enum {
    verse,
    text,
    func_parsing,
    form_parsing,
    strongs,
    lemma,
    normalised,
};

test "basic" {
    {
        var data = "Matt 1:1\tΒίβλος\tN-NSF\tN-NSF\t976&39\tβίβλος\tΒίβλος".*;
        var p = NestleParser.init(&data);
        var v = try ev(.verse, try p.next());
        try ee(.matthew, v.verse.book);
        try ee(1, v.verse.chapter);
        try ee(1, v.verse.verse);
        v = try ev(.word, try p.next());
        try expectEqualStrings("Βίβλος", v.word.word);
        v = try ev(.parsing, try p.next());
        try ee(try parse_tag("N-NSF"), v.parsing);
        v = try ev(.strongs, try p.next());
        try ee(976, v.strongs[0]);
        try ee(39, v.strongs[1]);
        _ = try ev(.eof, try p.next());
    }

    {
        var data = "  Matt 1:1  \t   Βίβλος  \tN-NSF\tN-NSF\t976\tβίβλος\tΒίβλος".*;
        var p = NestleParser.init(&data);
        var v = try ev(.verse, try p.next());
        try ee(.matthew, v.verse.book);
        try ee(1, v.verse.chapter);
        try ee(1, v.verse.verse);
        v = try ev(.word, try p.next());
        try expectEqualStrings("Βίβλος", v.word.word);
        v = try ev(.parsing, try p.next());
        try ee(try parse_tag("N-NSF"), v.parsing);
        v = try ev(.strongs, try p.next());
        try ee(976, v.strongs[0]);
        _ = try ev(.eof, try p.next());
    }

    {
        var data = "Mark 12:25\tἀλλ’\tCONJ\tCONJ\t235\tἀλλά\tἀλλ’".*;
        var p = NestleParser.init(&data);
        var v = try ev(.verse, try p.next());
        try ee(.mark, v.verse.book);
        try ee(12, v.verse.chapter);
        try ee(25, v.verse.verse);
        v = try ev(.word, try p.next());
        try expectEqualStrings("ἀλλ᾽", v.word.word);
        v = try ev(.parsing, try p.next());
        try ee(try parse_tag("CONJ"), v.parsing);
        v = try ev(.strongs, try p.next());
        try expectEqual(235, v.strongs[0]);
        _ = try ev(.eof, try p.next());
    }

    {
        var data =
            "BCV\ttext\tfunc_morph\tform_morph\tstrongs\tlemma\tnormalized\n".* ++
            "Matt 1:1\tΒίβλος\tN-NSF\tN-NSF\t976\tβίβλος\tΒίβλος\n".* ++
            "Matt 1:1\tγενέσεως\tN-GSF\tN-GSF\t1078\tγένεσις\tγενέσεως\n".* ++
            "Matt 1:1\tἸησοῦ\tN-GSM\tN-GSM\t2424\tἸησοῦς\tἸησοῦ\n".* ++
            "Matt 1:1\tΧριστοῦ\tN-GSM\tN-GSM\t5547\tΧριστός\tΧριστοῦ\n".* ++
            "Matt 1:1\tυἱοῦ\tN-GSM\tN-GSM\t5207\tυἱός\tυἱοῦ\n".* ++
            "Matt 1:1\tΔαυεὶδ\tN-PRI\tN-PRI\t1138\tΔαυίδ\tΔαυείδ\n".* ++
            "Matt 1:1\tυἱοῦ\tN-GSM\tN-GSM\t5207\tυἱός\tυἱοῦ\n".* ++
            "Rev 9:2\tἈβραάμ.\tN-PRI\tN-PRI\t11\tἈβραάμ\tἈβραάμ\n".*;
        var p = NestleParser.init(&data);
        var v = try ev(.verse, try p.next());
        try ee(.matthew, v.verse.book);
        try ee(1, v.verse.chapter);
        try ee(1, v.verse.verse);
        v = try ev(.word, try p.next());
        try expectEqualStrings("Βίβλος", v.word.word);
        v = try ev(.parsing, try p.next());
        try ee(try parse_tag("N-NSF"), v.parsing);
        v = try ev(.strongs, try p.next());
        try expectEqual(976, v.strongs[0]);
        v = try ev(.word, try p.next());
        try expectEqualStrings("γενέσεως", v.word.word);
        _ = try ev(.parsing, try p.next());
        _ = try ev(.strongs, try p.next());
        v = try ev(.word, try p.next());
        try expectEqualStrings("Ἰησοῦ", v.word.word);
        _ = try ev(.parsing, try p.next());
        _ = try ev(.strongs, try p.next());
        v = try ev(.word, try p.next());
        try expectEqualStrings("Χριστοῦ", v.word.word);
        _ = try ev(.parsing, try p.next());
        _ = try ev(.strongs, try p.next());
        v = try ev(.word, try p.next());
        try expectEqualStrings("υἱοῦ", v.word.word);
        _ = try ev(.parsing, try p.next());
        _ = try ev(.strongs, try p.next());
        v = try ev(.word, try p.next());
        try expectEqualStrings("Δαυεὶδ", v.word.word);
        _ = try ev(.parsing, try p.next());
        _ = try ev(.strongs, try p.next());
        v = try ev(.word, try p.next());
        try expectEqualStrings("υἱοῦ", v.word.word);
        _ = try ev(.parsing, try p.next());
        _ = try ev(.strongs, try p.next());
        v = try ev(.verse, try p.next());
        try expectEqual(.revelation, v.verse.book);
        try expectEqual(9, v.verse.chapter);
        try expectEqual(2, v.verse.verse);
        v = try ev(.word, try p.next());
        try expectEqualStrings("Ἀβραάμ.", v.word.text);
        try expectEqualStrings("Ἀβραάμ", v.word.word);
    }
}

test "test_parse_nestle_files" {
    const allocator = std.testing.allocator;
    var token_count: usize = 0;

    var p = try reader().init(allocator, true);
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
        if (.invalid_token == token) {
            try std.testing.expect(false);
            break;
        }
    }
    try std.testing.expectEqual(421281, token_count);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const praxis = @import("praxis");
const Reference = praxis.Reference;
const parse_tag = praxis.parse;

const modules = @import("modules.zig");
const Token = modules.Token;
const load_file_bytes = modules.load_file_bytes;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const ee = std.testing.expectEqual;
const ev = @import("test.zig").ev;
