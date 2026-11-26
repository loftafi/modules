// Test equals helper
pub fn ev(a: TokenType, b: Token) !Token {
    if (a == b) {
        return b;
    }
    err("Expected {s}={any}", .{ @tagName(a), b });
    return error.IncorrectTokenTypeReturned;
}

const std = @import("std");
const err = std.log.err;
const Module = @import("Module.zig");
const Token = Module.Token;
const TokenType = Module.TokenType;
