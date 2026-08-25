#!/usr/bin/env bash
# Bootloader installation and configuration

install_limine() {
    print_status "Installing Limine bootloader (UEFI)"

    # Install the limine userland and efibootmgr in the target system. We do
    # not run `limine bios-install`: the disk layout is GPT + ESP only (no
    # BIOS boot partition) and the installer enforces UEFI via check_uefi.
    arch-chroot /mnt /bin/bash << 'EOF'
pacman -Sy
pacman -S --noconfirm --needed limine efibootmgr
EOF

    # Configure based on GPU type. Microcode image comes from CPU_MICROCODE_IMG
    # (set by detect_cpu_vendor), independent of the GPU choice.
    # resume=/resume_offset= point the kernel at the hibernation image in the
    # btrfs swapfile. systemd-hibernate-resume can also pick the location up
    # from the HibernateLocation EFI variable, but that is only set while a
    # hibernation image exists -- the kernel parameters are what make the
    # setup survive a cleared or unavailable variable.
    local KERNEL_PARAMS="root=LABEL=ARCH rootflags=subvol=@ rw quiet loglevel=3"
    KERNEL_PARAMS="$KERNEL_PARAMS resume=LABEL=ARCH resume_offset=${SWAP_RESUME_OFFSET}"
    local MICROCODE_IMG="$CPU_MICROCODE_IMG"

    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        print_status "Configuring Limine for Nvidia GPU"
        KERNEL_PARAMS="$KERNEL_PARAMS $(get_nvidia_kernel_params)"
    else
        print_status "Configuring Limine for AMD GPU"
        KERNEL_PARAMS="$KERNEL_PARAMS $(get_amd_kernel_params)"
    fi

    arch-chroot /mnt /bin/bash << LIMINE_EOF
set -euo pipefail

# Write the Limine config at the ESP root. Limine searches for limine.conf
# next to its binary first and then at the root of the boot volume, so
# /boot/limine.conf works alongside /boot/EFI/limine/BOOTX64.EFI.
cat > /boot/limine.conf << 'LIMINE_CONFIG_EOF'
timeout: 2
graphics: yes
wallpaper: boot():/wallpaper.png
default_entry: 2

/+Arch Linux
    comment: Arch Linux (linux-zen)

    //Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-zen
    kernel_cmdline: ${KERNEL_PARAMS}
    module_path: boot():/${MICROCODE_IMG}
    module_path: boot():/initramfs-linux-zen.img

    //Snapshots

/Arch Linux Fallback
    comment: Arch Linux Fallback (linux-zen)
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-zen
    kernel_cmdline: root=LABEL=ARCH rootflags=subvol=@ rw resume=LABEL=ARCH resume_offset=${SWAP_RESUME_OFFSET}
    module_path: boot():/${MICROCODE_IMG}
    module_path: boot():/initramfs-linux-zen-fallback.img

LIMINE_CONFIG_EOF

# Deploy the Limine UEFI binary to the exact paths limine-entry-tool owns:
# EFI/limine/limine_x64.efi is what its 80-limine-efi-deploy.hook refreshes on
# every limine upgrade, and EFI/BOOT/BOOTX64.EFI is the removable fallback the
# firmware boots with no NVRAM entry at all. Any other filename here becomes a
# third copy that no hook ever updates, drifting out of step with the
# limine.conf that limine-snapper-sync keeps rewriting.
mkdir -p /boot/EFI/limine /boot/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/limine_x64.efi
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI

# Drop any stale Limine NVRAM entries from a previous failed install so
# re-runs do not accumulate duplicates.
while read -r bootnum; do
    [[ -z "\$bootnum" ]] && continue
    efibootmgr --quiet --bootnum "\$bootnum" --delete-bootnum
done < <(efibootmgr | awk '\$1 ~ /^Boot[0-9A-Fa-f]{4}\\*?\$/ && \$2 == "Limine" {print substr(\$1, 5, 4)}')

# Register a proper NVRAM boot entry pointing at the installed binary.
# The ESP is always partition 1 per lib/disk_setup.sh.
efibootmgr --quiet --create \\
    --disk "${TARGET_DISK}" \\
    --part 1 \\
    --label "Limine" \\
    --loader '\\EFI\\limine\\limine_x64.efi'
LIMINE_EOF

    cp "${SCRIPT_DIR}/arch_wallpaper.png" /mnt/boot/wallpaper.png

    # /etc/limine-snapper-sync.conf is owned by the limine-snapper-sync
    # package, which is only installed later in the post-install desktop
    # phase. Writing it here leaves an unowned file on that path and pacman
    # then refuses to install the package at all ("exists in filesystem").
    # configure_limine_snapper_sync in post_install/packages_desktop.sh tunes
    # the packaged file once it is actually there.

    print_success "Limine installed"
}
