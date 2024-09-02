const std = @import("std");

pub const CpuidResult = packed struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
};

const ExtendedFeatureFlagEnumeration1 = packed struct {
    fsgsbase: bool,
    ia32_tsc_adjust: bool,
    sgx: bool,
    bmi1: bool,
    hle: bool,
    avx2: bool,
    fdp_exception_only: bool,
    smep: bool,
    bmi2: bool,
    enhanced_rep_movsb_stosb: bool,
    invpcid: bool,
    rtm: bool,
    rdt_m: bool,
    deprecate_fpu_cs_ds: bool,
    mpx: bool,
    rdt_a: bool,
    avx512f: bool,
    avx512dq: bool,
    rdseed: bool,
    adx: bool,
    smap: bool,
    avx512ifma: bool,
    _: bool = false,
    clflushopt: bool,
    clwb: bool,
    intel_processor_trace: bool,
    avx512pf: bool,
    avx512er: bool,
    avx512cd: bool,
    sha: bool,
    avx512bw: bool,
    avx512vl: bool,
};

const ExtendedFeatureFlagEnumeration2 = packed struct {
    prefetch_wt1: bool,
    avx512_vbmi: bool,
    /// user-mode instruction prevention
    umip: bool,
    /// protection keys for user-mode pages
    pku: bool,
    ospke: bool,
    waitpkg: bool,
    avx512_vbmi2: bool,
    /// control flow enforcement technology - shadow stacks
    cet_ss: bool,
    gfni: bool,
    vaes: bool,
    vpclmulqdq: bool,
    avx512_vnni: bool,
    avx512_bitalg: bool,
    tme_en: bool,
    avx512_vpopcntdq: bool,
    _1: bool,
    /// support for 57 bit virtual addresses and 5 level paging
    la57: bool,
    mawau_value: u5,
    rdpid: bool,
    kl: bool,
    bus_lock_detect: bool,
    cldemote: bool,
    _2: bool,
    movdiri: bool,
    movdir64B: bool,
    enqcmd: bool,
    sgx_lc: bool,
    /// protection keys for kernel-mode pages
    pks: bool,
};

const ExtendedFeatureFlagEnumeration3 = packed struct {
    _1: bool,
    sgx_keys: bool,
    avx512_4vnniw: bool,
    avx512_4fmaps: bool,
    fast_short_rep_mov: bool,
    /// user interrupts
    uintr: bool,
    _2: u2,
    avx512_vp2intersect: bool,
    srbds_ctrl: bool,
    md_clear: bool,
    rtm_always_abort: bool,
    _3: bool,
    rtm_force_abort: bool,
    serialize: bool,
    hybrid: bool,
    tsxldtrk: bool,
    _4: bool,
    pconfig: bool,
    architectural_lbrs: bool,
    /// control flow enforcement technology indirect branch tracking
    cet_ibt: bool,
    _5: bool,
    amx_bf16: bool,
    avx512_fp16: bool,
    amx_tile: bool,
    amx_int8: bool,
    /// indirect branch restricted speculation, indirect branch predictor barrier
    ibrs_ibpb: bool,
    /// single thread indirect branch predictors
    stibp: bool,
    l1d_flush: bool,
    ia32_arch_compatibilities: bool,
    ia32_arch_core_capabilities: bool,
    /// speculative store bypass disable
    ssbd: bool,
};

const CpuidFeatures1 = packed struct {
    subleaf_limit: u32,
    flags1: ExtendedFeatureFlagEnumeration1,
    flags2: ExtendedFeatureFlagEnumeration2,
    flags3: ExtendedFeatureFlagEnumeration3,
};

pub extern fn get_cpuid(eax: u32, ecx: u32, out: *CpuidResult) callconv(.C) void;
comptime {
    asm (
        \\.globl get_cpuid
        \\.type get_cpuid @function
        \\get_cpuid:
        \\  movq %rbx, %r9
        \\  movl %edi, %eax
        \\  movl %esi, %ecx
        \\  movq %rdx, %r8
        \\  cpuid
        \\  movl %eax, (%r8)
        \\  movl %ebx, 4(%r8)
        \\  movl %ecx, 8(%r8)
        \\  movl %edx, 12(%r8)
        \\  movq %r9, %rbx
        \\  retq
    );
}

pub fn get_vendor_string() [12]u8 {
    var result: CpuidResult = .{};
    get_cpuid(0, 0, &result);
    const str = [12]u8{
        @truncate(result.ebx),
        @truncate(result.ebx >> 8),
        @truncate(result.ebx >> 16),
        @truncate(result.ebx >> 24),

        @truncate(result.edx),
        @truncate(result.edx >> 8),
        @truncate(result.edx >> 16),
        @truncate(result.edx >> 24),

        @truncate(result.ecx),
        @truncate(result.ecx >> 8),
        @truncate(result.ecx >> 16),
        @truncate(result.ecx >> 24),
    };
    return str;
}

pub fn get_features1() CpuidFeatures1 {
    var x = CpuidResult{};
    get_cpuid(0x07, 0, &x);
    return @bitCast(x);
}

const FeatureInformationEcx = packed struct {
    sse3: bool,
    pclmuqdq: bool,
    dtes64: bool,
    monitor: bool,
    ds_cpl: bool,
    vmx: bool,
    smx: bool,
    eist: bool,
    tm2: bool,
    ssse3: bool,
    cnxt_id: bool,
    sdbg: bool,
    fma: bool,
    cmpxchg16b: bool,
    xtpr_update_control: bool,
    pdcm: bool,
    _1: bool,
    pcid: bool,
    dca: bool,
    sse4_1: bool,
    sse4_2: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    tsc_deadline: bool,
    aesni: bool,
    xsave: bool,
    osxsave: bool,
    avx: bool,
    f16c: bool,
    rdrand: bool,
    _2: bool,
};

pub fn get_feature_information() FeatureInformationEcx {
    var x = CpuidResult{};
    get_cpuid(0x01, 0, &x);
    return @bitCast(x.ecx);
}

/// Table 3-11 in Intel SDM Vol 2A. 3-244
const FeatureInformationEdx = packed struct {
    fpu: bool,
    vme: bool,
    de: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cx8: bool,
    apic: bool,
    _1: bool,
    sep: bool,
    /// set if Memory Type Range Registers are supported
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse36: bool,
    psn: bool,
    clflush: bool,
    _2: bool,
    debug_store: bool,
    /// set if processor has MSRs to monitor temperature and control performance
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    ss: bool,
    htt: bool,
    tm: bool,
    _3: bool,
    pbe: bool,
};

pub fn get_feature_information2() FeatureInformationEdx {
    var x = CpuidResult{};
    get_cpuid(0x01, 0, &x);
    return @bitCast(x.edx);
}

test "CPUID sizes" {
    try std.testing.expectEqual(32, @bitSizeOf(FeatureInformationEcx));
    try std.testing.expectEqual(32, @bitSizeOf(FeatureInformationEdx));
}
