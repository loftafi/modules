const std = @import("std");
const testing = std.testing;

test {
    const byz = @import("byzantine.zig");
    std.testing.refAllDecls(byz);

    const nestle = @import("nestle.zig");
    std.testing.refAllDecls(nestle);
}
