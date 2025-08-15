#!/usr/bin/env bash
set -euo pipefail

# Arch Linux Installation Script with Btrfs + Snapper + Limine
# Optimized for Vincent's NixOS migration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
HOSTNAME=""
FONT_PASSWD=""
USERNAME="vincent"
USER_EMAIL="vincent.berthier@posteo.org"
TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8"
KEYBOARD="fr"
KEYBOARD_VARIANT="bepo"

# Disk configuration
TARGET_DISK=""
BOOT_SIZE="512M"
ROOT_SIZE="250G"
SWAP_SIZE="16G"

# Subvolume configuration
declare -A SUBVOLS=(
    ["@"]="/"
    ["@var_log"]="/var/log"
    ["@var_cache"]="/var/cache"
    ["@var_tmp"]="/var/tmp"
    ["@swap"]="/swap"
)

# Functions
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        print_error "This script requires UEFI boot mode"
        exit 1
    fi
    print_success "UEFI boot mode detected"
}

check_internet() {
    if ! ping -c 1 www.google.fr &> /dev/null; then
        print_error "No internet connection"
        exit 1
    fi
    print_success "Internet connection verified"
}

get_user_input() {
    echo -e "${BLUE}=== Arch Linux Installation Configuration ===${NC}"
    
    # Hostname
    while [[ -z "$HOSTNAME" ]]; do
        read -p "Enter hostname: " HOSTNAME
        if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
            print_warning "Invalid hostname. Use only letters, numbers, and hyphens."
            HOSTNAME=""
        fi
    done

    # Font zip password
    while [[ -z "$FONT_PASSWD" ]]; do
        read -p "Enter dank mono zip password: " FONT_PASSWD
        if [[ ! "$FONT_PASSWD" =~ ^[a-zA-Z0-9-]+$ ]]; then
            print_warning "Invalid font password. Use only letters, numbers, and hyphens."
            FONT_PASSWD=""
        fi
    done
    
    # Target disk
    echo
    print_status "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo
    
    while [[ -z "$TARGET_DISK" ]]; do
        read -p "Enter target disk (e.g., /dev/sda): " TARGET_DISK
        if [[ ! -b "$TARGET_DISK" ]]; then
            print_warning "Invalid disk. Please enter a valid block device."
            TARGET_DISK=""
        fi
    done
    
    # Confirmation
    echo
    echo -e "${YELLOW}=== Configuration Summary ===${NC}"
    echo "Hostname: $HOSTNAME"
    echo "Target disk: $TARGET_DISK"
    echo "Root partition: 250GB (for system + snapshots)"
    echo "Home partition: ~750GB (remaining space)"
    echo "Username: $USERNAME"
    echo "Timezone: $TIMEZONE"
    echo "Locale: $LOCALE"
    echo "Keyboard: $KEYBOARD ($KEYBOARD_VARIANT)"
    echo
    print_warning "This will COMPLETELY ERASE $TARGET_DISK"
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_error "Installation cancelled"
        exit 1
    fi
}

prepare_disk() {
    print_status "Preparing disk $TARGET_DISK"
    
    # Unmount any existing mounts
    umount -R /mnt 2>/dev/null || true
    
    # Wipe disk
    wipefs -af "$TARGET_DISK"
    sgdisk --zap-all "$TARGET_DISK"
    
    # Create partitions
    print_status "Creating partitions"
    sgdisk --new=1:0:+${BOOT_SIZE} --typecode=1:ef00 --change-name=1:"EFI System" "$TARGET_DISK"
    sgdisk --new=2:0:+${ROOT_SIZE} --typecode=2:8300 --change-name=2:"Linux filesystem" "$TARGET_DISK"
    sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"Home" "$TARGET_DISK"
    
    # Get partition names
    if [[ "$TARGET_DISK" =~ nvme ]]; then
        BOOT_PART="${TARGET_DISK}p1"
        ROOT_PART="${TARGET_DISK}p2"
        HOME_PART="${TARGET_DISK}p3"
    else
        BOOT_PART="${TARGET_DISK}1"
        ROOT_PART="${TARGET_DISK}2"
        HOME_PART="${TARGET_DISK}3"
    fi
    
    print_success "Partitions created: $BOOT_PART (boot), $ROOT_PART (root), $HOME_PART (home)"
}

format_partitions() {
    print_status "Formatting partitions"
    
    # Format boot partition
    mkfs.fat -F32 -n "BOOT" "$BOOT_PART"
    
    # Format root partition with btrfs
    mkfs.btrfs -f -L "ARCH" "$ROOT_PART"
    
    # Format home partition with btrfs  
    mkfs.btrfs -f -L "HOME" "$HOME_PART"
    
    print_success "Partitions formatted"
}

