const page_table = @import("page_table.zig");
const pmm = @import("../pmm.zig");
const serial_writer = @import("../main.zig").serial_writer;

pub const CR3 = packed struct {
    _1: u3,
    pwt: u1,
    pcd: u1,
    _2: u7,
    pml4: u52,
    pub fn get_pml4(self: CR3) u64 {
        return @as(u64, self.pml4) << 12;
    }
    pub fn translate(self: CR3, addr: page_table.VirtualAddress, hhdm_offset: u64) u64 {
        const pml4: *page_table.PML4 = @ptrFromInt(self.get_pml4() + hhdm_offset);
        const pml4e = pml4[addr.pml4];
        if (!pml4e.present) {
            return 1;
        }

        const pdpt: *page_table.PDPT = @ptrFromInt(pml4e.get_pdpt() + hhdm_offset);
        const pdpte = pdpt[addr.directory_pointer];
        if (!pdpte.huge_page.present) {
            return 2;
        }
        if (pdpte.is_huge_page()) {
            // the offset in a 1gb page is composed of 3 fields from the VirtualAddress structure
            return (@as(u64, pdpte.huge_page.page) << 30) | (@as(u64, addr.directory) << 21) | (@as(u64, addr.table) << 12) | @as(u64, addr.page_offset);
        } else {
            const pd: *page_table.PD = @ptrFromInt(pdpte.page_directory.get_page_directory() + hhdm_offset);
            const pde = pd[addr.directory];
            if (!pde.huge_page.present) {
                return 3;
            }
            if (pde.is_huge_page()) {
                return (@as(u64, pde.huge_page.page) << 21) | (@as(u64, addr.table) << 12) | @as(u64, addr.page_offset);
            } else {
                const pt: *page_table.PT = @ptrFromInt(pde.page_table.get_page_table() + hhdm_offset);
                const pte = pt[addr.table];
                if (!pte.present) {
                    return 4;
                }
                return (@as(u64, pte.page) << 12) + addr.page_offset;
            }
        }
    }

    const MapError = error{
        /// Indicates that a virtual address has already been mapped
        AlreadyPresent,
        Unaligned,
        NoMemory,
    };

    pub fn map(self: CR3, page: page_table.Page, physical_address: u64, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator) MapError!void {
        try serial_writer.print("inside map\n", .{});
        const addr = switch (page) {
            .four_kb => |virt| virt,
            .two_mb => |virt| virt,
            .one_gb => |virt| virt,
        };
        const page_type = switch (page) {
            .four_kb => page_table.PageType.four_kb,
            .two_mb => page_table.PageType.two_mb,
            .one_gb => page_table.PageType.one_gb,
        };
        const pml4: *page_table.PML4 = @ptrFromInt(self.get_pml4() + hhdm_offset);
        var pml4e = pml4[addr.pml4];
        if (!pml4e.present) {
            // we need to create a new pml4e pointing to a new pdpte
            // allocate frame for new pdpte, this is zeroed by the allocator so it contains no valid entries
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return MapError.NoMemory;
            }
            pml4e = page_table.PML4E{
                .present = true,
                .read_write = true,
                .user_supervisor = false,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pml4e.set_pdpt(frame);
        }
        // we now have a valid pml4e
        const pdpt: *page_table.PDPT = @ptrFromInt(pml4e.get_pdpt() + hhdm_offset);
        var pdpte: *volatile page_table.PDPTE = &pdpt[addr.directory_pointer];
        if (page_type == page_table.PageType.one_gb) {
            if (pdpte.huge_page.present) {
                return MapError.AlreadyPresent;
            }
            pdpte.huge_page = page_table.PDPTE_1GB{
                .present = true,
                .read_write = true,
                .user_supervisor = false,
                .pwt = false,
                .pcd = false,
                .execute_disable = false,
            };
            if (physical_address & 0x3FFFFFFF != 0) {
                return MapError.Unaligned;
            }
            pdpte.huge_page.set_page(physical_address);
            return;
        }
        if (!pdpte.page_directory.present) {
            // if we don't have a page directory to reference, we need to create a new one
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return MapError.NoMemory;
            }
            pdpte.page_directory = page_table.PDPTE_PD{
                .present = true,
                .read_write = true,
                .user_supervisor = false,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pdpte.page_directory.set_page_directory(frame);
        }
        // we now have a valid pdpte
        const pd: *page_table.PD = @ptrFromInt(pdpte.page_directory.get_page_directory() + hhdm_offset);
        var pde: *volatile page_table.PDE = &pd[addr.directory];
        if (page_type == page_table.PageType.two_mb) {
            if (pde.huge_page.present) {
                return MapError.AlreadyPresent;
            }
            pde.huge_page = page_table.PDE_2MB{
                .present = true,
                .read_write = true,
                .user_supervisor = false,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pde.huge_page.set_page(physical_address);
            return;
        }
        if (!pde.page_table.present) {
            // if we don't have a page table to reference, we need to create a new one
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return MapError.NoMemory;
            }
            pde.page_table = page_table.PDE_PT{
                .present = true,
                .read_write = true,
                .user_supervisor = false,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pde.page_table.set_page_table(frame);
        }
        // we now have a valid pde, additionally, we are mapping a 4kb page
        const pt: *page_table.PT = @ptrFromInt(pde.page_table.get_page_table() + hhdm_offset);
        var pte: *volatile page_table.PTE = &pt[addr.table];
        if (pte.present) {
            return MapError.AlreadyPresent;
        }
        pte.* = page_table.PTE{
            .present = true,
            .read_write = true,
            .user_supervisor = false,
            .pwt = false,
            .pcd = false,
            .accessed = false,
            .execute_disable = false,
        };
        pte.set_page(physical_address);
        return;
    }
};

pub extern fn get_cr3() callconv(.C) CR3;
pub extern fn set_cr3(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl get_cr3
        \\.type get_cr3 @function
        \\get_cr3:
        \\  movq %cr3, %rax
        \\  retq
        \\.globl set_cr3
        \\.type set_cr3 @function
        \\set_cr3:
        \\  movq %rdi, %cr3
        \\  retq
    );
}

