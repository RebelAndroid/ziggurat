const page_table = @import("page_table.zig");
const pmm = @import("../pmm.zig");
const log = @import("std").log.scoped(.registers);
const std = @import("std");

pub const PageFlags = struct {
    write: bool,
    execute: bool,
    user: bool,
};

pub const TranslationResult = struct {
    physical_address: u64,
    flags: PageFlags,
};

pub const CR3 = packed struct {
    _1: u3 = 0,
    pwt: u1,
    pcd: u1,
    _2: u7 = 0,
    pml4: u52,
    pub fn get_pml4(self: CR3) u64 {
        return @as(u64, self.pml4) << 12;
    }
    pub fn translate(self: CR3, addr: page_table.VirtualAddress, hhdm_offset: u64) ?TranslationResult {
        var res = TranslationResult{
            .flags = PageFlags{
                .write = true,
                .execute = true,
                .user = true,
            },
            .physical_address = 0,
        };

        const pml4: *page_table.PML4 = @ptrFromInt(self.get_pml4() + hhdm_offset);
        const pml4e = pml4[addr.pml4];
        if (!pml4e.present) {
            return null;
        }

        if (!pml4e.read_write) {
            res.flags.write = false;
        }
        if (pml4e.execute_disable) {
            res.flags.execute = false;
        }
        if (!pml4e.user) {
            res.flags.user = false;
        }

        log.debug("using page directory pointer table at: 0x{x}\n", .{pml4e.getPdpt()});
        const pdpt: *page_table.Pdpt = @ptrFromInt(pml4e.getPdpt() + hhdm_offset);
        const pdpte = pdpt[addr.directory_pointer];
        if (!pdpte.huge_page.present) {
            return null;
        }

        // the pdpte may not map a huge page, but this is fine because relevant bits are in the same position
        if (!pdpte.huge_page.read_write) {
            res.flags.write = false;
        }
        if (pdpte.huge_page.execute_disable) {
            res.flags.execute = false;
        }
        if (!pdpte.huge_page.user) {
            res.flags.user = false;
        }
        if (pdpte.isHugePage()) {
            // the offset in a 1gb page is composed of 3 fields from the VirtualAddress structure
            res.physical_address = (@as(u64, pdpte.huge_page.page) << 30) | (@as(u64, addr.directory) << 21) | (@as(u64, addr.table) << 12) | @as(u64, addr.page_offset);
            return res;
        } else {
            log.debug("using page directory at: 0x{x}\n", .{pdpte.page_directory.getPageDirectory()});
            const pd: *page_table.Pd = @ptrFromInt(pdpte.page_directory.getPageDirectory() + hhdm_offset);
            const pde = pd[addr.directory];

            if (!pde.huge_page.present) {
                return null;
            }

            // the pd may not map a huge page, but this is fine because relevant bits are in the same position
            if (!pde.huge_page.read_write) {
                res.flags.write = false;
            }
            if (pde.huge_page.execute_disable) {
                res.flags.execute = false;
            }
            if (!pde.huge_page.user) {
                res.flags.user = false;
            }

            if (pde.isHugePage()) {
                res.physical_address = (@as(u64, pde.huge_page.page) << 21) | (@as(u64, addr.table) << 12) | @as(u64, addr.page_offset);
                return res;
            } else {
                log.debug("using page table at: 0x{x}\n", .{pde.page_table.getPageTable()});
                const pt: *page_table.Pt = @ptrFromInt(pde.page_table.getPageTable() + hhdm_offset);
                const pte = pt[addr.table];
                if (!pte.present) {
                    return null;
                }

                if (!pte.read_write) {
                    res.flags.write = false;
                }
                if (pte.execute_disable) {
                    res.flags.execute = false;
                }
                if (!pte.user) {
                    res.flags.user = false;
                }
                res.physical_address = (@as(u64, pte.page) << 12) + addr.page_offset;
                return res;
            }
        }
    }

    pub fn check_flags(self: CR3, start: page_table.VirtualAddress, hhdm_offset: u64, length: u64, flags: PageFlags) bool {
        var start_page = start;
        start_page.page_offset = 0;
        // TODO: handle overflow
        var end_page: page_table.VirtualAddress = @bitCast(start.asU64() + length - 1);
        end_page.page_offset = 0;
        while (start_page != end_page) : (start_page = @bitCast(start_page.asU64() + 0x1000)) {
            if (self.translate(start_page, hhdm_offset)) |res| {
                if ((flags.write and !res.flags.write) || (flags.execute and !res.flags.execute) || (flags.user and !res.flags.user)) {
                    return false;
                }
            }
        }
        return true;
    }

    extern fn invalidatePage(address: u64) callconv(.C) void;
    comptime {
        asm (
            \\.globl invalidatePage
            \\.type invalidatePage @function
            \\invalidatePage:
            \\  invlpg (%rdi)
            \\  retq
        );
    }

    pub fn map(self: CR3, page: page_table.Page, physical_address: u64, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator, flags: PageFlags) page_table.MapError!void {
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
        const pml4: *volatile page_table.PML4 = @ptrFromInt(self.get_pml4() + hhdm_offset);
        var pml4e: *volatile page_table.PML4Entry = &pml4[addr.pml4];
        if (!pml4e.present) {
            // we need to create a new pml4e pointing to a new pdpt
            // allocate frame for new pdpt, this is zeroed by the allocator so it contains no valid entries
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return page_table.MapError.NoMemory;
            }
            pml4e.* = page_table.PML4Entry{
                .present = true,
                .read_write = true,
                .user_supervisor = true,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pml4e.setPdpt(frame);
        }

        std.debug.assert(pml4e.present);

        log.debug("following pdpt at 0x{x}\n", .{pml4e.getPdpt()});
        const pdpt: *volatile page_table.Pdpt = @ptrFromInt(pml4e.getPdpt() + hhdm_offset);
        var pdpte: *volatile page_table.PdptEntry = &pdpt[addr.directory_pointer];
        if (page_type == page_table.PageType.one_gb) {
            if (pdpte.huge_page.present) {
                return page_table.MapError.AlreadyPresent;
            }
            pdpte.huge_page = page_table.PdptEntry_1GB{
                .present = true,
                .read_write = flags.write,
                .user_supervisor = flags.user,
                .pwt = false,
                .pcd = false,
                .execute_disable = !flags.execute,
            };
            if (physical_address & 0x3FFFFFFF != 0) {
                return page_table.MapError.Unaligned;
            }
            pdpte.huge_page.setPage(physical_address);
            return;
        }
        if (!pdpte.page_directory.present) {
            // if we don't have a page directory to reference, we need to create a new one
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return page_table.MapError.NoMemory;
            }
            pdpte.page_directory = page_table.PdptEntry_PD{
                .present = true,
                .read_write = true,
                .user_supervisor = true,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pdpte.page_directory.setPageDirectory(frame);
        }
        if (pdpte.isHugePage()) {
            // we are trying to map a smaller page that is part of an already mapped huge page
            return page_table.MapError.AlreadyPresent;
        }

        std.debug.assert(pdpte.huge_page.present);

        log.debug("following pd at 0x{x}\n", .{pdpte.page_directory.getPageDirectory()});
        const pd: *volatile page_table.Pd = @ptrFromInt(pdpte.page_directory.getPageDirectory() + hhdm_offset);
        var pde: *volatile page_table.PdEntry = &pd[addr.directory];
        if (page_type == page_table.PageType.two_mb) {
            if (pde.huge_page.present) {
                return page_table.MapError.AlreadyPresent;
            }
            pde.huge_page = page_table.PdEntry_2MB{
                .present = true,
                .read_write = flags.write,
                .user_supervisor = flags.user,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = !flags.execute,
            };
            pde.huge_page.setPage(physical_address);
            return;
        }
        if (!pde.page_table.present) {
            // if we don't have a page table to reference, we need to create a new one
            const frame = frame_allocator.allocate_frame();
            if (frame == 0) {
                return page_table.MapError.NoMemory;
            }
            pde.page_table = page_table.PdEntry_PT{
                .present = true,
                .read_write = true,
                .user_supervisor = true,
                .pwt = false,
                .pcd = false,
                .accessed = false,
                .execute_disable = false,
            };
            pde.page_table.setPageTable(frame);
        }
        if (pde.isHugePage()) {
            // we are trying to map a smaller page that is part of an already mapped huge page
            return page_table.MapError.AlreadyPresent;
        }
        std.debug.assert(pde.huge_page.present);
        std.debug.assert(page_type == page_table.PageType.four_kb);

        log.debug("following pt at 0x{x}\n", .{pde.page_table.getPageTable()});
        const pt: *volatile page_table.Pt = @ptrFromInt(pde.page_table.getPageTable() + hhdm_offset);
        var pte: *volatile page_table.PtEntry = &pt[addr.table];
        if (pte.present) {
            return page_table.MapError.AlreadyPresent;
        }
        pte.* = page_table.PtEntry{
            .present = true,
            .read_write = flags.write,
            .user_supervisor = flags.user,
            .pwt = false,
            .pcd = false,
            .accessed = false,
            .execute_disable = !flags.execute,
        };
        pte.setPage(physical_address);
        invalidatePage(@bitCast(page.getAddress()));
        return;
    }

    pub fn setFlags(self: CR3, page: page_table.Page, hhdm_offset: u64, flags: PageFlags) bool {
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

        const pml4: *volatile page_table.PML4 = @ptrFromInt(self.get_pml4() + hhdm_offset);
        var pml4e: *volatile page_table.PML4Entry = &pml4[addr.pml4];
        if (!pml4e.present) {
            return false;
        }
        pml4e.user_supervisor = true;
        pml4e.read_write = true;

        log.debug("following pdpt at 0x{x}\n", .{pml4e.getPdpt()});
        const pdpt: *volatile page_table.Pdpt = @ptrFromInt(pml4e.getPdpt() + hhdm_offset);
        var pdpte: *volatile page_table.PdptEntry = &pdpt[addr.directory_pointer];
        if (page_type == page_table.PageType.one_gb) {
            if (!pdpte.huge_page.present) {
                return false;
            }
            pdpte.huge_page.read_write = flags.write;
            pdpte.huge_page.user_supervisor = flags.user;
            pdpte.huge_page.execute_disable = !flags.execute;
            invalidatePage(@bitCast(page.getAddress()));
            return true;
        }
        if (!pdpte.page_directory.present) {
            return false;
        }
        if (pdpte.isHugePage()) {
            // we are trying to change flags on one part of a huge page, fail
            return false;
        }

        pdpte.page_directory.user_supervisor = true;
        pdpte.page_directory.read_write = true;
        pdpte.page_directory.execute_disable = false;

        log.debug("following pd at 0x{x}\n", .{pdpte.page_directory.getPageDirectory()});
        const pd: *volatile page_table.Pd = @ptrFromInt(pdpte.page_directory.getPageDirectory() + hhdm_offset);
        var pde: *volatile page_table.PdEntry = &pd[addr.directory];
        if (!pde.page_table.present) {
            return false;
        }
        if (page_type == page_table.PageType.two_mb) {
            pde.huge_page.read_write = flags.write;
            pde.huge_page.user_supervisor = flags.user;
            pde.huge_page.execute_disable = !flags.execute;
            invalidatePage(@bitCast(page.getAddress()));
            return true;
        }
        if (pde.isHugePage()) {
            // we are trying to change flags on one part of a huge page, fail
            return false;
        }

        pde.page_table.read_write = true;
        pde.page_table.user_supervisor = true;
        pde.page_table.execute_disable = false;

        log.debug("following pt at 0x{x}\n", .{pde.page_table.getPageTable()});
        const pt: *volatile page_table.Pt = @ptrFromInt(pde.page_table.getPageTable() + hhdm_offset);
        var pte: *volatile page_table.PtEntry = &pt[addr.table];
        if (!pte.present) {
            return false;
        }
        pte.read_write = flags.write;
        pte.user_supervisor = flags.user;
        pte.execute_disable = !flags.execute;
        invalidatePage(@bitCast(page.getAddress()));
        return true;
    }

    pub fn setFlagsRange(self: CR3, start: u64, size: u64, hhdm_offset: u64, flags: PageFlags) void {
        std.debug.assert(start % 4096 == 0);
        const page_count = @divExact(size, 4096);
        var i: u64 = 0;
        while (i < page_count) : (i += 1) {
            _ = self.setFlags(page_table.Page{ .four_kb = @bitCast(@as(u64, start + 4096 * i)) }, hhdm_offset, flags);
        }
    }

    pub fn setPat(self: CR3, page: page_table.Page, hhdm_offset: u64, pat: u3) bool {
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

        const pml4: *volatile page_table.PML4 = @ptrFromInt(self.get_pml4() + hhdm_offset);
        var pml4e: *volatile page_table.PML4Entry = &pml4[addr.pml4];
        if (!pml4e.present) {
            return false;
        }

        log.debug("following pdpt at 0x{x}\n", .{pml4e.getPdpt()});
        const pdpt: *volatile page_table.Pdpt = @ptrFromInt(pml4e.getPdpt() + hhdm_offset);
        var pdpte: *volatile page_table.PdptEntry = &pdpt[addr.directory_pointer];
        if (page_type == page_table.PageType.one_gb) {
            if (!pdpte.huge_page.present) {
                return false;
            }
            pdpte.huge_page.pat = (pat & 0b100) != 0;
            pdpte.huge_page.pcd = (pat & 0b010) != 0;
            pdpte.huge_page.pwt = (pat & 0b001) != 0;
            invalidatePage(@bitCast(page.getAddress()));
            return true;
        }
        if (!pdpte.page_directory.present) {
            return false;
        }
        if (pdpte.isHugePage()) {
            // we are trying to change flags on one part of a huge page, fail
            return false;
        }

        log.debug("following pd at 0x{x}\n", .{pdpte.page_directory.getPageDirectory()});
        const pd: *volatile page_table.Pd = @ptrFromInt(pdpte.page_directory.getPageDirectory() + hhdm_offset);
        var pde: *volatile page_table.PdEntry = &pd[addr.directory];
        if (!pde.page_table.present) {
            return false;
        }
        if (page_type == page_table.PageType.two_mb) {
            pde.huge_page.pat = (pat & 0b100) != 0;
            pde.huge_page.pcd = (pat & 0b010) != 0;
            pde.huge_page.pwt = (pat & 0b001) != 0;
            invalidatePage(@bitCast(page.getAddress()));
            return true;
        }
        if (pde.isHugePage()) {
            // we are trying to change flags on one part of a huge page, fail
            return false;
        }

        log.debug("following pt at 0x{x}\n", .{pde.page_table.getPageTable()});
        const pt: *volatile page_table.Pt = @ptrFromInt(pde.page_table.getPageTable() + hhdm_offset);
        var pte: *volatile page_table.PtEntry = &pt[addr.table];
        if (!pte.present) {
            return false;
        }
        pte.pat = (pat & 0b100) != 0;
        pte.pcd = (pat & 0b010) != 0;
        pte.pwt = (pat & 0b001) != 0;
        invalidatePage(@bitCast(page.getAddress()));
        return true;
    }

    pub fn allocateRange(self: CR3, start: u64, size: u64, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator, flags: PageFlags) void {
        std.debug.assert(start % 4096 == 0);
        const page_count = @divExact(size, 4096);
        var i: u64 = 0;
        while (i < page_count) : (i += 1) {
            const frame = frame_allocator.allocate_frame();
            self.map(page_table.Page{ .four_kb = @bitCast(@as(u64, start + 4096 * i)) }, frame, hhdm_offset, frame_allocator, flags) catch unreachable;
        }
    }

    pub fn copy(self: CR3, hhdm_offset: u64, frame_allocator: *pmm.FrameAllocator) CR3 {
        const pml4: *const page_table.PML4 = @ptrFromInt(hhdm_offset + self.get_pml4());
        const new_pml4 = page_table.copyPml4(pml4, hhdm_offset, frame_allocator);
        return CR3{
            .pwt = 0,
            .pcd = 0,
            .pml4 = @intCast(new_pml4 >> 12),
        };
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

pub extern fn get_cr4() callconv(.C) CR4;
pub extern fn set_cr4(CR4) callconv(.C) void;
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
    carry: bool = false,
    _1: bool = true,
    parity: bool = false,
    _2: bool = false,
    auxiliary_carry: bool = false,
    _3: bool = false,
    zero: bool = false,
    sign: bool = false,
    trap: bool = false,
    /// Clear to ignore maskable hardware interrupts, does not affect exceptions or nonmaskable interrupts
    interrupt_enable: bool = false,
    direction_flag: bool = false,
    overflow_flag: bool = false,
    io_privilege_level: u2 = 0,
    nested_task: bool = false,
    _4: bool = false,
    resume_flag: bool = false,
    virtual_8086: bool = false,
    alignment_check_or_access_control: bool = false,
    virtual_interrupt: bool = false,
    virtual_interrupt_pending: bool = false,
    identification: bool = false,
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

pub extern fn getDs() callconv(.C) u16;
comptime {
    asm (
        \\.globl getDs
        \\.type getDs @function
        \\getDs:
        \\  movw %ds, %ax
        \\  retq
    );
}

pub extern fn getCs() callconv(.C) u16;
comptime {
    asm (
        \\.globl getCs
        \\.type getCs @function
        \\getCs:
        \\  movw %cs, %ax
        \\  retq
    );
}

test "register sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(CR4));
}