create_subvolumes() {
    print_status "Creating btrfs subvolumes"
    
    # Mount root to create subvolumes
    mount "$ROOT_PART" /mnt
    
    # Create subvolumes
    for subvol in "${!SUBVOLS[@]}"; do
        btrfs subvolume create "/mnt/$subvol"
        print_status "Created subvolume: $subvol"
    done
    
    # Unmount
    umount /mnt
    
    print_success "Subvolumes created"
}

mount_filesystem() {
    print_status "Mounting filesystem"
    
    local mount_opts="noatime,compress=zstd:1,space_cache=v2,discard=async"
    
    # Mount root subvolume (no @home subvolume needed)
    mount -o "$mount_opts,subvol=@" "$ROOT_PART" /mnt
    
    # Create mount points and mount system subvolumes only
    for subvol in "${!SUBVOLS[@]}"; do
        if [[ "$subvol" != "@" && "$subvol" != "@home" ]]; then  # Skip @home
            local mount_point="/mnt${SUBVOLS[$subvol]}"
            mkdir -p "$mount_point"
            mount -o "$mount_opts,subvol=$subvol" "$ROOT_PART" "$mount_point"
            print_status "Mounted $subvol -> $mount_point"
        fi
    done
    
    # Mount separate home partition (no subvolumes)
    mkdir -p /mnt/home
    mount -o "$mount_opts" "$HOME_PART" /mnt/home
    
    # Mount boot partition
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot
    
    # Create swapfile
    print_status "Creating swapfile"
    btrfs filesystem mkswapfile --size "$SWAP_SIZE" /mnt/swap/swapfile
    swapon /mnt/swap/swapfile
    
    print_success "Filesystem mounted"
}

install_base_system() {
    print_status "Installing base system"
    
    # Update mirrors
    # reflector --country France --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

    # Detect GPU and install appropriate drivers
    if lspci | grep -i nvidia &>/dev/null; then
        print_status "Nvidia GPU detected, installing Nvidia drivers"
        GPU_PACKAGES="nvidia nvidia-utils nvidia-settings"
        LIB32_GPU_PACKAGES="lib32-nvidia-utils"
        MICROCODE="intel-ucode"
    else
        print_status "AMD GPU assumed, installing AMD drivers"
        GPU_PACKAGES="mesa vulkan-radeon xf86-video-amdgpu"
        LIB32_GPU_PACKAGES="lib32-mesa lib32-vulkan-radeon"
        MICROCODE="amd-ucode"
    fi
    
    # Install base packages
    pacstrap -K /mnt \
        base base-devel linux-zen linux-zen-headers linux-firmware $MICROCODE \
        btrfs-progs snapper snap-pac \
        networkmanager bluez bluez-utils \
        git chezmoi fish \
        nano helix \
        man-db man-pages \
        reflector cargo sddm \
        ttf-nerd-fonts-symbols-mono ttf-fira-code ttf-jetbrains-mono-nerd \
        $GPU_PACKAGES

# Only keep linux-zen kernel
arch-chroot /mnt /bin/bash << 'EOF'
pacman -R linux --noconfirm
# Remove linux preset if it exists
rm -f /etc/mkinitcpio.d/linux.preset

# Remove any stale initramfs files
rm -f /boot/initramfs-linux.img
rm -f /boot/initramfs-linux-fallback.img
rm -f /boot/vmlinuz-linux

# Only keep linux-zen files
ls -la /boot/
EOF

    # Enable multilib in the installed system
    arch-chroot /mnt /bin/bash << 'MULTILIB_EOF'
# We’re using linux-zen instead
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Sy
MULTILIB_EOF
    
    # Now install lib32 packages
    if [[ -n "$LIB32_GPU_PACKAGES" ]]; then
        arch-chroot /mnt pacman -S --noconfirm $LIB32_GPU_PACKAGES
    fi
     
    print_success "Base system installed"
}

