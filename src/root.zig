const std = @import("std");
const testing = std.testing;

test {
    const byz = @import("byzantine.zig");
    std.testing.refAllDecls(byz);

    const nestle = @import("nestle.zig");
    std.testing.refAllDecls(nestle);

    // Additional modules that are not public domain.
    const cntr = @import("cntr.zig");
    std.testing.refAllDecls(cntr);

    //const sbl = @import("sbl.zig");
    //std.testing.refAllDecls(sbl);
}
