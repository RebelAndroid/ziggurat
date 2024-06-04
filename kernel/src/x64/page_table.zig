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
    A: bool,
    /// ignored
    _1: bool = 0,
    /// reserved
    _2: bool = 0,
    /// ignored
    _3: u3 = 0,
};
pub const PML4: type = PML4E[512];

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
};
