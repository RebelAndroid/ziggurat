const std = @import("std");

pub const PML4E = packed struct {
    present: bool,
    /// Allows writing
    read_write: bool,
    /// allows user-mode access
    user_supervisor: bool,
    /// enables write through
    pwt: bool,
    /// disables cache
    pcd: bool,
    /// accessed
    accessed: bool,
    /// ignored
    _1: bool = false,
    /// reserved
    _2: bool = false,
    /// ignored
    _3: u3 = 0,
    /// ignored, used by HLAT paging
    _4: bool = false,
    /// Physical address of pdpt referenced by this entry
    pdpt: u40,
    _5: u11 = 0,
    execute_disable: bool,
};

pub const PML4: type = [512]PML4E;

/// Page Directory Pointer Table Entry that maps a 1GB page
pub const PDPTE_1GB = packed struct {
    present: bool,
    /// Allows writing
    read_write: bool,
    /// allows user-mode access
    user_supervisor: bool,
    /// enables write through
    pwt: bool,
    /// disables cache
    pcd: bool,
    /// accessed
    accessed: bool,
    /// dirty
    dirty: bool,
    /// set to map a 1GB page
    page_size: bool = true,
    global: bool,
    /// Ignored
    _1: u2 = 0,
    /// Ignored, used for HLAT paging
    _2: bool = false,
    /// Page attribute table
    pat: bool,
    /// Reserved
    _3: u17 = 0,
    /// Physical address of page referenced by this entry
    page: u22,
    /// Ignored
    _4: u7 = 0,
    /// Used for protection keys
    _5: u4 = 0,
    execute_disable: bool,
};

/// Page Directory Pointer Table Entry that references a page directory
pub const PDPTE_PD = packed struct {
    present: bool,
    /// Allows writing
    read_write: bool,
    /// allows user-mode access
    user_supervisor: bool,
    /// enables write through
    pwt: bool,
    /// disables cache
    pcd: bool,
    /// accessed
    accessed: bool,
    /// ignored
    _1: bool = false,
    /// clear to reference a page directory
    page_size: bool = false,
    /// Ignored
    _2: u3 = 0,
    /// Ignored, used for HLAT paging
    _3: bool = false,
    /// Physical directory of page table referenced by this entry
    page_directory: u40,
    /// Ignored
    _5: u11 = 0,
    execute_disable: bool,
};

pub const PDPTE = packed union {
    huge_page: PDPTE_1GB,
    page_directory: PDPTE_PD,
};

/// Page Directory Pointer Table
pub const PDPT: type = [512]PDPTE;

/// Page Directory Entry that maps a 2MB page
pub const PDE_2MB = packed struct {
    present: bool,
    /// Allows writing
    read_write: bool,
    /// allows user-mode access
    user_supervisor: bool,
    /// enables write through
    pwt: bool,
    /// disables cache
    pcd: bool,
    /// accessed
    accessed: bool,
    /// dirty
    dirty: bool,
    /// set to map a 2MB page
    page_size: bool = true,
    global: bool,
    /// Ignored
    _1: u2 = 0,
    /// Ignored, used for HLAT paging
    _2: bool = false,
    /// Page attribute table
    pat: bool,
    /// Reserved
    _3: u8 = 0,
    /// Physical address of page referenced by this entry
    page: u31,
    /// Ignored
    _4: u7 = 0,
    /// Used for protection keys
    _5: u4 = 0,
    execute_disable: bool,
};

/// Page Directory Entry that references a page table
pub const PDE_PT = packed struct {
    present: bool,
    /// Allows writing
    read_write: bool,
    /// allows user-mode access
    user_supervisor: bool,
    /// enables write through
    pwt: bool,
    /// disables cache
    pcd: bool,
    /// accessed
    accessed: bool,
    /// ignored
    _1: bool = false,
    /// clear to reference a page table
    page_size: bool = false,
    /// Ignored
    _2: u3 = 0,
    /// Ignored, used for HLAT paging
    _3: bool = false,
    /// Physical directory of page table referenced by this entry
    page_table: u40,
    /// Ignored
    _5: u11 = 0,
    execute_disable: bool,
};

pub const PDE = packed union {
    huge_page: PDE_2MB,
    page_table: PDE_PT,
};

/// Page Directory
const PD: type = [512]PDE;

/// Page Table Entry, always maps a 4kb page
pub const PTE = packed struct {
    present: bool,
    /// Allows writing
    read_write: bool,
    /// allows user-mode access
    user_supervisor: bool,
    /// enables write through
    pwt: bool,
    /// disables cache
    pcd: bool,
    /// accessed
    accessed: bool,
    /// dirty
    dirty: bool,
    /// page attribute table
    pat: bool,
    global: bool,
    /// Ignored
    _1: u2 = 0,
    /// Ignored, used for HLAT paging
    _2: bool = false,
    /// Physical address of page referenced by this entry
    page: u40,
    /// Ignored
    _4: u7 = 0,
    /// Used for protection keys
    _5: u4 = 0,
    execute_disable: bool,
};

const PT: type = [512]PTE;

test "Paging Structure Sizes" {
    // Sizes of entries
    try std.testing.expectEqual(64, @bitSizeOf(PML4E));
    try std.testing.expectEqual(64, @bitSizeOf(PDPTE_1GB));
    try std.testing.expectEqual(64, @bitSizeOf(PDPTE_PD));
    try std.testing.expectEqual(64, @bitSizeOf(PDPTE));
    try std.testing.expectEqual(64, @bitSizeOf(PDE_2MB));
    try std.testing.expectEqual(64, @bitSizeOf(PDE_PT));

    // Sizes of whole tables
    try std.testing.expectEqual(4096, @sizeOf(PML4));
    try std.testing.expectEqual(4096, @sizeOf(PDPT));
    try std.testing.expectEqual(4096, @sizeOf(PD));
    try std.testing.expectEqual(4096, @sizeOf(PT));
}