install_fonts() {
    local font_file=""
    if [[ -f "DankMono.zip" ]]; then
        font_file="DankMono.zip"
    elif [[ -f "fonts.zip" ]]; then
        font_file="fonts.zip"
    fi
    
    if [[ -n "$FONT_PASSWD" && -n "$font_file" ]]; then
        print_status "Installing custom fonts from $font_file"
        
        # Copy to a persistent location, not /tmp
        mkdir -p /mnt/opt/temp
        cp "$font_file" /mnt/opt/temp/
        
        arch-chroot /mnt /bin/bash << EOF
# Install unzip if not available
pacman -S --noconfirm unzip

# Create temporary directory
mkdir -p /tmp/fonts

# Extract fonts with password from copied zip
unzip -P "$FONT_PASSWD" "/opt/temp/$font_file" "*.otf" -d /tmp/fonts/ 2>/dev/null || {
    echo "Failed to extract fonts or no .otf files found"
    exit 1
}

# Install fonts system-wide
mkdir -p /usr/share/fonts/custom
find /tmp/fonts -name "*.otf" -exec cp {} /usr/share/fonts/custom/ \;

# Update font cache
fc-cache -fv

# Cleanup
rm -rf /tmp/fonts "/opt/temp/$font_file"
rmdir /opt/temp 2>/dev/null || true

EOF

        if [[ $? -eq 0 ]]; then
            print_success "Custom fonts installed system-wide"
        else
            print_warning "Font installation failed"
        fi
    else
        print_warning "No font password set or font file not found, skipping font installation"
    fi
}

configure_system() {
    print_status "Configuring system"
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Configure system in chroot
    arch-chroot /mnt /bin/bash << EOF
# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configure locale
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Configure keyboard
echo "KEYMAP=$KEYBOARD" > /etc/vconsole.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Configure hosts
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable systemd-timesyncd
systemctl enable reflector.timer
systemctl enable fstrim.timer

# Create user
useradd -m -G wheel,audio,video,optical,storage -s /bin/fish $USERNAME
echo "$USERNAME:$USERNAME" | chpasswd

# Install and configure doas as primary
pacman -S --noconfirm opendoas

# Configure doas (NO PASSWORD)
cat > /etc/doas.conf << DOAS_EOF
# Allow wheel group to execute commands as root without password
permit nopass :wheel
DOAS_EOF

# Set proper permissions on doas.conf
chown root:root /etc/doas.conf
chmod 600 /etc/doas.conf

# Configure sudo ONLY for snapper and other broken tools
cat > /etc/sudoers.d/broken-software << SUDO_EOF
# ONLY for software that hardcodes sudo like idiots
%wheel ALL=(ALL) NOPASSWD: /usr/bin/snapper, /usr/bin/btrfs, /usr/bin/snap-pac, /usr/bin/pacman
SUDO_EOF
chmod 440 /etc/sudoers.d/broken-software

# Alias helix to hx
ln -sf /usr/bin/helix /usr/local/bin/hx

# Configure pacman
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Sync databases after enabling multilib
pacman -Sy

# Configure keyboard for console/TTY
echo "KEYMAP=fr-bepo" > /etc/vconsole.conf

# Configure keyboard for X11/Wayland
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << 'KEYBOARD_EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "fr"
    Option "XkbVariant" "bepo"
EndSection
KEYBOARD_EOF

# For Wayland compositors that don't read X11 config, set environment
echo 'export XKB_DEFAULT_LAYOUT=fr' >> /etc/environment
echo 'export XKB_DEFAULT_VARIANT=bepo' >> /etc/environment

# Disable TPM
systemctl mask systemd-tpm2-setup-early.service
systemctl mask systemd-tpm2-setup.service
systemctl mask tpm2.target

# Configure Nvidia if present
if lspci | grep -i nvidia &>/dev/null; then
    echo "Configuring Nvidia drivers..."
    
    # Add Nvidia modules to mkinitcpio
    sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    
    # Regenerate initramfs
    mkinitcpio -P
    
    # Create Nvidia udev rules
    echo 'ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="/usr/bin/nvidia-modprobe -c0 -u"' > /etc/udev/rules.d/70-nvidia.rules
    
    # Enable nvidia-persistenced
    systemctl disable nvidia-persistenced
    systemctl mask nvidia-persistenced
fi

EOF

    print_success "System configured with doas"
}

setup_snapper() {
    print_status "Setting up Snapper"
    
    arch-chroot /mnt /bin/bash << 'EOF'
# Create snapper config for root (let it create its own .snapshots)
snapper -c root create-config /

# Don't delete snapper's subvolume or try to replace it
# The previous approach was wrong - let snapper manage its own subvolume

# Set snapper configuration
cat > /etc/snapper/configs/root << 'SNAPPER_EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
SNAPPER_EOF

# Enable snapper services
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

EOF

    print_success "Snapper configured"
}

