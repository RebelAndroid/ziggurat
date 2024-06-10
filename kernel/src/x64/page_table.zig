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
    accessed: bool = false,
    /// ignored
    _1: bool = false,
    /// reserved
    _2: bool = false,
    /// ignored
    _3: u3 = 0,
    /// ignored, used by HLAT paging
    _4: bool = false,
    /// Physical address of pdpt referenced by this entry
    pdpt: u40 = 0,
    _5: u11 = 0,
    execute_disable: bool,
    pub fn get_pdpt(self: PML4E) u64 {
        return @as(u64, self.pdpt) << 12;
    }
    pub fn set_pdpt(self: *volatile PML4E, pdpt: u64) void {
        self.pdpt = @truncate(pdpt >> 12);
    }
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
    accessed: bool = false,
    /// dirty
    dirty: bool = false,
    /// set to map a 1GB page
    page_size: bool = true,
    global: bool = false,
    /// Ignored
    _1: u2 = 0,
    /// Ignored, used for HLAT paging
    _2: bool = false,
    /// Page attribute table
    pat: bool = false,
    /// Reserved
    _3: u17 = 0,
    /// Physical address of page referenced by this entry
    page: u22 = 0,
    /// Ignored
    _4: u7 = 0,
    /// Used for protection keys
    _5: u4 = 0,
    execute_disable: bool,
    pub fn set_page(self: *volatile PDPTE_1GB, page: u64) void {
        self.page = @truncate(page >> 30);
    }
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
    accessed: bool = false,
    /// ignored
    _1: bool = false,
    /// clear to reference a page directory
    page_size: bool = false,
    /// Ignored
    _2: u3 = 0,
    /// Ignored, used for HLAT paging
    _3: bool = false,
    /// Physical directory of page table referenced by this entry
    page_directory: u40 = 0,
    /// Ignored
    _5: u11 = 0,
    execute_disable: bool,
    pub fn get_page_directory(self: PDPTE_PD) u64 {
        return @as(u64, self.page_directory) << 12;
    }
    pub fn set_page_directory(self: *volatile PDPTE_PD, page_directory: u64) void {
        self.page_directory = @truncate(page_directory >> 12);
    }
};

pub const PDPTE = packed union {
    huge_page: PDPTE_1GB,
    page_directory: PDPTE_PD,
    pub fn is_huge_page(self: PDPTE) bool {
        return self.huge_page.page_size;
    }
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
    accessed: bool = false,
    /// dirty
    dirty: bool = false,
    /// set to map a 2MB page
    page_size: bool = true,
    global: bool = false,
    /// Ignored
    _1: u2 = 0,
    /// Ignored, used for HLAT paging
    _2: bool = false,
    /// Page attribute table
    pat: bool = false,
    /// Reserved
    _3: u8 = 0,
    /// Physical address of page referenced by this entry
    page: u31 = 0,
    /// Ignored
    _4: u7 = 0,
    /// Used for protection keys
    _5: u4 = 0,
    execute_disable: bool,
    pub fn set_page(self: *volatile PDE_2MB, page: u64) void {
        self.page = @truncate(page >> 21);
    }
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
    accessed: bool = false,
    /// ignored
    _1: bool = false,
    /// clear to reference a page table
    page_size: bool = false,
    /// Ignored
    _2: u3 = 0,
    /// Ignored, used for HLAT paging
    _3: bool = false,
    /// Physical directory of page table referenced by this entry
    page_table: u40 = 0,
    /// Ignored
    _5: u11 = 0,
    execute_disable: bool,
    pub fn get_page_table(self: PDE_PT) u64 {
        return @as(u64, self.page_table) << 12;
    }
    pub fn set_page_table(self: *volatile PDE_PT, page_table: u64) void {
        self.page_table = @truncate(page_table >> 12);
    }
};

pub const PDE = packed union {
    huge_page: PDE_2MB,
    page_table: PDE_PT,
    pub fn is_huge_page(self: PDE) bool {
        return self.huge_page.page_size;
    }
};

/// Page Directory
pub const PD: type = [512]PDE;

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
    accessed: bool = false,
    /// dirty
    dirty: bool = false,
    /// page attribute table
    pat: bool = false,
    global: bool = false,
    /// Ignored
    _1: u2 = 0,
    /// Ignored, used for HLAT paging
    _2: bool = false,
    /// Physical address of page referenced by this entry
    page: u40 = 0,
    /// Ignored
    _4: u7 = 0,
    /// Used for protection keys
    _5: u4 = 0,
    execute_disable: bool,
    pub fn set_page(self: *volatile PTE, physical_address: u64) void {
        self.page = @truncate(physical_address >> 12);
    }
};

pub const PT: type = [512]PTE;

pub const VirtualAddress = packed struct {
    page_offset: u12,
    table: u9,
    directory: u9,
    directory_pointer: u9,
    pml4: u9,
    sign_extension: u16,
};

pub const PageType = enum {
    four_kb,
    two_mb,
    one_gb,
};

pub const Page = union(enum) {
    four_kb: VirtualAddress,
    two_mb: VirtualAddress,
    one_gb: VirtualAddress,
};

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

    // Size of VirtualAddress
    try std.testing.expectEqual(64, @bitSizeOf(VirtualAddress));
}
