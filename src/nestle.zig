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

        pub fn next(self: *Self, _: Allocator) !TextToken {
            return self.parser.next();
        }

        pub fn value(self: *Self) []const u8 {
            return self.parser.value;
        }

        pub fn greek(self: *Self) []const u8 {
            return self.parser.word;
        }

        pub fn punctuation(self: *Self) ?[]const u8 {
            const trailing = self.parser.value.len - self.parser.value.len;
            if (trailing == 0) return null;
            return self.parser.value[trailing..];
        }

        pub fn word(self: *Self) []const u8 {
            return self.parser.word;
        }

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.nestle;
        }

        pub fn reference(self: *Self) praxis.Reference {
            return self.parser.reference;
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

const NestleParser = struct {
    /// This is a pointer to the data buffer that is advanced as we read.
    data: []u8,

    /// A pointer to the original buffer.
    original: []const u8,

    /// The text value of each recognised token
    value: []u8,

    /// If a token is a `word`, then this variable contains
    /// the word minus any punctuation.
    word: []const u8,

    // The Nestle data is 6 columns per line.
    column: usize,

    reference: Reference = undefined,
    verse_tag: []const u8 = "",

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []u8) NestleParser {
        return .{
            .data = data[0..data.len],
            .original = data,
            .value = "",
            .word = "",
            .column = 0,
            .reference = .{
                .module = .nestle,
                .book = .unknown,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *NestleParser) !TextToken {
        _ = self.skip_space();
        if (self.data.len == 0) return .eof;
        self.read_field();

        // If first column is "BCV" this is a header row, skip it.
        if (self.column == 0 and std.mem.eql(u8, "BCV", self.value)) {
            self.read_field();
            self.read_field();
            self.read_field();
            self.read_field();
            self.read_field();
            self.read_field();
            self.read_field();
        }

        // Depending on the column, a different token type is returned.
        self.column += 1;
        switch (self.column) {
            1 => {
                if (!std.mem.eql(u8, self.verse_tag, self.value)) {
                    self.verse_tag = self.value;
                    self.reference = praxis.parse_reference(self.value) catch |f| {
                        std.log.err("Failed parsing {s}. Character {d}. {any}", .{
                            self.value,
                            self.original.len - self.data.len,
                            f,
                        });
                        return f;
                    };
                    self.reference.module = .nestle;
                    return .verse;
                }
                return self.next();
            },
            2 => return .word,
            3 => {
                self.read_field();
                self.column += 1;
                _ = parse_tag(self.value) catch |f| {
                    std.log.err("Faild parsing {s}. {any}", .{ self.value, f });
                    return f;
                };
                return .parsing;
            },
            4 => unreachable,
            5 => {
                const w = self.word;
                const v = self.value;
                self.read_field();
                self.read_field();
                self.word = w;
                self.value = v;
                self.column = 0;
                return .strongs;
            },
            else => unreachable,
        }
    }

    fn read_field(self: *NestleParser) void {
        _ = self.skip_space();
        self.value = self.data;
        self.value.len = 0;
        self.word = "";
        var end: usize = 0;
        while (self.data.len > 0) {
            if (self.data[0] == '\t' or self.data[0] == '\n' or self.data[0] == '\r' or self.data[0] == 0)
                break;
            if (is_punctuation(self.data[0]) and self.word.len == 0) {
                self.word = self.value;
            }
            if (self.data[0] != ' ') {
                end = self.value.len + 1;
            }
            self.value.len += 1;
            self.advance();
        }
        self.value.len = end;
        if (self.data.len > 0) {
            if (self.data[0] == '\t') {
                self.advance();
            } else if (self.data[0] == '\n') {
                self.advance();
            } else if (self.data[0] == '\r') {
                self.advance();
            }
        }
        if (std.mem.endsWith(u8, self.value, "’")) {
            self.value[self.value.len - 3] = "᾽"[0];
            self.value[self.value.len - 2] = "᾽"[1];
            self.value[self.value.len - 1] = "᾽"[2];
        }
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

fn is_ascii_whitespace(c: u8) bool {
    return (c <= 32);
}

fn is_eol(c: u8) bool {
    return c == '\n' or c == '\r';
}

// Conservatively only accept punctuation we have seen in data sources.
fn is_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-';
}

test "basic" {
    {
        var data = "Matt 1:1\tΒίβλος\tN-NSF\tN-NSF\t976\tβίβλος\tΒίβλος".*;
        var p = NestleParser.init(&data);
        try expectEqual(.verse, try p.next());
        try expectEqualStrings("Matt 1:1", p.value);
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Βίβλος", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqualStrings("N-NSF", p.value);
        try expectEqual(.strongs, try p.next());
        try expectEqualStrings("976", p.value);
        try expectEqual(.eof, try p.next());
    }

    {
        var data = "  Matt 1:1  \t   Βίβλος  \tN-NSF\tN-NSF\t976\tβίβλος\tΒίβλος".*;
        var p = NestleParser.init(&data);
        try expectEqual(.verse, try p.next());
        try expectEqualStrings("Matt 1:1", p.value);
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Βίβλος", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqualStrings("N-NSF", p.value);
        try expectEqual(.strongs, try p.next());
        try expectEqualStrings("976", p.value);
        try expectEqual(.eof, try p.next());
    }

    {
        //data = "Mark 12:25\tἀλλ’\tCONJ\tCONJ\t235\tἀλλά\tἀλλ’";
        var data = "Mark 12:25\tἀλλ’\tCONJ\tCONJ\t235\tἀλλά\tἀλλ’".*;
        var p = NestleParser.init(&data);
        try expectEqual(.verse, try p.next());
        try expectEqualStrings("Mark 12:25", p.value);
        try expectEqual(.word, try p.next());
        try expectEqualStrings("ἀλλ᾽", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqualStrings("CONJ", p.value);
        try expectEqual(.strongs, try p.next());
        try expectEqualStrings("235", p.value);
        try expectEqual(.eof, try p.next());
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
        try expectEqual(.verse, try p.next());
        try expectEqualStrings("Matt 1:1", p.value);
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Βίβλος", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqualStrings("N-NSF", p.value);
        try expectEqual(.strongs, try p.next());
        try expectEqualStrings("976", p.value);
        try expectEqual(.word, try p.next());
        try expectEqualStrings("γενέσεως", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqual(.strongs, try p.next());
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Ἰησοῦ", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqual(.strongs, try p.next());
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Χριστοῦ", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqual(.strongs, try p.next());
        try expectEqual(.word, try p.next());
        try expectEqualStrings("υἱοῦ", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqual(.strongs, try p.next());
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Δαυεὶδ", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqual(.strongs, try p.next());
        try expectEqual(.word, try p.next());
        try expectEqualStrings("υἱοῦ", p.value);
        try expectEqual(.parsing, try p.next());
        try expectEqual(.strongs, try p.next());
        try expectEqual(.verse, try p.next());
        try expectEqualStrings("Rev 9:2", p.value);
        try expectEqual(.revelation, p.reference.book);
        try expectEqual(9, p.reference.chapter);
        try expectEqual(2, p.reference.verse);
        try expectEqual(.word, try p.next());
        try expectEqualStrings("Ἀβραάμ.", p.value);
        try expectEqualStrings("Ἀβραάμ", p.word);
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
        if (.unexpected_character == token) {
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
const TextToken = modules.TextToken;
const load_file_bytes = modules.load_file_bytes;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
