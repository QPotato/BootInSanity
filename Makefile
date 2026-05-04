SHELL       := /bin/bash
IMAGE_NAME  := bootinsanity-builder
ROOT        := $(shell pwd)
BUILD_DIR   := $(ROOT)/build
OUTPUT      ?= $(BUILD_DIR)/bootinsanity-installer.iso

# Required at invocation time:
DEBIAN_ISO  ?=
XSANITY_DIR ?=
VERSION     ?= dev
GPU         ?= nouveau
NO_CACHE    ?= 0

# Note: XSanity is staged under work/inputs/xsanity/ at recipe time to avoid
# Make's $(abspath) mangling paths that contain spaces (e.g. "XSanity 0.96.0/").
INPUTS_DIR := $(ROOT)/work/inputs

# Unset snap-injected library paths so system QEMU uses system GTK/GDK libs.
unexport SNAP_LIBRARY_PATH GTK_PATH GTK_EXE_PREFIX GDK_PIXBUF_MODULE_FILE \
         GDK_PIXBUF_MODULEDIR GIO_MODULE_DIR GTK_IM_MODULE_FILE LOCPATH

DOCKER_RUN = docker run --rm --privileged \
             -v "$(ROOT)":/work \
             $(if $(DEBIAN_ISO),-v "$(realpath $(DEBIAN_ISO))":/inputs/debian.iso:ro) \
             $(if $(XSANITY_DIR),-v "$(INPUTS_DIR)/xsanity":/inputs/xsanity:ro)

TARGET_DISK := $(BUILD_DIR)/qemu-target.qcow2
TARGET_SIZE ?= 16G

.PHONY: help builder iso qemu qemu-install qemu-installed qemu-update target-disk shell clean distclean

help:
	@echo "BootInSanity build targets"
	@echo ""
	@echo "  make builder                     build Docker builder image"
	@echo "  make iso DEBIAN_ISO=<path>       build BootInSanity installer ISO (Debian 13 DVD-1)"
	@echo "      [XSANITY_DIR=<path>]         (Phase 1+; not required in Phase 0)"
	@echo "      [OUTPUT=<path>]              default: build/bootinsanity-installer.iso"
	@echo "      [VERSION=<string>]           default: dev"
	@echo "      [GPU=nouveau|340|390|470]    default: nouveau (rebuild per cabinet GPU)"
	@echo "  make qemu                        boot \$$OUTPUT in qemu (live mode)"
	@echo "  make qemu-install                boot ISO + virtio target disk for installer"
	@echo "  make qemu-installed              boot from installed target disk (no ISO)"
	@echo "  make qemu-update                 boot ISO in update mode (preserves target disk p3)"
	@echo "  make target-disk                 create empty qcow2 target disk"
	@echo "  make shell                       drop into builder container"
	@echo "  make clean                       remove work + build dirs"
	@echo "  make distclean                   also remove builder Docker image"

builder:
	docker build --pull=never -t $(IMAGE_NAME) . 2>/dev/null \
	    || docker build -t $(IMAGE_NAME) .

iso: builder
	@if [ -z "$(DEBIAN_ISO)" ]; then \
	    echo "ERROR: DEBIAN_ISO=<path> required"; exit 1; fi
	@if [ ! -f "$(DEBIAN_ISO)" ]; then \
	    echo "ERROR: $(DEBIAN_ISO) not found"; exit 1; fi
	@mkdir -p $(BUILD_DIR) $(INPUTS_DIR)
	@if [ -n "$(XSANITY_DIR)" ]; then \
	    if [ ! -d "$(XSANITY_DIR)" ]; then \
	        echo "ERROR: XSANITY_DIR not found: $(XSANITY_DIR)"; exit 1; fi; \
	    echo "==> Staging XSanity dir to work/inputs/xsanity/"; \
	    rm -rf "$(INPUTS_DIR)/xsanity"; \
	    cp -al "$(XSANITY_DIR)" "$(INPUTS_DIR)/xsanity" 2>/dev/null \
	        || cp -a "$(XSANITY_DIR)" "$(INPUTS_DIR)/xsanity"; \
	fi
	$(DOCKER_RUN) $(IMAGE_NAME) /work/build.sh \
	    --debian-iso /inputs/debian.iso \
	    $(if $(XSANITY_DIR),--xsanity-dir /inputs/xsanity) \
	    --output /work/build/$(notdir $(OUTPUT)) \
	    --version $(VERSION) \
	    --gpu $(GPU) \
	    $(if $(filter 1,$(NO_CACHE)),--no-cache)

