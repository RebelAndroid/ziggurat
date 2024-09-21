const std = @import("std");
const build_font = @import("build-font.zig");

pub fn build(b: *std.Build) !void {
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
    const lazy_path = std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = "src/main.zig" } };
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = lazy_path,
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    // Add ACPICA.
    kernel.defineCMacro("ACPI_DEBUGGER", "");
    const components = [_][]const u8{ "dispatcher", "events", "executer", "hardware", "parser", "namespace", "utilities", "tables", "resources", "debugger" };
    inline for (components) |component| {
        const c_src_dir = "../acpica-unix-20240321/source/components/" ++ component;
        const dir = try std.fs.cwd().openDir(c_src_dir, .{ .iterate = true });
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".c")) {
                kernel.addCSourceFile(.{ .file = b.path(b.pathJoin(&[_][]const u8{ c_src_dir, entry.name })) });
            }
        }
    }

    kernel.addIncludePath(b.path("../acpica-unix-20240321/source/include"));

    kernel.root_module.addImport("limine", limine.module("limine"));
    kernel.setLinkerScriptPath(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = "linker.ld" } });

    kernel.pie = true;

    // Disable LTO. This prevents issues with limine requests
    kernel.want_lto = false;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const font_file = std.fs.cwd().openFile("../cozette.bdf", .{}) catch std.debug.panic("unable to open font file", .{});
    defer font_file.close();

    const packed_font = build_font.build_font(font_file, allocator) catch std.debug.panic("unable to build font", .{});
    const packed_font_file = std.fs.cwd().createFile("src/cozette-packed.bin", .{}) catch unreachable;
    defer packed_font_file.close();

    packed_font_file.writeAll(packed_font) catch unreachable;

    b.installArtifact(kernel);
}
