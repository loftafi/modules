pub const folder = "resources/byzantine";

pub const files = [_][]const u8{
    "01_MAT", "02_MAR", "03_LUK", "04_JOH", "05_ACT", "06_ROM", "07_1CO",
    "08_2CO", "09_GAL", "10_EPH", "11_PHP", "12_COL", "13_1TH", "14_2TH",
    "15_1TI", "16_2TI", "17_TIT", "18_PHM", "19_HEB", "20_JAM", "21_1PE",
    "22_2PE", "23_1JO", "24_2JO", "25_3JO", "26_JUD", "27_REV",
};

pub fn reader() type {
    return struct {
        const Self = @This();
        parser: ByzParser,
        original: []u8,
        data: []u8,
        parser2: ByzParser,
        data2: []u8,
        files_index: usize = 0,
        carryover_token: Token = .unknown,
        verbose: bool = false,

        pub fn init(allocator: Allocator, verbose: bool) !Self {
            var buf: [50]u8 = undefined;
            const dir = try std.fs.cwd().openDir(folder, .{});

            const book = extract_book_from_filename(files[0]);

            var filename = try bufPrint(&buf, "{s}.BP5", .{files[0]});
            const data = try load_file_bytes(allocator, dir, filename);
            const parser = ByzParser.init(data, book);

            filename = try bufPrint(&buf, "{s}.TXT", .{files[0]});
            const data2 = try load_file_bytes(allocator, dir, filename);
            const parser2 = ByzParser.init(data2, book);

            if (verbose)
                debug("reading book {s}", .{@tagName(book)});

            return .{
                .original = data,
                .data = data,
                .parser = parser,
                .data2 = data2,
                .parser2 = parser2,
                .files_index = 0,
                .carryover_token = .unknown,
                .verbose = verbose,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
            allocator.free(self.data2);
        }

        // Read parser2 tokens for paragraph and accentation,
        // supplimented by parser1 tokens for parsing data.
        pub fn next(self: *Self, allocator: Allocator) !Token {
            var token: Token = .{ .unknown = {} };

            if (self.carryover_token == .unknown) {
                token = try self.parser.next();
            } else {
                token = self.carryover_token;
                self.carryover_token = .unknown;
                if (self.verbose)
                    debug("using the holdback BP5({s} {any})", .{
                        @tagName(token), token,
                    });
            }

            // Are there more files to continue into?
            if (token == .eof) {
                if (self.files_index >= files.len) return token;

                var buf: [50]u8 = undefined;
                const dir = try std.fs.cwd().openDir(folder, .{});

                const book = extract_book_from_filename(files[self.files_index]);
                var filename = try bufPrint(&buf, "{s}.BP5", .{
                    files[self.files_index],
                });
                allocator.free(self.data);
                self.data = try load_file_bytes(allocator, dir, filename);
                self.parser = ByzParser.init(self.data, book);

                filename = try bufPrint(&buf, "{s}.TXT", .{
                    files[self.files_index],
                });
                allocator.free(self.data2);
                self.data2 = try load_file_bytes(allocator, dir, filename);
                self.parser2 = ByzParser.init(self.data2, book);

                debug("reading book {s}", .{@tagName(book)});

                self.files_index += 1;
                token = try self.parser.next();
            }

            // Read our secondary file for paragraph markers and word accentation
            switch (token) {
                .verse => {
                    // Secondary parser should have the same verse marker for us
                    const token2 = try self.parser2.next();
                    if (token2 == .paragraph) {
                        self.carryover_token = token;
                        if (self.verbose)
                            debug("TXT({s}) holdback BP5({s})", .{
                                @tagName(token2),
                                @tagName(token),
                            });
                        return token2;
                    }
                    if (token2 != .verse) {
                        err("Verse marker misalignment. {s} BP5({any}) TXT({any})", .{
                            @tagName(token.verse.book),
                            token.verse,
                            token2,
                        });
                        @panic("Verse misalignment.");
                    }
                    if (self.verbose)
                        debug("BP5({s} {any}) aligns to TXT({any})", .{
                            @tagName(token),
                            token,
                            token2,
                        });
                    return token2;
                },
                .word => {
                    // Secondary parser should have the same word for us, but
                    // it might be a paragraph.
                    const token2 = try self.parser2.next();
                    if (token2 == .paragraph) {
                        if (self.verbose)
                            debug("BP5({s} {s}) holdback. TXT({s})", .{
                                @tagName(token),
                                token.word.word,
                                @tagName(token2),
                            });
                        self.carryover_token = token;
                        return token2;
                    }
                    if (self.verbose)
                        debug("BP5({s} {s}) aligns to TXT({s} {s})", .{
                            @tagName(token),
                            token.word.word,
                            @tagName(token2),
                            token2.word.word,
                        });
                    if (token2 != .word) {
                        @panic("Expected word in TXT file");
                    }
                    return token2;
                },
                .variant_alt, .variant_end, .variant_mark => {
                    // Should not be sent
                    unreachable;
                },
                .eof => {
                    // Already handled above
                    unreachable;
                },
                .strongs, .parsing, .paragraph, .invalid_token, .unknown => return token,
            }

            return token;
        }

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.byzantine;
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

const ByzParser = struct {
    /// This is a pointer to the data buffer that is advanced as we read.
    data: []const u8 = "",

    /// A pointer to the original buffer.
    original: []const u8 = "",

    /// Cache a greek betacode decoding
    greek_buffer: BoundedArray(u8, praxis.MAX_WORD_SIZE),

    /// Internal state tracking of variant markers.
    variant: u8 = 0,

    current_reference: Reference = .unknown,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []const u8, book: praxis.Book) ByzParser {
        return .{
            .data = data,
            .original = data,
            .variant = 0,
            .greek_buffer = .{ .len = 0 },
            .current_reference = .{
                .module = .byzantine,
                .book = book,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *ByzParser) !Token {
        const lines = self.skip_space();
        if (lines > 1) {
            return .{ .paragraph = {} };
        }
        if (self.data.len == 0) return .{ .eof = {} };
        var value = self.data;

        // If we see a digit, it is the start of a strongs number
        // or the start of a verse reference.
        if (is_ascii_digit(self.data[0])) {
            var x: u16 = 0;
            while (self.data.len > 0 and is_ascii_digit(self.data[0])) {
                x = (x * 10) + (self.data[0] - '0');
                self.advance();
            }
            if (self.data.len == 0 or !is_verse_divider(self.data[0])) {
                // It's a strongs number
                value.len = self.data.ptr - value.ptr;
                if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                    return .{ .strongs = [2]u16{ x, 0 } };
                }
                return .{ .invalid_token = value };
            } else {
                // More characters exist and its a verse divider.
                // It's a verse reference.
                var reference = self.current_reference;
                reference.chapter = x;
                x = 0;
                self.advance();
                if (!is_ascii_digit(self.data[0])) {
                    value.len = self.data.ptr - value.ptr;
                    return .{ .invalid_token = value };
                }
                while (self.data.len > 0 and is_ascii_digit(self.data[0])) {
                    x = (x * 10) + (self.data[0] - '0');
                    self.advance();
                }
                reference.verse = x;
                value.len = self.data.ptr - value.ptr;
                if (self.variant != 0) {
                    warn("Verse marker '{s}' encountered in variant.", .{value});
                }
                if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                    return .{ .verse = reference };
                }
                return .{ .invalid_token = value };
            }
        }

        // Is this a word?
        if (is_ascii_betacode_start(self.data[0])) {
            self.data = self.data[1..];
            while (self.data.len > 0 and is_ascii_betacode(self.data[0])) {
                self.advance();
            }

            // Grab ' at end of word to signify ellision
            if (self.data.len > 0 and self.data[0] == '\'') {
                self.data = self.data[1..];
            }
            value.len = self.data.ptr - value.ptr;

            self.greek_buffer.clear();
            const greek = betacode_to_greek(value, .tlg, &self.greek_buffer) catch |e| {
                std.log.err("invalid betacode {s}. {any}", .{ value, e });
                return .{ .invalid_token = value };
            };

            // Add any leftover punctuation to the `value` but not the word.
            while (self.data.len > 0 and is_punctuation(self.data[0])) {
                try self.greek_buffer.append(self.data[0]);
                self.data = self.data[1..];
                value.len += 1;
            }

            if (self.data.len == 0 or is_eol(self.data[0]) or is_ascii_whitespace(self.data[0])) {
                return .{ .word = .{ .text = self.greek_buffer.slice(), .word = greek } };
            }

            return .{ .invalid_token = value[0 .. value.len + 1] };
        }

        // Is it a paragraph mark?
        if (self.data[0] == '?') {
            self.advance();
            return .{ .paragraph = {} };
        }

        // Is this a parsing tag
        if (self.data[0] == '{') {
            self.advance();
            if (self.data.len > 1 and (self.data[0] == 'N' or
                self.data[0] == 'B' or self.data[0] == 'C' or
                self.data[0] == 'M' or self.data[0] == 'S' or
                self.data[0] == 'E') and is_ascii_whitespace(self.data[1]))
            {
                // B and N annotations can be skipped
                while (self.data.len > 0 and self.data[0] != '}') {
                    self.advance();
                }
                if (self.data.len > 0 and self.data[0] == '}') {
                    self.advance();
                }
                return self.next();
            }
            _ = self.skip_space();
            value = self.data;
            while (self.data.len > 0 and is_parsing_letter(self.data[0])) {
                self.advance();
            }
            value.len = self.data.ptr - value.ptr;
            if (value.len == 0) {
                return .{ .invalid_token = "ERR" };
            }
            _ = self.skip_space();
            if (self.data.len > 0 and self.data[0] == '}') {
                self.advance();
                if (value.len == 1 and is_paragraph_tag(value[0])) {
                    return .paragraph;
                }
                const parsing = parse_tag(value) catch |e| {
                    std.log.err("invalid parsing {s}. {any}", .{ value, e });
                    return .{ .invalid_token = value };
                };
                return .{ .parsing = parsing };
            }
            return .{ .invalid_token = value };
        }

        // Is this a variant marker?
        if (self.data[0] == '|') {
            const c = self.data[0..1];
            self.advance();
            const tag: Token = switch (self.variant) {
                0 => .{ .variant_mark = {} },
                1 => .{ .variant_alt = {} },
                2 => .{ .variant_end = {} },
                else => .{ .invalid_token = c },
            };
            self.variant += 1;
            if (self.variant == 3) self.variant = 0;
            return tag;
        }

        return .{ .invalid_token = self.data[0..1] };
    }

    /// Pass over whitespace and comments. Return the number of lines skipped.
    /// two consecutive line endings might be considered a paragraph in some
    /// data files.
    fn skip_space(self: *ByzParser) usize {
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

    inline fn advance(self: *ByzParser) void {
        self.data.len -= 1;
        self.data.ptr += 1;
    }

    pub fn debug_slice(self: *ByzParser) []const u8 {
        if (self.data.len == 0) return "";
        const show = @min(20, self.data.len);
        return self.data[0..show];
    }
};

pub fn punctuation(word: Word) ?[]const u8 {
    const trailing = word.text.len - word.word.len;
    if (trailing == 0) return null;
    return word.text[(word.text.len - trailing)..];
}

fn is_ascii_whitespace(c: u8) bool {
    return (c <= 32);
}

fn is_eol(c: u8) bool {
    return c == '\n' or c == '\r';
}

fn is_ascii_digit(c: u8) bool {
    return (c >= '0' and c <= '9');
}

inline fn is_ascii_letter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

inline fn is_ascii_betacode_start(c: u8) bool {
    return is_ascii_letter(c) or
        (c == '*' or c == '\\' or c == '/' or c == ')' or c == '(');
}

inline fn is_ascii_betacode(c: u8) bool {
    return is_ascii_betacode_start(c) or (c == '=' or c == '|' or c == '+');
}

fn is_parsing_letter(c: u8) bool {
    return is_ascii_letter(c) or is_ascii_digit(c) or c == '-';
}

fn is_verse_divider(c: u8) bool {
    return c == ':' or c == '.';
}

// Conservatively only accept punctuation we have seen in data sources.
fn is_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-';
}

fn is_paragraph_tag(c: u8) bool {
    return c == 'p' or c == 'P' or c == 'π' or c == 'Π';
}

// Test equals helper
pub fn ev(a: TokenType, b: Token) !Token {
    if (a == b) {
        return b;
    }
    std.log.err("Expected {s}={any}", .{ @tagName(a), b });
    return error.IncorrectTokenTypeReturned;
}

test "basic" {
    var p = ByzParser.init(&"   22".*, .mark);
    _ = try ev(.strongs, try p.next());
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"2  3".*, .mark);
    var v = try ev(.strongs, try p.next());
    try ee(2, v.strongs[0]);
    v = try ev(.strongs, try p.next());
    try ee(3, v.strongs[0]);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"22 2:3 0".*, .mark);
    v = try ev(.strongs, try p.next());
    try ee(22, v.strongs[0]);
    v = try ev(.verse, try p.next());
    try ee(2, v.verse.chapter);
    try ee(3, v.verse.verse);
    v = try ev(.strongs, try p.next());
    try ee(0, v.strongs[0]);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&" 2:2 \t \r\n 2:3 0 \n ".*, .mark);
    _ = try ev(.verse, try p.next());
    _ = try ev(.verse, try p.next());
    v = try ev(.strongs, try p.next());
    try ee(0, v.strongs[0]);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&" 2:2 \t \r\n  \n 2:3 0 \n ".*, .mark);
    _ = try ev(.verse, try p.next());
    _ = try ev(.paragraph, try p.next());
    _ = try ev(.verse, try p.next());
    v = try ev(.strongs, try p.next());
    try ee(0, v.strongs[0]);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&" 2:2,   ".*, .mark);
    _ = try ev(.invalid_token, try p.next());

    p = ByzParser.init(&" 22,   ".*, .mark);
    _ = try ev(.invalid_token, try p.next());

    p = ByzParser.init(&" 2: ".*, .mark);
    _ = try ev(.invalid_token, try p.next());

    p = ByzParser.init(&"99 2: ".*, .mark);
    _ = try ev(.strongs, try p.next());
    _ = try ev(.invalid_token, try p.next());

    p = ByzParser.init(&"3:8 o logos 9 ".*, .mark);
    _ = try ev(.verse, try p.next());
    v = try ev(.word, try p.next());
    try es("ο", v.word.word);
    v = try ev(.word, try p.next());
    try es("λογος", v.word.word);
    v = try ev(.strongs, try p.next());
    try ee(9, v.strongs[0]);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"3:8 o {N-NSM}".*, .mark);
    _ = try ev(.verse, try p.next());
    v = try ev(.word, try p.next());
    try es("ο", v.word.word);
    v = try ev(.parsing, try p.next());
    try ee(try parse_tag("N-NSM"), v.parsing);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"3:8 o {N-NSM} a".*, .mark);
    _ = try ev(.verse, try p.next());
    v = try ev(.word, try p.next());
    try es("ο", v.word.text);
    v = try ev(.parsing, try p.next());
    try ee(try parse_tag("N-NSM"), v.parsing);
    v = try ev(.word, try p.next());
    try es("α", v.word.word);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"3:8 o {N-NSM".*, .mark);
    _ = try ev(.verse, try p.next());
    v = try ev(.word, try p.next());
    try es("ο", v.word.word);
    _ = try ev(.invalid_token, try p.next());

    p = ByzParser.init(&"3:8 o | logos | logon | hn.".*, .mark);
    _ = try ev(.verse, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.variant_mark, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.variant_alt, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.variant_end, try p.next());
    v = try ev(.word, try p.next());
    try es("ην", v.word.word);
    try es("ην.", v.word.text);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&
        \\1:1 {p} o 3739 {R-NSN} hn 1510 5707 {V-IAI-3S} ap 575 {PREP} archv 746
        \\{N-GSF} o 3739 {R-ASN} akhkoamen 191 5754 {V-2RAI-1P-ATT}
    .*, .mark);
    _ = try ev(.verse, try p.next());
    _ = try ev(.paragraph, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.strongs, try p.next());

    // Skip N and B annotations
    p = ByzParser.init(&"BASILEU/EI E)PI\\ {N E)PI\\ > - } TH=S".*, .mark);
    v = try ev(.word, try p.next());
    try es("βασιλεύει", v.word.word);
    //try es("BASILEU/EI", v.word.word);
    v = try ev(.word, try p.next());
    try es("ἐπὶ", v.word.text);
    try es("ἐπὶ", v.word.word);
    v = try ev(.word, try p.next());
    try es("τῆς", v.word.text);
    try es("τῆς", v.word.word);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"12:23 *OU(=TOS HN E)N A)RXH=| O\\S O\\N QEO/N. ? ".*, .mark);
    v = try ev(.verse, try p.next());
    _ = try ee(12, v.verse.chapter);
    _ = try ee(23, v.verse.verse);
    _ = try ev(.word, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.word, try p.next());
    _ = try ev(.paragraph, try p.next());
    _ = try ev(.eof, try p.next());

    // Skip N and B annotations
    p = ByzParser.init(&
        \\02.01 teknia 5040 {N-VPN} mou 1473 {P-1GS} tauta 3778 {D-APN} 
        \\grafw 1125 {V-PAI-1S} umin 4771 {P-2DP} ina 2443 {CONJ}
    .*, .mark);
    v = try ev(.verse, try p.next());
    try ee(2, v.verse.chapter);
    try ee(1, v.verse.verse);
    v = try ev(.word, try p.next());
    try es("τεκνια", v.word.word);
    _ = try ev(.strongs, try p.next());
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("μου", v.word.word);
    _ = try ev(.strongs, try p.next());
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("ταυτα", v.word.word);
    _ = try ev(.strongs, try p.next());
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("γραφω", v.word.word);
    _ = try ev(.strongs, try p.next());
    v = try ev(.parsing, try p.next());
    try ee(try parse_tag("V-PAI-1S"), v.parsing);
    v = try ev(.word, try p.next());
    try es("υμιν", v.word.word);
    _ = try ev(.strongs, try p.next());
    v = try ev(.parsing, try p.next());
    try ee(try parse_tag("P-2DP"), v.parsing);

    p = ByzParser.init(&"A)NQRW/PWN,".*, .mark);
    v = try ev(.word, try p.next());
    try es("ἀνθρώπων", v.word.word);
    try es("ἀνθρώπων,", v.word.text);
    try es(",", punctuation(v.word).?);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"O A)NQRW/PWN, ".*, .mark);
    v = try ev(.word, try p.next());
    try ee(null, punctuation(v.word));
    v = try ev(.word, try p.next());
    try es("ἀνθρώπων", v.word.word);
    try es("ἀνθρώπων,", v.word.text);
    try es(",", punctuation(v.word).?);
    _ = try ev(.eof, try p.next());

    p = ByzParser.init(&"KAT' O)/NAR E)FA/NH AU)TW=|,".*, .mark);
    v = try ev(.word, try p.next());
    try es("κατ᾽", v.word.word);
    v = try ev(.word, try p.next());
    try es("ὄναρ", v.word.word);
}

