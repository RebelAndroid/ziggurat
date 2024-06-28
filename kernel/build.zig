const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define a freestanding x86_64 cross-compilation target.
    var target: std.zig.CrossTarget = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    // Build the kernel itself.
    const optimize = b.standardOptimizeOption(.{});
    const limine = b.dependency("limine", .{});
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    kernel.root_module.addImport("limine", limine.module("limine"));
    kernel.setLinkerScriptPath(.{ .path = "linker.ld" });

    kernel.pie = true;

    // Disable LTO. This prevents issues with limine requests
    kernel.want_lto = false;

    kernel.addIncludePath(.{ .path = "acpica-unix-20240321/source/include" });

    const acpica = b.addStaticLibrary(.{
        .name = "acpica",
        .target = b.resolveTargetQuery(target),
        .code_model = .kernel,
        .pic = true,
        .optimize = optimize,
    });
    // acpica.defineCMacro("ACPI_USE_SYSTEM_INTTYPES", null);
    acpica.addCSourceFiles(.{
        .files = &[_][]const u8{
            "../acpica-unix-20240321/source/components/hardware/hwacpi.c",
            "../acpica-unix-20240321/source/components/hardware/hwesleep.c",
            "../acpica-unix-20240321/source/components/hardware/hwgpe.c",
            "../acpica-unix-20240321/source/components/hardware/hwpci.c",
            "../acpica-unix-20240321/source/components/hardware/hwregs.c",
            "../acpica-unix-20240321/source/components/hardware/hwsleep.c",
            "../acpica-unix-20240321/source/components/hardware/hwtimer.c",
            "../acpica-unix-20240321/source/components/hardware/hwvalid.c",
            "../acpica-unix-20240321/source/components/hardware/hwxface.c",
            "../acpica-unix-20240321/source/components/hardware/hwxfsleep.c",

            "../acpica-unix-20240321/source/components/utilities/utxfinit.c",
        },
    });
    acpica.addIncludePath(.{ .path = "../acpica-unix-20240321/source/include" });

    kernel.linkLibrary(acpica);

    b.installArtifact(kernel);
}