install_limine() {
    print_status "Installing Limine bootloader"
    
    arch-chroot /mnt /bin/bash << 'EOF'
# Update package database
pacman -Sy
# Install limine from official repos
pacman -S --noconfirm limine

# Install limine to disk  
TARGET_DISK_LIMINE=$(lsblk -no PKNAME $(findmnt -no SOURCE /) | head -1)
limine bios-install /dev/${TARGET_DISK_LIMINE}

# Detect GPU and set appropriate kernel parameters
if lspci | grep -i nvidia &>/dev/null; then
    echo "Configuring Limine for Nvidia GPU"
    KERNEL_PARAMS="root=LABEL=ARCH rootflags=subvol=@ rw quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
    # Nvidia GPUs are usually paired with Intel CPUs
    MICROCODE_IMG="intel-ucode.img"
else
    echo "Configuring Limine for AMD GPU"  
    KERNEL_PARAMS="root=LABEL=ARCH rootflags=subvol=@ rw quiet loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3"
    MICROCODE_IMG="amd-ucode.img"
fi

# Create limine configuration with GPU-specific parameters
mkdir -p /boot/EFI/BOOT
cat > /boot/limine.conf << LIMINE_EOF
timeout: 2
graphics: yes
default_entry: 1

/Arch Linux
    comment: Arch Linux (linux-zen)
    comment: machine-id=$(cat /etc/machine-id)

    //Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-zen
    kernel_cmdline: ${KERNEL_PARAMS}
    module_path: boot():/${MICROCODE_IMG}
    module_path: boot():/initramfs-linux-zen.img

/Arch Linux Fallback
    comment: Arch Linux Fallback (linux-zen)
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-zen
    kernel_cmdline: root=LABEL=ARCH rootflags=subvol=@ rw
    module_path: boot():/${MICROCODE_IMG}
    module_path: boot():/initramfs-linux-zen-fallback.img


LIMINE_EOF

# Copy limine files
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cp /usr/share/limine/limine-bios.sys /boot/

EOF

    print_success "Limine installed"
}

configure_openssh() {
    print_status "Configuring system"
    
    # Configure system in chroot
    arch-chroot /mnt /bin/bash << EOF
# Install and configure SSH server for remote debugging
pacman -S --noconfirm openssh

# Configure SSH
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/install.conf << 'SSH_EOF'
Port 22
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
UsePAM yes
SSH_EOF

# Enable SSH service
systemctl enable sshd
EOF

    print_success "System configured with SSH enabled"
    echo
    echo -e "${GREEN}SSH will be available after reboot${NC}"
    echo "Connect with: ssh vincent@<ip-address>"
    echo -e "${YELLOW}Don't forget to set password: passwd${NC}"
}

copy_post_install() {
    print_status "Copying post-install script"
    
    # Copy the actual post_install.sh script to user's home
    if [[ -f "post_install.sh" ]]; then
        cp post_install.sh /mnt/home/$USERNAME/
        # chown $USERNAME:$USERNAME /mnt/home/$USERNAME/post_install.sh
        chmod +x /mnt/home/$USERNAME/post_install.sh
        print_success "Post-install script copied to /home/$USERNAME/"
    else
        print_warning "post_install.sh not found in current directory"
        print_warning "You'll need to download it manually after installation"
    fi
}

check_secure_boot() {
    if [[ -d /sys/firmware/efi/efivars ]] && [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]]; then
        if od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tr -d ' ' | grep -q 1; then
            print_warning "Secure Boot is currently enabled"
            print_warning "This installation requires Secure Boot to be disabled"
            print_warning "Please disable it in BIOS/UEFI settings before first boot"
        else
            print_success "Secure Boot is disabled - good to go"
        fi
    else
        print_success "Secure Boot check completed"
    fi
}

main() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  Arch Linux Installation with Btrfs + Snapper"
    echo "  Optimized for Vincent's NixOS Migration"
    echo "=================================================="
    echo -e "${NC}"
    
    check_uefi
    check_internet
    check_secure_boot
    get_user_input
    
    prepare_disk
    format_partitions
    create_subvolumes
    mount_filesystem
    install_base_system
    configure_system
    install_fonts
    configure_openssh
    setup_snapper
    install_limine
    copy_post_install
    
    print_success "Installation completed!"
    echo
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Reboot into the new system"
    echo "2. Log in as $USERNAME"
    echo "3. Run ~/post-install.sh to install AUR helper and basic packages"
    echo "4. Set up chezmoi with your dotfiles"
    echo "5. Configure 1Password integration"
    echo
    echo -e "${YELLOW}Important:${NC}"
    echo "- Set user password: passwd"
    echo "- Configure chezmoi: chezmoi init --apply"
    echo
    read -p "Press Enter to reboot or Ctrl+C to stay in live environment..."
    reboot
}

# Run main function
main "$@"
