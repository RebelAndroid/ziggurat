const std = @import("std");
const cpuid = @import("cpuid.zig");

pub const StateComponentBitmaps = packed struct {
    x87: bool,
    sse: bool,
    avx: bool,

    // MPX
    bndregs: bool,
    bndcsr: bool,

    // AVX-512
    opmask: bool,
    zmm_hi256: bool,
    h16_zmm: bool,

    pt: bool,
    pkru: bool,
    pasid: bool,

    // CET
    cet_u: bool,
    cet_s: bool,

    hdc_state: bool,
    uintr: bool,
    lbr: bool,
    hwp: bool,

    // AMX
    tilecfg: bool,
    tiledata: bool,

    _1: u44,
    _2: bool,
};

// pub fn get_feature_information() StateComponentBitmaps {
//     var x = cpuid.CpuidResult{};
//     get_cpuid(0x0D, 0, &x);
//     return @bitCast(x.ecx);
// }

test "xsave sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(StateComponentBitmaps));
}
