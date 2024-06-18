const page_table = @import("page_table.zig");
const pmm = @import("../pmm.zig");
const log = @import("std").log.scoped(.registers);

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

        log.debug("using page directory pointer table at: 0x{X}\n", .{pml4e.get_pdpt()});
        const pdpt: *page_table.Pdpt = @ptrFromInt(pml4e.get_pdpt() + hhdm_offset);
        const pdpte = pdpt[addr.directory_pointer];
        if (!pdpte.huge_page.present) {
            return 2;
        }
        if (pdpte.is_huge_page()) {
            // the offset in a 1gb page is composed of 3 fields from the VirtualAddress structure
            return (@as(u64, pdpte.huge_page.page) << 30) | (@as(u64, addr.directory) << 21) | (@as(u64, addr.table) << 12) | @as(u64, addr.page_offset);
        } else {
            log.debug("using page directory at: 0x{X}\n", .{pdpte.page_directory.get_page_directory()});
            const pd: *page_table.Pd = @ptrFromInt(pdpte.page_directory.get_page_directory() + hhdm_offset);
            const pde = pd[addr.directory];
            if (!pde.huge_page.present) {
                return 3;
            }
            if (pde.is_huge_page()) {
                return (@as(u64, pde.huge_page.page) << 21) | (@as(u64, addr.table) << 12) | @as(u64, addr.page_offset);
            } else {
                log.debug("using page table at: 0x{X}\n", .{pde.page_table.get_page_table()});
                const pt: *page_table.Pt = @ptrFromInt(pde.page_table.get_page_table() + hhdm_offset);
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
        log.info("inside map\n", .{});
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
            // we need to create a new pml4e pointing to a new pdpt
            // allocate frame for new pdpt, this is zeroed by the allocator so it contains no valid entries
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return MapError.NoMemory;
            }
            log.debug("allocating new PDPT at frame: 0x{}", .{frame});
            pml4e = page_table.PML4Entry{
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
        log.debug("using page directory pointer table at: 0x{X}\n", .{pml4e.get_pdpt()});
        const pdpt: *page_table.Pdpt = @ptrFromInt(pml4e.get_pdpt() + hhdm_offset);
        var pdpte: *volatile page_table.PdptEntry = &pdpt[addr.directory_pointer];
        if (page_type == page_table.PageType.one_gb) {
            log.debug("mapping 1GB page", .{});
            if (pdpte.huge_page.present) {
                return MapError.AlreadyPresent;
            }
            pdpte.huge_page = page_table.PdptEntry_1GB{
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
            log.debug("allocating new PDPT at frame: 0x{}", .{frame});
            pdpte.page_directory = page_table.PdptEntry_PD{
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
        if (pdpte.is_huge_page()) {
            // we are trying to map a smaller page that is part of an already mapped huge page
            return MapError.AlreadyPresent;
        }
        // we now have a valid pdpte
        log.debug("using page directory at: 0x{X}\n", .{pdpte.page_directory.get_page_directory()});
        const pd: *page_table.Pd = @ptrFromInt(pdpte.page_directory.get_page_directory() + hhdm_offset);
        var pde: *volatile page_table.PdEntry = &pd[addr.directory];
        log.debug("pde: {}\n", .{pde.page_table});
        if (page_type == page_table.PageType.two_mb) {
            log.debug("mapping 2MB page", .{});
            if (pde.huge_page.present) {
                return MapError.AlreadyPresent;
            }
            pde.huge_page = page_table.PdEntry_2MB{
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
            log.debug("allocating new PT at frame: 0x{}", .{frame});
            pde.page_table = page_table.PdEntry_PT{
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
        if (pde.is_huge_page()) {
            // we are trying to map a smaller page that is part of an already mapped huge page
            return MapError.AlreadyPresent;
        }
        // we now have a valid pde, additionally, we are mapping a 4kb page
        log.debug("using page table at: 0x{X}\n", .{pde.page_table.get_page_table()});
        const pt: *page_table.Pt = @ptrFromInt(pde.page_table.get_page_table() + hhdm_offset);
        var pte: *volatile page_table.PtEntry = &pt[addr.table];
        if (pte.present) {
            return MapError.AlreadyPresent;
        }
        pte.* = page_table.PtEntry{
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

pub const Rflags = packed struct {
    carry: bool,
    _1: bool = true,
    parity: bool,
    _2: bool = false,
    auxillary_carry: bool,
    _3: bool = false,
    zero: bool,
    sign: bool,
    trap: bool,
    /// Clear to ignore maskable hardware interrupts, does not affect exceptions or nonmaskable interrupts
    interrupt_enable: bool,
    direction_flag: bool,
    overflow_flag: bool,
    io_privilege_level: u2,
    nested_task: bool,
    _4: bool = false,
    resume_flag: bool,
    virtual_8086: bool,
    alignment_check_or_access_control: bool,
    virtual_interrupt: bool,
    virtual_interrupt_pending: bool,
    identification: bool,
    _5: u10 = 0,
    _6: u32 = 0,
};

pub extern fn get_rflags() callconv(.C) Rflags;
comptime {
    asm (
        \\.globl get_rflags
        \\.type get_rflags @function
        \\get_rflags:
        \\  pushfq
        \\  popq %rax
        \\  retq
    );
}
