pub const CpuidResult = packed struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
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
