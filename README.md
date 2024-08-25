# Ziggurat
Ziggurat is a work-in-progress kernel for x86-64 machines. Currently, it can load a static elf file and run it in userspace.

## Building
Ziggurat uses Nix to manage the build environment. Enter the nix environment with `nix develop` or use enable direnv for the Ziggurat directory.
Ziggurat uses make to build, use `make` with the appropriate target.


### Build targets
- `ziggurat.iso` This target builds the ziggurat ISO image. This .iso can be used to boot on real hardware with `dd if=ziggurat.iso of=/dev/my_flash_drive_here`.
- `run-kvm-uefi` This target creates a qemu virtual machine using kvm to run Ziggurat.
- `run-gdb-uefi` This target creates a qemu virtual machine to run Ziggurat. The virtual machine waits for a connection from gdb before starting.
- `run-uefi` This target creates a qemu virtual machine to run Ziggurat.