const std = @import("std");
const pmm = @import("../pmm.zig");

pub const MapError = error{
    /// Indicates that a virtual address has already been mapped
    AlreadyPresent,
    Unaligned,
    NoMemory,
};

pub const PML4Entry = packed struct {
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
    pub fn getPdpt(self: PML4Entry) u64 {
        return @as(u64, self.pdpt) << 12;
    }
    pub fn setPdpt(self: *volatile PML4Entry, pdpt: u64) void {
        self.pdpt = @truncate(pdpt >> 12);
    }
};

pub const PML4: type = [512]PML4Entry;

/// Page Directory Pointer Table Entry that maps a 1GB page
pub const PdptEntry_1GB = packed struct {
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
    pub fn setPage(self: *volatile PdptEntry_1GB, page: u64) void {
        self.page = @truncate(page >> 30);
    }
};

/// Page Directory Pointer Table Entry that references a page directory
pub const PdptEntry_PD = packed struct {
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
    pub fn getPageDirectory(self: PdptEntry_PD) u64 {
        return @as(u64, self.page_directory) << 12;
    }
    pub fn setPageDirectory(self: *volatile PdptEntry_PD, page_directory: u64) void {
        self.page_directory = @truncate(page_directory >> 12);
    }
};

/// Page Directory Pointer Table Entry
pub const PdptEntry = packed union {
    huge_page: PdptEntry_1GB,
    page_directory: PdptEntry_PD,
    pub fn isHugePage(self: PdptEntry) bool {
        return self.huge_page.page_size;
    }
};

/// Page Directory Pointer Table
pub const Pdpt: type = [512]PdptEntry;

/// Page Directory Entry that maps a 2MB page
pub const PdEntry_2MB = packed struct {
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
    pub fn setPage(self: *volatile PdEntry_2MB, page: u64) void {
        self.page = @truncate(page >> 21);
    }
};

/// Page Directory Entry that references a page table
pub const PdEntry_PT = packed struct {
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
    pub fn getPageTable(self: PdEntry_PT) u64 {
        return @as(u64, self.page_table) << 12;
    }
    pub fn setPageTable(self: *volatile PdEntry_PT, page_table: u64) void {
        self.page_table = @truncate(page_table >> 12);
    }
};

pub const PdEntry = packed union {
    huge_page: PdEntry_2MB,
    page_table: PdEntry_PT,
    pub fn isHugePage(self: PdEntry) bool {
        return self.huge_page.page_size;
    }
};

/// Page Directory
pub const Pd: type = [512]PdEntry;

/// Page Table Entry, always maps a 4kb page
pub const PtEntry = packed struct {
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
    pub fn setPage(self: *volatile PtEntry, physical_address: u64) void {
        self.page = @truncate(physical_address >> 12);
    }
};

/// Page Table
pub const Pt: type = [512]PtEntry;

pub const VirtualAddress = packed struct {
    page_offset: u12,
    table: u9,
    directory: u9,
    directory_pointer: u9,
    pml4: u9,
    sign_extension: u16,
    pub fn asU64(self: VirtualAddress) u64 {
        return @bitCast(self);
    }
    pub fn isHigherHalf(self: VirtualAddress) bool {
        return pml4 >= 256;
    }
};

pub const PageType = enum {
    four_kb,
    two_mb,
    one_gb,
};

/// A page of any size.
pub const Page = union(PageType) {
    four_kb: VirtualAddress,
    two_mb: VirtualAddress,
    one_gb: VirtualAddress,
    pub fn getAddress(self: Page) VirtualAddress {
        return switch (self) {
            .four_kb => |virt| virt,
            .two_mb => |virt| virt,
            .one_gb => |virt| virt,
        };
    }
    pub fn getType(self: Page) PageType {
        return switch (self) {
            .four_kb => |_| PageType.four_kb,
            .two_mb => |_| PageType.two_mb,
            .one_gb => |_| PageType.one_gb,
        };
    }
};

pub fn copyPml4(pml4: *const PML4, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator) u64 {
    const frame = frame_allocator.allocate_frame();
    var new_pml4: *PML4 = @ptrFromInt(hhdm_offset + frame);

    var i: u64 = 0;
    for (pml4) |pml4e| {
        if (pml4e.present) {
            const pdpt: *Pdpt = @ptrFromInt(hhdm_offset + pml4e.getPdpt());
            const new_pdpt = copyPdpt(pdpt, hhdm_offset, frame_allocator);
            // copy the old entry, and make it point to the new pdpt
            new_pml4[i] = pml4[i];
            new_pml4[i].setPdpt(new_pdpt);
        }
        i += 1;
    }
    return frame;
}

pub fn copyPdpt(pdpt: *const Pdpt, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator) u64 {
    const frame = frame_allocator.allocate_frame();
    const new_pdpt: *Pdpt = @ptrFromInt(hhdm_offset + frame);

    var i: u64 = 0;
    for (pdpt) |pdpte| {
        if (pdpte.huge_page.present) {
            if (pdpte.isHugePage()) {
                // copy huge page
                new_pdpt[i] = pdpte;
            } else {
                // copy page directory
                const pd: *Pd = @ptrFromInt(hhdm_offset + pdpte.page_directory.getPageDirectory());
                const new_pd = copyPd(pd, hhdm_offset, frame_allocator);
                new_pdpt[i] = pdpt[i];
                new_pdpt[i].page_directory.setPageDirectory(new_pd);
            }
        }
        i += 1;
    }
    return frame;
}

pub fn copyPd(pd: *const Pd, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator) u64 {
    const frame = frame_allocator.allocate_frame();
    const new_pd: *Pd = @ptrFromInt(hhdm_offset + frame);

    var i: u64 = 0;
    for (pd) |pde| {
        if (pde.huge_page.present) {
            if (pde.isHugePage()) {
                // copy huge page
                new_pd[i] = pde;
            } else {
                // copy page table
                const page_table: *Pt = @ptrFromInt(hhdm_offset + pde.page_table.getPageTable());
                const new_page_table = copyPageTable(page_table, hhdm_offset, frame_allocator);
                new_pd[i] = pd[i];
                new_pd[i].page_table.setPageTable(new_page_table);
            }
        }
        i += 1;
    }
    return frame;
}

pub fn copyPageTable(page_table: *const Pt, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator) u64 {
    const frame = frame_allocator.allocate_frame();
    const new_pt: *Pt = @ptrFromInt(hhdm_offset + frame);

    var i: u64 = 0;
    for (page_table) |pte| {
        if (pte.present) {
            new_pt[i] = pte;
        }
        i += 1;
    }
    return frame;
}

test "Paging Structure Sizes" {
    // Sizes of entries
    try std.testing.expectEqual(64, @bitSizeOf(PML4Entry));
    try std.testing.expectEqual(64, @bitSizeOf(PdptEntry_1GB));
    try std.testing.expectEqual(64, @bitSizeOf(PdptEntry_PD));
    try std.testing.expectEqual(64, @bitSizeOf(PdptEntry));
    try std.testing.expectEqual(64, @bitSizeOf(PdEntry_2MB));
    try std.testing.expectEqual(64, @bitSizeOf(PdEntry_PT));

    // Sizes of whole tables
    try std.testing.expectEqual(4096, @sizeOf(PML4));
    try std.testing.expectEqual(4096, @sizeOf(Pdpt));
    try std.testing.expectEqual(4096, @sizeOf(Pd));
    try std.testing.expectEqual(4096, @sizeOf(Pt));

    // Size of VirtualAddress
    try std.testing.expectEqual(64, @bitSizeOf(VirtualAddress));
}