qemu:
	@if [ ! -f "$(OUTPUT)" ]; then \
	    echo "ERROR: $(OUTPUT) not found. Run 'make iso' first."; exit 1; fi
	qemu-system-x86_64 -enable-kvm -m 4G -smp 2 \
	    -cdrom $(OUTPUT) \
	    -boot d \
	    -device virtio-vga,xres=1280,yres=720 \
	    -display gtk,zoom-to-fit=on \
	    -audiodev pa,id=snd0 \
	    -device intel-hda -device hda-output,audiodev=snd0 \
	    -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp::2222-:22 \
	    -usb -device usb-kbd -device usb-tablet \

target-disk:
	@mkdir -p $(BUILD_DIR)
	@if [ ! -f "$(TARGET_DISK)" ]; then \
	    qemu-img create -f qcow2 "$(TARGET_DISK)" $(TARGET_SIZE); \
	fi

# Boot ISO with a virtio target disk attached. Pick "Clean Install" or
# "Update" from the boot menu. Installer wipes / re-flashes $(TARGET_DISK).
qemu-install: target-disk
	@if [ ! -f "$(OUTPUT)" ]; then \
	    echo "ERROR: $(OUTPUT) not found. Run 'make iso' first."; exit 1; fi
	qemu-system-x86_64 -enable-kvm -m 4G -smp 2 \
	    -cdrom $(OUTPUT) \
	    -drive file=$(TARGET_DISK),if=virtio,format=qcow2 \
	    -boot d \
	    -device virtio-vga,xres=1280,yres=720 \
	    -display gtk,zoom-to-fit=on \
	    -audiodev pa,id=snd0 \
	    -device intel-hda -device hda-output,audiodev=snd0 \
	    -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp::2222-:22 \
	    -usb -device usb-kbd -device usb-tablet \

# Boot from the installed disk (no ISO). Run after qemu-install completes.
qemu-installed:
	@if [ ! -f "$(TARGET_DISK)" ]; then \
	    echo "ERROR: $(TARGET_DISK) not found. Run 'make qemu-install' first."; exit 1; fi
	qemu-system-x86_64 -enable-kvm -m 4G -smp 2 \
	    -drive file=$(TARGET_DISK),if=virtio,format=qcow2 \
	    -boot c \
	    -device virtio-vga,xres=1280,yres=720 \
	    -display gtk,zoom-to-fit=on \
	    -audiodev pa,id=snd0 \
	    -device intel-hda -device hda-output,audiodev=snd0 \
	    -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp::2222-:22 \
	    -usb -device usb-kbd -device usb-tablet \

shell: builder
	docker run --rm -it --privileged \
	    -v $(ROOT):/work \
	    $(IMAGE_NAME) bash

clean:
	rm -rf $(ROOT)/work $(BUILD_DIR)

distclean: clean
	-docker rmi $(IMAGE_NAME)

qemu-update:
	@if [ ! -f "$(OUTPUT)" ]; then \
	    echo "ERROR: $(OUTPUT) not found. Run 'make iso' first."; exit 1; fi
	@if [ ! -f "$(TARGET_DISK)" ]; then \
	    echo "ERROR: $(TARGET_DISK) not found. Run 'make qemu-install' first."; exit 1; fi
	xorriso -osirrox on -indev "$(OUTPUT)" \
	    -extract /live/vmlinuz /tmp/bis-vmlinuz \
	    -extract /live/initrd  /tmp/bis-initrd 2>/dev/null
	qemu-system-x86_64 -enable-kvm -m 4G -smp 2 \
	    -kernel /tmp/bis-vmlinuz \
	    -initrd /tmp/bis-initrd \
	    -append "boot=live install=update-yes quiet" \
	    -cdrom $(OUTPUT) \
	    -drive file=$(TARGET_DISK),if=virtio,format=qcow2 \
	    -device virtio-vga,xres=1280,yres=720 \
	    -display gtk,zoom-to-fit=on \
	    -audiodev pa,id=snd0 \
	    -device intel-hda -device hda-output,audiodev=snd0 \
	    -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp::2222-:22 \
	    -usb -device usb-kbd -device usb-tablet \
