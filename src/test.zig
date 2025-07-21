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
const module = @import("modules.zig");
const Token = module.Token;
const TokenType = module.TokenType;
