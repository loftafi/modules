pub const folder = "resources/ccat";

pub const files = [_][]const u8{
    "01.Gen.1.mlxx",    "02.Gen.2.mlxx",    "03.Exod.mlxx",
    "04.Lev.mlxx",      "05.Num.mlxx",      "06.Deut.mlxx",
    "07.JoshB.mlxx",    "08.JoshA.mlxx",    "09.JudgesB.mlxx",
    "10.JudgesA.mlxx",  "11.Ruth.mlxx",     "12.1Sam.mlxx",
    "13.2Sam.mlxx",     "14.1Kings.mlxx",   "15.2Kings.mlxx",
    "16.1Chron.mlxx",   "17.2Chron.mlxx",   "18.1Esdras.mlxx",
    "19.2Esdras.mlxx",  "20.Esther.mlxx",   "21.Judith.mlxx",
    "22.TobitBA.mlxx",  "23.TobitS.mlxx",   "24.1Macc.mlxx",
    "25.2Macc.mlxx",    "26.3Macc.mlxx",    "27.4Macc.mlxx",
    "28.Psalms1.mlxx",  "29.Psalms2.mlxx",  "30.Odes.mlxx",
    "31.Proverbs.mlxx", "32.Qoheleth.mlxx", "33.Canticles.mlxx",
    "34.Job.mlxx",      "35.Wisdom.mlxx",   "36.Sirach.mlxx",
    "37.PsSol.mlxx",    "38.Hosea.mlxx",    "39.Micah.mlxx",
    "40.Amos.mlxx",     "41.Joel.mlxx",     "42.Jonah.mlxx",
    "43.Obadiah.mlxx",  "44.Nahum.mlxx",    "45.Habakkuk.mlxx",
    "46.Zeph.mlxx",     "47.Haggai.mlxx",   "48.Zech.mlxx",
    "49.Malachi.mlxx",  "50.Isaiah1.mlxx",  "51.Isaiah2.mlxx",
    "52.Jer1.mlxx",     "53.Jer2.mlxx",     "54.Baruch.mlxx",
    "55.EpJer.mlxx",    "56.Lam.mlxx",      "57.Ezek1.mlxx",
    "58.Ezek2.mlxx",    "59.BelOG.mlxx",    "60.BelTh.mlxx",
    "61.DanielOG.mlxx", "62.DanielTh.mlxx", "63.SusOG.mlxx",
    "64.SusTh.mlxx",
};

const word_column_width = 25;
const parsing_column_width = 10;

