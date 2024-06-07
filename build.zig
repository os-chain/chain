const std = @import("std");

fn getTarget(b: *std.Build, arch: std.Target.Cpu.Arch) std.Build.ResolvedTarget {
    const query: std.Target.Query = .{
        .cpu_arch = arch,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = switch (arch) {
            .x86_64 => std.Target.x86.featureSet(&.{.soft_float}),
            else => @panic("unsupported architecture"),
        },
        .cpu_features_sub = switch (arch) {
            .x86_64 => std.Target.x86.featureSet(&.{ .mmx, .sse, .sse2, .avx, .avx2 }),
            else => @panic("unsupported architecture"),
        },
    };

    return b.resolveTargetQuery(query);
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const kernel_target = getTarget(b, .x86_64);

    // This is a kernel, it makes no sense to have install/uninstall steps
    b.top_level_steps.clearRetainingCapacity();

    const kernel = b.addExecutable(.{
        .name = "chain",
        .target = kernel_target,
        .optimize = optimize,
        .root_source_file = b.path("kernel/src/main.zig"),
    });
    kernel.setLinkerScript(b.path("kernel/link-x86_64.ld"));

    const kernel_step = b.step("kernel", "Build the kernel executable");
    b.default_step = kernel_step;
    kernel_step.dependOn(&b.addInstallArtifact(kernel, .{}).step);

    const stub_iso_tree = b.addWriteFiles();
    _ = stub_iso_tree.addCopyFile(kernel.getEmittedBin(), "kernel");
    _ = stub_iso_tree.addCopyFile(b.path("limine.cfg"), "limine.cfg");
    _ = stub_iso_tree.addCopyFile(b.dependency("limine", .{}).path("limine-uefi-cd.bin"), "limine-uefi-cd.bin");

    const stub_iso_xorriso = b.addSystemCommand(&.{"xorriso"});
    stub_iso_xorriso.addArgs(&.{ "-as", "mkisofs" });
    stub_iso_xorriso.addArgs(&.{ "--efi-boot", "limine-uefi-cd.bin" });
    stub_iso_xorriso.addArg("-efi-boot-part");
    stub_iso_xorriso.addArg("--efi-boot-image");
    stub_iso_xorriso.addArg("--protective-msdos-label");
    stub_iso_xorriso.addDirectoryArg(stub_iso_tree.getDirectory());
    stub_iso_xorriso.addArg("-o");
    const stub_iso = stub_iso_xorriso.addOutputFileArg("chain_stub.iso");

    const stub_iso_step = b.step("stub_iso", "Create a stub ISO, used to install chain");
    stub_iso_step.dependOn(&b.addInstallFile(stub_iso, "chain_stub.iso").step);

    const qemu = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemu.addArg("-bios");
    qemu.addFileArg(b.dependency("ovmf", .{}).path("RELEASEX64_OVMF.fd"));
    qemu.addArg("-cdrom");
    qemu.addFileArg(stub_iso);
    qemu.addArgs(&.{ "-debugcon", "stdio" });

    const qemu_step = b.step("qemu", "Run the stub ISO in QEMU");
    qemu_step.dependOn(&qemu.step);
}