test "test_parse_byzantine_files" {
    const allocator = std.testing.allocator;
    var token_count: usize = 0;

    var p = try reader().init(allocator, true);
    defer p.deinit(allocator);

    var ref: Reference = .unknown;
    while (true) {
        const token = p.next(allocator) catch |e| {
            std.log.err("Failed parsing {any}. Error {any}", .{
                @tagName(p.module()),
                e,
            });
            try std.testing.expect(false);
            break;
        };
        if (token == .verse) {
            if (token_count < 100) {
                try std.testing.expectEqual(.matthew, token.verse.book);
            }
            if (.unknown != token.verse.book) {
                try std.testing.expect(.unknown != token.verse.book);
            }
            ref = token.verse;
        }
        token_count += 1;
        if (.eof == token) {
            break;
        }
        if (.invalid_token == token) {
            std.log.err("invalid token = '{s}' in book {s} char={d}", .{
                token.invalid_token,
                @tagName(ref.book),
                p.data.ptr - p.original.ptr,
            });
            try std.testing.expect(false);
            break;
        }
    }
    try std.testing.expectEqual(486791, token_count);
}

const std = @import("std");
const bufPrint = std.fmt.bufPrint;
const BoundedArray = std.BoundedArray;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const warn = std.log.warn;
const err = std.log.err;
const debug = std.log.debug;
const Allocator = std.mem.Allocator;

const praxis = @import("praxis");
const Parsing = praxis.Parsing;
const Reference = praxis.Reference;
const BetacodeType = praxis.BetacodeType;
const parse_tag = praxis.parse;
const betacode_to_greek = praxis.betacode_to_greek;

const modules = @import("modules.zig");
const load_file_bytes = modules.load_file_bytes;
const Token = modules.Token;
const TokenType = modules.TokenType;
const Module = modules.Module;
const Paragraph = modules.Paragraph;
const Verse = modules.Verse;
const Word = modules.Word;
const extract_book_from_filename = modules.extract_book_from_filename;

const ee = std.testing.expectEqual;
const es = std.testing.expectEqualStrings;
