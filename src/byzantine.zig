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
        data: []u8,
        parser2: ByzParser,
        data2: []u8,
        files_index: usize = 0,
        carryover_token: TextToken = .unknown,
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

        pub fn value(self: *Self) []const u8 {
            return self.parser.value;
        }

        pub fn punctuation(self: *Self) ?[]const u8 {
            return self.parser2.punctuation();
        }

        pub fn greek(self: *Self) []const u8 {
            if (self.parser2.greek.len > 0) {
                return self.parser2.greek.slice();
            }
            return self.parser.value;
        }

        pub fn word(self: *Self) []const u8 {
            return self.parser.word;
        }

        // Read parser2 tokens for paragraph and accentation,
        // supplimented by parser1 tokens for parsing data.
        pub fn next(self: *Self, allocator: Allocator) !TextToken {
            var token: TextToken = .unknown;

            if (self.carryover_token != .unknown) {
                token = self.carryover_token;
                self.carryover_token = .unknown;
                if (self.verbose)
                    debug("using the holdback BP5({s} {s})", .{
                        @tagName(token),
                        self.parser.value,
                    });
            } else {
                token = try self.parser.next();
            }

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
                    if (token != token2) {
                        err("Verse marker misalignment. {s} BP5({s} {s}) TXT({s} {s})", .{
                            @tagName(self.parser.reference.book),
                            @tagName(token),
                            self.parser.value,
                            @tagName(token2),
                            self.parser2.value,
                        });
                        @panic("Verse misalignment.");
                    }
                    if (self.verbose)
                        debug("BP5({s} {s}) aligns to TXT({s} {s})", .{
                            @tagName(token),
                            self.parser.value,
                            @tagName(token2),
                            self.parser2.value,
                        });
                    return token;
                },
                .word => {
                    // Secondary parser should have the same word for us, but
                    // it might be a paragraph.
                    const token2 = try self.parser2.next();
                    if (token2 == .paragraph) {
                        if (self.verbose)
                            debug("BP5({s} {s}) holdback. TXT({s})", .{
                                @tagName(token),
                                self.parser.value,
                                @tagName(token2),
                            });
                        self.carryover_token = token;
                        return token2;
                    }
                    if (self.verbose)
                        debug("BP5({s} {s}) aligns to TXT({s} {s})", .{
                            @tagName(token),
                            self.parser.value,
                            @tagName(token2),
                            self.parser2.value,
                        });
                    if (token2 != .word) {
                        @panic("Expected word in TXT file");
                    }
                    return token;
                },
                .variant_alt, .variant_end, .variant_mark => {
                    // Should not be sent
                    unreachable;
                },
                .eof => {
                    // Already handled above
                    unreachable;
                },
                .strongs, .parsing, .paragraph, .unexpected_character, .unknown => return token,
            }

            return token;
        }

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.byzantine;
        }

        pub fn reference(self: *Self) praxis.Reference {
            return self.parser.reference;
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

    /// The text value of each recognised token
    value: []const u8 = "",

    /// If a token is a `word`, then this variable contains
    /// the word minus any punctuation.
    word: []const u8 = "",
    greek: BoundedArray(u8, praxis.MAX_WORD_SIZE),

    /// Internal state tracking of variant markers.
    variant: u8 = 0,

    reference: Reference = .unknown,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []const u8, book: praxis.Book) ByzParser {
        return .{
            .data = data,
            .original = data,
            .value = "",
            .word = "",
            .variant = 0,
            .greek = .{ .len = 0 },
            .reference = .{
                .module = .byzantine,
                .book = book,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *ByzParser) !TextToken {
        const lines = self.skip_space();
        if (lines > 1) {
            self.value.len = self.data.ptr - self.value.ptr;
            return .paragraph;
        }
        if (self.data.len == 0) return .eof;
        self.value = self.data;

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
                self.value.len = self.data.ptr - self.value.ptr;
                if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                    return .strongs;
                }
                return .unexpected_character;
            } else {
                // More characters exist and its a verse divider.
                // It's a verse reference.
                self.reference.chapter = x;
                x = 0;
                self.advance();
                if (!is_ascii_digit(self.data[0]))
                    return .unexpected_character;
                while (self.data.len > 0 and is_ascii_digit(self.data[0])) {
                    x = (x * 10) + (self.data[0] - '0');
                    self.advance();
                }
                self.reference.verse = x;
                self.value.len = self.data.ptr - self.value.ptr;
                if (self.variant != 0) {
                    warn("Verse marker '{s}' encountered in variant.", .{self.value});
                }
                if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                    return .verse;
                }
                return .unexpected_character;
            }
        }

        // Is this a word?
        if (is_ascii_betacode_start(self.data[0])) {
            self.advance();
            while (self.data.len > 0 and is_ascii_betacode(self.data[0])) {
                self.advance();
            }
            self.word = self.value;
            self.word.len = self.data.ptr - self.value.ptr;

            // Option 1 is to end by whitespace/eof
            if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                // Ended by whitespace or no more data
                self.value.len = self.data.ptr - self.value.ptr;
                self.greek.clear();
                _ = betacode_to_greek(self.value, .tlg, &self.greek) catch |e| {
                    std.log.err("invalid betacode {s}", .{self.value});
                    return e;
                };
                while (self.data.len > 0 and is_punctuation(self.data[0])) {
                    self.advance();
                    self.value.len += 1;
                }
                return .word;
            }

            // Grab ' at end of word to signify ellision
            if (self.data[0] == '\'') {
                self.advance();
                self.value.len = self.data.ptr - self.value.ptr;
                self.word = self.value;
                if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                    self.greek.clear();
                    _ = betacode_to_greek(self.value, .tlg, &self.greek) catch |e| {
                        std.log.err("invalid betacode {s}", .{self.value});
                        return e;
                    };
                    while (self.data.len > 0 and is_punctuation(self.data[0])) {
                        self.advance();
                        self.value.len += 1;
                    }
                    return .word;
                }
            }

            // Is the trailing character valid punctuation?
            if (is_punctuation(self.data[0])) {
                self.value.len = self.data.ptr - self.value.ptr;
                self.word = self.value; // word should not include the punctuation.
                self.advance();
                while (self.data.len > 0 and is_punctuation(self.data[0])) {
                    self.advance();
                }
                if (self.data.len == 0 or is_ascii_whitespace(self.data[0])) {
                    self.value.len = self.data.ptr - self.value.ptr;
                    _ = betacode_to_greek(self.word, .tlg, &self.greek) catch |e| {
                        std.log.err("check {s}", .{self.value});
                        return e;
                    };
                    return .word;
                }
            }

            return .unexpected_character;
        }

        // Is it a paragraph mark?
        if (self.data[0] == '?') {
            self.advance();
            self.value.len = self.data.ptr - self.value.ptr;
            return .paragraph;
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
            self.value = self.data;
            while (self.data.len > 0 and is_parsing_letter(self.data[0])) {
                self.advance();
            }
            self.value.len = self.data.ptr - self.value.ptr;
            if (self.value.len == 0) {
                return .unexpected_character;
            }
            _ = self.skip_space();
            if (self.data.len > 0 and self.data[0] == '}') {
                self.advance();
                if (self.value.len == 1 and is_paragraph_tag(self.value[0])) {
                    return .paragraph;
                }
                _ = try parse_tag(self.value);
                return .parsing;
            }
            return .unexpected_character;
        }

        // Is this a variant marker?
        if (self.data[0] == '|') {
            self.advance();
            self.value.len = self.data.ptr - self.value.ptr;
            const tag: TextToken = switch (self.variant) {
                0 => .variant_mark,
                1 => .variant_alt,
                2 => .variant_end,
                else => .unexpected_character,
            };
            self.variant += 1;
            if (self.variant == 3) self.variant = 0;
            return tag;
        }

        return .unexpected_character;
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

    pub fn punctuation(self: *ByzParser) ?[]const u8 {
        const trailing = self.value.len - self.word.len;
        if (trailing == 0) return null;
        return self.value[(self.value.len - trailing)..];
    }

    pub fn debug_slice(self: *ByzParser) []const u8 {
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

test "basic" {
    var p = ByzParser.init(&"   22".*, .mark);
    try ee(.strongs, p.next());
    try ee(.eof, p.next());

    p = ByzParser.init(&"2  3".*, .mark);
    try ee(.strongs, p.next());
    try es("2", p.value);
    try ee(.strongs, p.next());
    try es("3", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&"22 2:3 0".*, .mark);
    try ee(.strongs, p.next());
    try es("22", p.value);
    try ee(.verse, p.next());
    try es("2:3", p.value);
    try ee(.strongs, p.next());
    try es("0", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&" 2:2 \t \r\n 2:3 0 \n ".*, .mark);
    try ee(.verse, p.next());
    try ee(.verse, p.next());
    try ee(.strongs, p.next());
    try es("0", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&" 2:2 \t \r\n  \n 2:3 0 \n ".*, .mark);
    try ee(.verse, p.next());
    try ee(.paragraph, p.next());
    try ee(.verse, p.next());
    try ee(.strongs, p.next());
    try es("0", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&" 2:2,   ".*, .mark);
    try ee(.unexpected_character, p.next());

    p = ByzParser.init(&" 22,   ".*, .mark);
    try ee(.unexpected_character, p.next());

    p = ByzParser.init(&" 2: ".*, .mark);
    try ee(.unexpected_character, p.next());

    p = ByzParser.init(&"99 2: ".*, .mark);
    try ee(.strongs, p.next());
    try ee(.unexpected_character, p.next());

    p = ByzParser.init(&"3:8 o logos 9 ".*, .mark);
    try ee(.verse, p.next());
    try ee(.word, p.next());
    try es("o", p.value);
    try ee(.word, p.next());
    try es("logos", p.value);
    try ee(.strongs, p.next());
    try es("9", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&"3:8 o {N-NSM}".*, .mark);
    try ee(.verse, p.next());
    try ee(.word, p.next());
    try es("o", p.value);
    try ee(.parsing, p.next());
    try es("N-NSM", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&"3:8 o {N-NSM} a".*, .mark);
    try ee(.verse, p.next());
    try ee(.word, p.next());
    try es("o", p.value);
    try ee(.parsing, p.next());
    try es("N-NSM", p.value);
    try ee(.word, p.next());
    try es("a", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&"3:8 o {N-NSM".*, .mark);
    try ee(.verse, p.next());
    try ee(.word, p.next());
    try es("o", p.value);
    try ee(.unexpected_character, p.next());

    p = ByzParser.init(&"3:8 o | logos | logon | hn.".*, .mark);
    try ee(.verse, p.next());
    try ee(.word, p.next());
    try ee(.variant_mark, p.next());
    try ee(.word, p.next());
    try ee(.variant_alt, p.next());
    try ee(.word, p.next());
    try ee(.variant_end, p.next());
    try ee(.word, p.next());
    try es("hn", p.word);
    try es("hn.", p.value);
    try ee(.eof, p.next());

    p = ByzParser.init(&
        \\1:1 {p} o 3739 {R-NSN} hn 1510 5707 {V-IAI-3S} ap 575 {PREP} archv 746
        \\{N-GSF} o 3739 {R-ASN} akhkoamen 191 5754 {V-2RAI-1P-ATT}
    .*, .mark);
    try ee(.verse, p.next());
    try ee(.paragraph, p.next());
    try ee(.word, p.next());
    try ee(.strongs, p.next());

    // Skip N and B annotations
    p = ByzParser.init(&"BASILEU/EI E)PI\\ {N E)PI\\ > - } TH=S".*, .mark);
    try ee(.word, p.next());
    try es("βασιλεύει", p.greek.slice());
    try es("BASILEU/EI", p.value);
    try ee(.word, p.next());
    try es("E)PI\\", p.value);
    try es("ἐπὶ", p.greek.slice());
    try ee(.word, p.next());
    try es("TH=S", p.value);
    try es("τῆς", p.greek.slice());
    try ee(.eof, p.next());

    p = ByzParser.init(&"12:23 *OU(=TOS HN E)N A)RXH=| O\\S O\\N QEO/N. ? ".*, .mark);
    try ee(.verse, p.next());
    try ee(12, p.reference.chapter);
    try ee(23, p.reference.verse);
    try ee(.word, p.next());
    try ee(.word, p.next());
    try ee(.word, p.next());
    try ee(.word, p.next());
    try ee(.word, p.next());
    try ee(.word, p.next());
    try ee(.word, p.next());
    try ee(.paragraph, p.next());
    try ee(.eof, p.next());

    // Skip N and B annotations
    p = ByzParser.init(&
        \\02.01 teknia 5040 {N-VPN} mou 1473 {P-1GS} tauta 3778 {D-APN} 
        \\grafw 1125 {V-PAI-1S} umin 4771 {P-2DP} ina 2443 {CONJ}
    .*, .mark);
    try ee(.verse, p.next());
    try ee(2, p.reference.chapter);
    try ee(1, p.reference.verse);
    try ee(.word, p.next());
    try es("teknia", p.value);
    try ee(.strongs, p.next());
    try ee(.parsing, p.next());
    try ee(.word, p.next());
    try es("mou", p.value);
    try ee(.strongs, p.next());
    try ee(.parsing, p.next());
    try ee(.word, p.next());
    try es("tauta", p.value);
    try ee(.strongs, p.next());
    try ee(.parsing, p.next());
    try ee(.word, p.next());
    try es("grafw", p.value);
    try ee(.strongs, p.next());
    try ee(.parsing, p.next());
    try es("V-PAI-1S", p.value);
    try ee(.word, p.next());
    try es("umin", p.value);
    try ee(.strongs, p.next());
    try ee(.parsing, p.next());
    try es("P-2DP", p.value);

    p = ByzParser.init(&"A)NQRW/PWN,".*, .mark);
    try ee(.word, p.next());
    try es("A)NQRW/PWN", p.word);
    try es("A)NQRW/PWN,", p.value);
    try es("ἀνθρώπων", p.greek.slice());
    try es(",", p.punctuation().?);
    try ee(.eof, p.next());

    p = ByzParser.init(&"O A)NQRW/PWN, ".*, .mark);
    try ee(.word, p.next());
    try ee(null, p.punctuation());
    try ee(.word, p.next());
    try es("A)NQRW/PWN", p.word);
    try es("A)NQRW/PWN,", p.value);
    try es("ἀνθρώπων", p.greek.slice());
    try es(",", p.punctuation().?);
    try ee(.eof, p.next());

    p = ByzParser.init(&"KAT' O)/NAR E)FA/NH AU)TW=|,".*, .mark);
    try ee(.word, p.next());
    try es("KAT'", p.value);
    try ee(.word, p.next());
    try es("O)/NAR", p.value);
}

test "test_parse_byzantine_files" {
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
        if (token == .verse and token_count < 100) {
            try std.testing.expectEqual(.matthew, p.reference().book);
        }
        if (token == .verse and .unknown != p.reference().book) {
            try std.testing.expect(.unknown != p.reference().book);
        }
        token_count += 1;
        if (.eof == token) {
            break;
        }
        if (.unexpected_character == token) {
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
const TextToken = modules.TextToken;
const Module = modules.Module;
const Paragraph = modules.Paragraph;
const Verse = modules.Verse;
const Word = modules.Word;
const extract_book_from_filename = modules.extract_book_from_filename;

const ee = std.testing.expectEqual;
const es = std.testing.expectEqualStrings;
