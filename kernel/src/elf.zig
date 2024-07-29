const std = @import("std");

const log = std.log.scoped(.elf);

/// The header of an elf file, valid only for the 64 executables
pub const Header = extern struct {
    /// Magic Number marking the file as an ELF, should be {0x7F, 'E', 'L', 'F'}
    magic: [4]u8,
    /// 1 for 32 bit, 2 for 64 bit
    bit_size: u8,
    /// 1 for little endian, 2 for big endian
    endianness: u8,
    version: u8,
    _1: [8]u8,
    typ: u16,
    instruction_set: u16,
    elf_version: u32,
    entry_point_offset: u64,
    program_header_table_offset: u64,
    section_header_table_offset: u64,
    flags: u32,
    elf_header_size: u16,
    /// Size of each entry in the program header table
    program_header_size: u16,
    /// Number of entries in the program header table
    program_header_table_size: u16,
    /// Size of each entry in the section header table
    section_header_size: u16,
    /// Number of entries in the section header table
    section_header_table_size: u16,
    section_index_to_section_header_string_table: u16,
};

pub const ProgramHeader = extern struct {
    typ: ProgramHeaderType,
    flags: ProgramHeaderFlags,
    offset: u64,
    virtual_address: u64,
    physical_address: u64,
    file_size: u64,
    memory_size: u64,
    alignment: u64,
};

pub const ProgramHeaderType = enum(u32) {
    none = 0,
    load = 1,
    dynamic = 2,
    interp = 3,
    note = 4,
    shlib = 5,
    phdr = 6,
    tls = 7,
    gnu_eh_frame = 0x60000000 + 0x474e550,
    gnu_stack = 0x60000000 + 0x474e551,
    gnu_relro = 0x60000000 + 0x474e552,
    gnu_property = 0x60000000 + 0x474e553,
    _,
};

pub const ProgramHeaderFlags = packed struct {
    executable: bool,
    writable: bool,
    readable: bool,
    _: u29,
};

pub const SectionHeader = extern struct {
    name: u32,
    typ: SectionHeaderType,
    flags: SectionHeaderFlags,
    address: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    address_align: u64,
    entry_size: u64,
};

pub const SectionHeaderType = enum(u32) {
    none = 0,
    progbits = 1,
    symbol_table = 2,
    string_table = 3,
    rela = 4,
    symbol_hash_table = 5,
    dynamic = 6,
    note = 7,
    nobits = 8,
    rel = 9,
    _1 = 10,
    dyn_sym = 11,
    init_array = 14,
    fini_array = 15,
    preinit_array = 16,
    group = 17,
    symbol_table_shndx = 18,
    _,
};

pub const SectionHeaderFlags = packed struct {
    writable: bool,
    alloc: bool,
    executable: bool,
    merge: bool,
    strings: bool,
    info_link: bool,
    link_order: bool,
    os_nonconforming: bool,
    group: bool,
    tls: bool,
    compressed: bool,
    _1: u9,
    os_flags: u8,
    processor_flags: u4,
    _2: u32,
};

pub fn load_elf(file: []align(8) const u8) void {
    const header: *const Header = @ptrCast(file);
    log.info("ELF header: {}\n", .{header});
    if (header.magic[0] != 0x7f or header.magic[1] != 'E' or header.magic[2] != 'L' or header.magic[3] != 'F') {
        log.err("init file is not an ELF! (invalid magic value)\n", .{});
    }
    if (header.bit_size != 2) {
        log.err("init file is not 64 bit!\n", .{});
    }
    if (header.instruction_set != 0x3E) {
        log.err("init file is not x86-64! found architecture: 0x{x}\n", .{header.instruction_set});
    }
    if (header.program_header_size != 56) {
        log.err("program header size not 56! found: {}\n", .{header.program_header_size});
    }
    const ptr: [*]const ProgramHeader = @alignCast(@ptrCast(&file[header.program_header_table_offset]));
    const program_header_table = ptr[0..header.program_header_table_size];
    for (program_header_table) |pheader| {
        log.info("program header: {}\n", .{pheader});
    }

    const ptr2: [*]const SectionHeader = @alignCast(@ptrCast(&file[header.section_header_table_offset]));
    const section_header_table = ptr2[0..header.section_header_table_size];
    for (section_header_table) |sheader| {
        log.info("section header: {}\n", .{sheader});
    }
    if (section_header_table[0].size != 0 or section_header_table[0].link != 0) {
        // If these fields are non-zero they hold the actual number of section header entries and index of the string table section
        log.err("TODO", .{});
        return;
    }
}

test "elf sizes" {
    try std.testing.expectEqual(64, @sizeOf(Header));
    try std.testing.expectEqual(56, @sizeOf(ProgramHeader));
    try std.testing.expectEqual(64, @sizeOf(SectionHeader));
    try std.testing.expectEqual(32, @bitSizeOf(ProgramHeaderFlags));
    try std.testing.expectEqual(64, @bitSizeOf(SectionHeaderFlags));
}
