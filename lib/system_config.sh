#!/usr/bin/env bash
# System configuration functions

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

EOF

    # Apply GPU-specific configuration
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        configure_nvidia_system
    fi

    print_success "System configured with doas"
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