/// packed struct representing CR4 values
/// more info at Intel Software Developer's Manual Vol. 3A 2-17
pub const CR4 = packed struct {
    /// Virtual-8086 Mode Extensions: enables interrupt and exceptions handling extensions in virtual-8086 mode
    vme: bool,
    /// Protected-Mode Virtual Interrupts: enables virtual interrupt flag in protected mode
    pvi: bool,
    /// Time Stamp Disable: restricts execution of RDTSC instruction to ring 0 (also applies to RDTSCP if available)
    tsd: bool,
    /// Debug Extensions: ?
    de: bool,
    /// Page Size Extensions: enables 4MB pages with 32 bit paging
    pse: bool,
    /// Physical Address Extension: Allows paging for physical addresses larger than 32 bits, must be set for long mode paging (IA-32e)
    pae: bool,
    /// Machine-Check Enable: enables the machine-check exception
    mce: bool,
    /// Page Global Enable: enables global pages
    pge: bool,
    /// Performance-Monitoring Counter Enable: allows RDPMC instruction to execute at any privilege level (only in ring 0 if clear)
    pce: bool,
    /// Operating System Support For FXSAVE and FXRSTOR instructions: enables FXSAVE and FXSTOR,
    /// allows the processor to execute most SSE/SSE2/SSE3/SSSE3/SSE4 (others always available)
    osfxsr: bool,
    /// Operating System Support for Unmasked SIMD Floating-Point Exceptions: indicates support for handling unmasked SIMD floating-point exceptions
    osxmmexcpt: bool,
    /// User-Mode Instruction Prevention: prevents rings > 0 from executing SGDT, SIDT, SMSW, and STR
    umip: bool,
    /// 57-bit linear addresses: enables 5-level paging (57 bit virtual addresses)
    la57: bool,
    /// VMX-Enable: enables VMX
    vmxe: bool,
    /// SMX-Enable: enables SMX
    smxe: bool,
    _2: bool,
    /// FSGSBASE-Enable: enables RDFSBASE, RDGSBASE, WRFSBASE, and WRGSBASE
    fsgsbase: bool,
    /// PCID-Enable: enables process-context identifiers
    pcide: bool,
    /// Enables XSAVE, XRSTOR, XGETBV, and XSETBV
    osxsave: bool,
    /// Key-Locker-Enable: enables LOADIWKEY
    kl: bool,
    /// SMEP-Enable: enables supervisor-mode execution prevention
    smep: bool,
    /// SMAP-Enable: enables supervisor-mode access prevention
    smap: bool,
    /// Enable protection keys for user-mode pages: ?
    pke: bool,
    /// Control-Flow Enforcement Technology: enables CET when set
    cet: bool,
    /// Enable protection keys for supervisor-mode pages
    pks: bool,
    /// User Interrupts Enable: enables user interrupts
    uintr: bool,
    _4: u38,
};

pub extern fn get_cr4() callconv(.C) u64;
pub extern fn set_cr4(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl get_cr4
        \\.type get_cr4 @function
        \\get_cr4:
        \\  movq %cr4, %rax
        \\  retq
        \\.globl set_cr4
        \\.type set_cr4 @function
        \\set_cr4:
        \\  movq %rdi, %cr4
        \\  retq
    );
}
