//! A module contains a biblical text or other related ancient Greek document.
//! Helper functions to load byzantine text and nestle 1904 text as a module
//! are provided.

const std = @import("std");
const testing = std.testing;

pub const Module = @import("module.zig").Module;
pub const byzantine = @import("byzantine.zig");
pub const nestle = @import("nestle.zig");

test {
    std.testing.refAllDecls(@This());
}
