const std = @import("std");

const ChainArch = enum {
    x86_64,
    aarch64,
};

fn getTarget(b: *std.Build, arch: ChainArch) std.Build.ResolvedTarget {
    const query: std.Target.Query = .{
        .cpu_arch = switch (arch) {
            inline else => |x| @field(std.Target.Cpu.Arch, @tagName(x)),
        },
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = switch (arch) {
            .x86_64 => std.Target.x86.featureSet(&.{.soft_float}),
            .aarch64 => std.Target.aarch64.featureSet(&.{}),
        },
        .cpu_features_sub = switch (arch) {
            .x86_64 => std.Target.x86.featureSet(&.{ .mmx, .sse, .sse2, .avx, .avx2 }),
            .aarch64 => std.Target.aarch64.featureSet(&.{}),
        },
    };

    return b.resolveTargetQuery(query);
}

fn addKernel(b: *std.Build, options: struct { arch: ChainArch, optimize: std.builtin.OptimizeMode }) *std.Build.Step.Compile {
    const target = getTarget(b, options.arch);

    const kernel = b.addExecutable(.{
        .name = "chain",
        .target = target,
        .optimize = options.optimize,
        .code_model = switch (options.arch) {
            .x86_64 => .kernel,
            .aarch64 => .default,
        },
        .root_source_file = b.path("kernel/src/main.zig"),
    });
    kernel.setLinkerScript(b.path(b.fmt("kernel/link-{s}.ld", .{@tagName(options.arch)})));
    return kernel;
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const arch = b.option(ChainArch, "arch", "The target architecture") orelse .x86_64;

    // This is a kernel, it makes no sense to have install/uninstall steps
    b.top_level_steps.clearRetainingCapacity();

    const kernel = addKernel(b, .{
        .arch = arch,
        .optimize = optimize,
    });

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

    const qemu = b.addSystemCommand(&.{b.fmt("qemu-system-{s}", .{@tagName(arch)})});

    switch (arch) {
        .x86_64 => {
            qemu.addArg("-bios");
            qemu.addFileArg(b.dependency("ovmf", .{}).path("RELEASEX64_OVMF.fd"));
            qemu.addArg("-cdrom");
            qemu.addFileArg(stub_iso);
        },
        .aarch64 => {
            qemu.addArgs(&.{ "-M", "virt" });
            qemu.addArgs(&.{ "-cpu", "cortex-a72" });
            qemu.addArgs(&.{ "-device", "ramfb" });
            qemu.addArgs(&.{ "-device", "qemu-xhci" });
            qemu.addArgs(&.{ "-device", "usb-kbd" });
            qemu.addArg("-bios");
            qemu.addFileArg(b.dependency("ovmf", .{}).path("RELEASEAARCH64_QEMU_EFI.fd"));
            qemu.addArg("-cdrom");
            qemu.addFileArg(stub_iso);
            qemu.addArgs(&.{ "-boot", "d" });
        },
    }

    qemu.addArgs(&.{ "-serial", "stdio" });
    qemu.addArgs(&.{ "-m", "2G" });

    const qemu_step = b.step("qemu", "Run the stub ISO in QEMU");
    qemu_step.dependOn(&qemu.step);
}
