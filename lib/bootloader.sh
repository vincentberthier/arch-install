#!/usr/bin/env bash
# Bootloader installation and configuration

install_limine() {
    print_status "Installing Limine bootloader"
    
    arch-chroot /mnt /bin/bash << 'EOF'
# Update package database
pacman -Sy
# Install limine from official repos
pacman -S --noconfirm limine

# Install limine to disk  
# Get the root device, handling btrfs subvolume syntax
ROOT_DEVICE=$(findmnt -no SOURCE / | sed 's/\[.*\]//g')
# Get the parent disk name
TARGET_DISK_LIMINE=$(lsblk -no PKNAME ${ROOT_DEVICE} | head -1)
# Install limine
limine bios-install /dev/${TARGET_DISK_LIMINE}
EOF

    # Configure based on GPU type
    local KERNEL_PARAMS="root=LABEL=ARCH rootflags=subvol=@ rw quiet loglevel=3"
    local MICROCODE_IMG=""
    
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        print_status "Configuring Limine for Nvidia GPU"
        KERNEL_PARAMS="$KERNEL_PARAMS $(get_nvidia_kernel_params)"
        MICROCODE_IMG="intel-ucode.img"
    else
        print_status "Configuring Limine for AMD GPU"
        KERNEL_PARAMS="$KERNEL_PARAMS $(get_amd_kernel_params)"
        MICROCODE_IMG="amd-ucode.img"
    fi

    arch-chroot /mnt /bin/bash << LIMINE_EOF
# Create limine configuration with GPU-specific parameters
mkdir -p /boot/EFI/BOOT
cat > /boot/limine.conf << 'LIMINE_CONFIG_EOF'
timeout: 2
graphics: yes
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
    kernel_cmdline: root=LABEL=ARCH rootflags=subvol=@ rw
    module_path: boot():/${MICROCODE_IMG}
    module_path: boot():/initramfs-linux-zen-fallback.img

LIMINE_CONFIG_EOF

# Copy limine files
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cp /usr/share/limine/limine-bios.sys /boot/

LIMINE_EOF

doas sed -i 's/LIMIT_USAGE_PERCENT=.*/LIMIT_USAGE_PERCENT=99/' /etc/limine-snapper-sync.conf

    print_success "Limine installed"
}
