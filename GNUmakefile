# Nuke built-in rules and variables.
override MAKEFLAGS += -rR

override IMAGE_NAME := ziggurat

# Convenience macro to reliably declare user overridable variables.
define DEFAULT_VAR =
    ifeq ($(origin $1),default)
        override $(1) := $(2)
    endif
    ifeq ($(origin $1),undefined)
        override $(1) := $(2)
    endif
endef

override DEFAULT_KZIGFLAGS := -Doptimize=ReleaseSafe
$(eval $(call DEFAULT_VAR,KZIGFLAGS,$(DEFAULT_KZIGFLAGS)))

QEMU_FLAGS := -serial stdio -no-shutdown -no-reboot
.PHONY: all
all: $(IMAGE_NAME).iso

.PHONY: all-hdd
all-hdd: $(IMAGE_NAME).hdd

.PHONY: run
run: $(IMAGE_NAME).iso
	qemu-system-x86_64 -M q35 -m 2G -cdrom $(IMAGE_NAME).iso -boot d $(QEMU_FLAGS)

.PHONY: run-uefi
run-uefi: ovmf $(IMAGE_NAME).iso
	qemu-system-x86_64 -M q35 -m 128M -bios ovmf/OVMF.fd -cdrom $(IMAGE_NAME).iso -boot d $(QEMU_FLAGS)

.PHONY: run-gdb-uefi
run-gdb-uefi: ovmf $(IMAGE_NAME).iso
	qemu-system-x86_64 -M q35 -m 128M -bios ovmf/OVMF.fd -cdrom $(IMAGE_NAME).iso -boot d $(QEMU_FLAGS) -s -S

.PHONY: run-kvm-uefi
run-kvm-uefi: ovmf $(IMAGE_NAME).iso
	qemu-system-x86_64 -M q35 -m 128M -bios ovmf/OVMF.fd -cdrom $(IMAGE_NAME).iso -boot d $(QEMU_FLAGS) -enable-kvm	-cpu host -smp 2
	
.PHONY: run-hdd
run-hdd: $(IMAGE_NAME).hdd
	qemu-system-x86_64 -M q35 -m 2G -hda $(IMAGE_NAME).hdd $(QEMU_FLAGS)

.PHONY: run-hdd-uefi
run-hdd-uefi: ovmf $(IMAGE_NAME).hdd
	qemu-system-x86_64 -M q35 -m 2G -bios ovmf/OVMF.fd -hda $(IMAGE_NAME).hdd $(QEMU_FLAGS)

.PHONY: zig-test
zig-test:
	zig test kernel/src/x64/cpuid.zig
	zig test kernel/src/x64/apic.zig
	zig test kernel/src/x64/gdt.zig
	zig test kernel/src/process.zig
	zig test kernel/src/x64/registers.zig
	zig test kernel/src/x64/xsave.zig
	zig test kernel/src/x64/idt.zig
	zig test kernel/src/x64/tss.zig
	zig test kernel/src/x64/page_table.zig
	zig test kernel/src/acpi.zig
	zig test kernel/src/x64/msr.zig
	zig test kernel/src/elf.zig

ovmf:
	mkdir -p ovmf
	cd ovmf && curl -Lo OVMF.fd https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF.fd

limine/limine:
	rm -rf limine
	git clone https://github.com/limine-bootloader/limine.git --branch=v7.x-binary --depth=1
	$(MAKE) -C limine

.PHONY: kernel
kernel: init
	cd kernel && zig build $(KZIGFLAGS)

.PHONY: init
init:
	cd init && zig build -Doptimize=ReleaseSafe
	cp init/zig-out/bin/init kernel/src

$(IMAGE_NAME).iso: limine/limine kernel
	rm -rf iso_root
	mkdir -p iso_root/boot
	cp -v kernel/zig-out/bin/kernel iso_root/boot/
	mkdir -p iso_root/boot/limine
	cp -v limine.cfg limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin iso_root/boot/limine/
	mkdir -p iso_root/EFI/BOOT
	cp -v limine/BOOTX64.EFI iso_root/EFI/BOOT/
	cp -v limine/BOOTIA32.EFI iso_root/EFI/BOOT/
	xorriso -as mkisofs -b boot/limine/limine-bios-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_root -o $(IMAGE_NAME).iso
	./limine/limine bios-install $(IMAGE_NAME).iso
	rm -rf iso_root

$(IMAGE_NAME).hdd: limine/limine kernel
	rm -f $(IMAGE_NAME).hdd
	dd if=/dev/zero bs=1M count=0 seek=64 of=$(IMAGE_NAME).hdd
	sgdisk $(IMAGE_NAME).hdd -n 1:2048 -t 1:ef00
	./limine/limine bios-install $(IMAGE_NAME).hdd
	mformat -i $(IMAGE_NAME).hdd@@1M
	mmd -i $(IMAGE_NAME).hdd@@1M ::/EFI ::/EFI/BOOT ::/boot ::/boot/limine
	mcopy -i $(IMAGE_NAME).hdd@@1M kernel/zig-out/bin/kernel ::/boot
	mcopy -i $(IMAGE_NAME).hdd@@1M limine.cfg limine/limine-bios.sys ::/boot/limine
	mcopy -i $(IMAGE_NAME).hdd@@1M limine/BOOTX64.EFI ::/EFI/BOOT
	mcopy -i $(IMAGE_NAME).hdd@@1M limine/BOOTIA32.EFI ::/EFI/BOOT

.PHONY: clean
clean:
	rm -rf iso_root $(IMAGE_NAME).iso $(IMAGE_NAME).hdd
	rm -rf kernel/zig-cache kernel/.zig-cache kernel/zig-out
	rm -rf init/zig-cache init/.zig-cache init/zig-out

.PHONY: distclean
distclean: clean
	rm -rf limine ovmf