pub fn reader() type {
    return struct {
        const Self = @This();
        data: []u8,
        parser: CcatParser,
        files_index: usize,

        pub fn init(allocator: Allocator) !Self {
            const dir = try std.fs.cwd().openDir(folder, .{ .iterate = false });
            const data = try load_file_bytes(allocator, dir, files[0]);
            var parser = CcatParser.init(data);
            parser.current_verse.module = .ccat;
            parser.current_verse.book = extract_book_from_filename(ccat_book_name(files[0]));
            return .{
                .data = data,
                .parser = parser,
                .files_index = 0,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
        }

        pub fn next(self: *Self, allocator: Allocator) !Token {
            var token = try self.parser.next();
            if (token == .eof and self.files_index < files.len) {
                const dir = try std.fs.cwd().openDir(folder, .{});
                allocator.free(self.data);
                self.data = try load_file_bytes(allocator, dir, files[self.files_index]);
                self.parser = CcatParser.init(self.data);
                self.parser.current_verse.book = extract_book_from_filename(ccat_book_name(files[self.files_index]));
                token = try self.parser.next();
                self.files_index += 1;
            }
            return token;
        }

        pub fn module(_: *Self) praxis.Module {
            return praxis.Module.ccat;
        }

        pub fn debug_slice(self: *Self) []const u8 {
            return self.parser.debug_slice();
        }
    };
}

// Are we reading a verse reference or verse contents.
const State = enum {
    verse,
    contents,
};

const CcatParser = struct {
    /// A pointer to the original buffer.
    original: []const u8,

    /// This is a pointer to the data buffer that is advanced as we read.
    data: []const u8,

    /// Internal state tracking of variant markers.
    column: u8,
    mode: State,

    /// Track which verse we are reading
    current_verse: Reference = undefined,

    /// Reads token from the input data byte array. The array may
    /// be destructively modified in the process of reading it.
    pub fn init(data: []const u8) CcatParser {
        return .{
            .data = data,
            .original = data,
            .column = 0,
            .state = .verse,
            .current_verse = .{
                .module = .ccat,
                .book = .unknown,
                .chapter = 0,
                .verse = 0,
                .word = 0,
            },
        };
    }

    pub fn next(self: *CcatParser) !Token {
        if (self.data.len == 0) return .{ .eof = {} };

        if (false) {
            // Current version does not include paragraphs
            const lines = self.skip_space();
            if (lines > 1) {
                return .{ .paragraph = {} };
            }
        }

        if (self.mode == .verse) {
            var text = self.data;
            while (self.data.len > 0 and !is_eol(self.data[0])) {
                self.data = self.data[1..];
            }
            text.len = self.data.ptr - text.ptr;
            while (self.data.len > 0 and is_eol(self.data[0])) {
                self.data = self.data[1..];
            }
            const ref = praxis.Book.parse(text) catch |f| {
                err("Inknown reference: {s}.  Error: {any}", .{ text, f });
                return .{ .invalid_token = text };
            };
            self.mode = .contents;
            return .{ .verse = ref };
        }

        // Word appears first
        //
        //  *A)GAPH/SATE             VA  AAD2P  A)GAPA/W
        if (self.column == 0) {
            if (self.data.len < word_column_width) {
                return error.InvalidLineLength;
            }
            const text = trim_whitespace(self.data[0..word_column_width]);
            var buffer = std.BoundedArray(u8, praxis.MAX_WORD_SIZE).init(0);
            const word = betacode_to_greek(text, .default, &buffer);
            self.column = 1;
            return .{ .word = .{ .word = word, .text = word } };
        }

        // Send the parsing token second.
        if (self.column == 1) {
            if (self.data.len < parsing_column_width) {
                return error.InvalidLineLength;
            }
            const text = self.data[0..parsing_column_width];
            const parsing = parse_tag(text) catch |f| {
                err("Invalid parsing string: {s} Error: {any}", .{ text, f });
                return .{ .invalid_field = text };
            };
            return .{ .parsing = .{ .parsing = parsing } };
        }

        // Skip final column for now
        while (self.data.len > 0 and !is_eol(self.data[0]))
            self.data = self.data[1..];
        var lines: usize = 0;
        while (self.data.len > 0 and is_eol(self.data[0])) {
            self.data = self.data[1..];
            lines += 1;
        }
        self.column = 0;
        if (lines > 1) {
            self.mode = .verse;
        }

        return self.next();
    }

    fn trim_whitespace(text: []const u8) []const u8 {
        var value = text;
        while (value.len > 0 and is_ascii_whitespace(value[0])) {
            value = value[1..];
        }
        while (value.len > 0 and is_ascii_whitespace(value[value.len - 1])) {
            value = value[0 .. value.len - 1];
        }
        return value;
    }

    /// Pass over whitespace and comments. Return the number of lines skipped.
    /// two consecutive line endings might be considered a paragraph in some
    /// data files.
    fn skip_space(self: *CcatParser) usize {
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

    pub fn punctuation(self: *CcatParser) ?[]const u8 {
        const trailing = self.value.len - self.word.len;
        if (trailing == 0) return null;
        return self.value[(self.value.len - trailing)..];
    }

    pub fn debug_slice(self: *CcatParser) []const u8 {
        if (self.data.len == 0) return "";
        const show = @min(20, self.data.len);
        return self.data[0..show];
    }
};

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
fn is_ccat_punctuation(c: u8) bool {
    return c == ':' or c == '.' or c == ',' or c == ';' or c == '-';
}

fn ccat_book_name(name: []const u8) []const u8 {
    //if (std.ascii.eqlIgnoreCase("64-Jn-morphgnt.txt", name)) {
    //    return "64-Jh-morphgnt.txt";
    //}
    return name;
}

test "basic_ccat" {
    var p = CcatParser.init(&
        \\Wis 3:5
        \\*A)GAPH/SATE             VA  AAD2P  A)GAPA/W
        \\DIKAIOSU/NHN,            N1  ASF    DIKAIOSU/NH
        \\OI(                      RA  VPM    O(
        \\
        \\Gen 4:6
        \\KRI/NONTES               V1  PAPVPM KRI/NW
        \\TH\N                     RA  ASF    O(
        \\GH=N                     N1  ASF    GH=
        \\FRONH/SATE               VA  AAD2P  FRONE/W
        \\PERI\                    P          PERI/
        \\TOU=                     RA  GSM    O(
    .*);
    var v = try ev(.verse, try p.next());
    try ee(praxis.Book.wisdom, v.verse.book);
    try ee(3, v.verse.chapter);
    try ee(5, v.verse.verse);
    v = try ev(.word, try p.next());
    try es("Ἀγαπήσατε", v.word.word);
    try es("Ἀγαπήσατε", v.word.text);
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("δικαιοσύνην", v.word.word);
    try es("δικαιοσύνην,", v.word.text);
    _ = try ev(.parsing, try p.next());
    v = try ev(.word, try p.next());
    try es("οἱ,", v.word.text);
    try es("οἱ", v.word.word);
    _ = try ev(.parsing, try p.next());
    v = try ev(.verse, try p.next());
    try ee(praxis.Book.genesis, v.verse.book);
    try ee(4, v.verse.chapter);
    try ee(6, v.verse.verse);
    _ = try ev(.word, try p.next());
    try es("κρίνοντες,", v.word.text);
    try es("κρίνοντες", v.word.word);
    _ = try ev(.parsing, try p.next());
}

test "test_parse_ccat_files" {
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
const parse_tag = praxis.parse_morphgnt;
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
const ev = @import("test.zig").ev;
