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
echo "en_US.UTF-8" >> /etc/locale.gen
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
usermod -a -G plugdev $USERNAME

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

# Configure pacman
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Sync databases after enabling multilib
pacman -Sy

# Configure keyboard for console/TTY
echo "KEYMAP=fr-bepo" > /etc/vconsole.conf

sh -c "$(curl -fsSL https://steevelefort.github.io/optimot-install/install.sh)"

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

# Jail directory for SFTP
mkdir -p /var/lib/jail
useradd -G sshusers -s /usr/bin/nologin -d /var/lib/jail sftp_user
echo "sftp_user:sftp_user" | chpasswd

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

Subsystem sftp /usr/lib/ssh/sftp-server

Match group sshusers
 AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys
 ChrootDirectory %h
 X11Forwarding no
 AllowTcpForwarding no
 PasswordAuthentication no
 PermitEmptyPasswords no
 ForceCommand internal-sftp
SSH_EOF

mkdir /etc/ssh/authorized_keys
chown root:root /etc/ssh/authorized_keys
chmod 755 /etc/ssh/authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEaVvdqcBRa6S4jORfKN7R98rHUptFeV6WgcO9rpQsIP vincent.berthier@tyrex-cyber.com" > /etc/ssh/authorized_keys/tyrex
chmod 644 /etc/ssh/authorized_keys/tyrex
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPYmwsF4C6jAgqO43vPaNFRZVNvvL4Zoi+wKmYS2FlAJ vincent.berthier@posteo.org" > /etc/ssh/authorized_keys/vincent
chmod 644 /etc/ssh/authorized_keys/vincent

# Enable SSH service
systemctl enable sshd
EOF

    print_success "System configured with SSH enabled"
    echo
    echo -e "${GREEN}SSH will be available after reboot${NC}"
    echo "Connect with: ssh vincent@<ip-address>"
    echo -e "${YELLOW}Don't forget to set password: passwd${NC}"
}

configure_firewall() {
    print_status "Configuring firewall with nftables"

    arch-chroot /mnt /bin/bash << EOF
pacman -Sy --noconfirm nftables

# If iptables firewall is set up for some reason, disable it
systemctl stop iptables.service 2>/dev/null || true
systemctl disable iptables.service 2>/dev/null || true
systemctl stop ip6tables.service 2>/dev/null || true
systemctl disable ip6tables.service 2>/dev/null || true

cat > /etc/nftables.conf << 'NFTABLES_EOF'
#!/usr/bin/nft -f

# Clear all prior state
flush ruleset

# Define variables for easier management
define SSH_PORT = 22
define HTTP_PORT = 80
define HTTPS_PORT = 443
define CUSTOM_TCP_PORTS = { 1234, 2222, 8080 }
define DNS_PORT = 53

# Steam ports for gaming and remote play
define STEAM_CLIENT_PORTS = { 27000-27100 }      # Steam client traffic
define STEAM_SERVER_PORTS = { 27015-27030 }      # Steam game servers
define STEAM_REMOTE_PLAY_TCP = { 27036-27037 }   # Steam Remote Play TCP
define STEAM_REMOTE_PLAY_UDP = { 27031-27036 }   # Steam Remote Play UDP
define STEAM_STREAMING_TCP = { 27040 }           # Steam In-Home Streaming TCP
define STEAM_STREAMING_UDP = { 27000-27100 }     # Steam In-Home Streaming UDP range
define STEAM_DISCOVERY = { 27036 }               # Steam discovery
define STEAM_BROADCAST_DISCOVERY = { 27036 }     # Steam broadcast discovery

table inet filter {
    chain input {
        # Base chain with drop policy
        type filter hook input priority 0; policy drop;

        # Allow loopback traffic
        iif lo accept

        # Allow established and related connections
        ct state established,related accept

        # Allow ICMP/ICMPv6 (ping, etc.)
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH access
        tcp dport \$SSH_PORT ct state new accept

        # HTTP and HTTPS
        tcp dport { \$HTTP_PORT, \$HTTPS_PORT } ct state new accept

        # Custom TCP ports
        tcp dport \$CUSTOM_TCP_PORTS ct state new accept

        # DNS
        udp dport \$DNS_PORT accept

        # Steam Client Traffic (UDP)
        udp dport \$STEAM_CLIENT_PORTS accept

        # Steam Game Servers (UDP)
        udp dport \$STEAM_SERVER_PORTS accept

        # Steam Remote Play (TCP)
        tcp dport \$STEAM_REMOTE_PLAY_TCP ct state new accept

        # Steam Remote Play (UDP)
        udp dport \$STEAM_REMOTE_PLAY_UDP accept

        # Steam In-Home Streaming (TCP)
        tcp dport \$STEAM_STREAMING_TCP ct state new accept

        # Steam In-Home Streaming (UDP)
        udp dport \$STEAM_STREAMING_UDP accept

        # Steam Discovery (UDP)
        udp dport \$STEAM_DISCOVERY accept

        # Additional Steam ports for Big Picture mode and controller support
        tcp dport { 27014-27050 } ct state new accept
        udp dport { 4380, 27000-27031, 27036 } accept

        # Steam broadcasting and remote play discovery
        udp dport 27036 accept

        # Log dropped packets (optional - comment out if too verbose)
        # limit rate 5/minute log prefix "nftables-dropped: "

        # Drop everything else (implicit due to policy drop)
    }

    chain forward {
        # Base chain with drop policy
        type filter hook forward priority 0; policy drop;

        # Allow forwarding for established and related connections
        ct state established,related accept

        # Add custom forwarding rules here if needed
    }

    chain output {
        # Base chain with accept policy (allow all outgoing by default)
        type filter hook output priority 0; policy accept;
    }
}

# Optional: NAT table for masquerading (useful if this machine acts as a router)
# Uncomment if needed
# table ip nat {
#     chain postrouting {
#         type nat hook postrouting priority 100; policy accept;
#         # masquerade private networks
#         ip saddr 192.168.0.0/16 oifname != "lo" masquerade
#         ip saddr 10.0.0.0/8 oifname != "lo" masquerade
#         ip saddr 172.16.0.0/12 oifname != "lo" masquerade
#     }
# }
NFTABLES_EOF

# Set proper permissions
chmod 644 /etc/nftables.conf

systemctl enable nftables.service
systemctl start nftables.service
EOF

    print_success "Firewall setup completed successfully!"
    echo "Open ports:"
    echo "  TCP: 22 (SSH), 80 (HTTP), 443 (HTTPS), 1234, 2222, 8080"
    echo "  UDP: 53 (DNS)"
    echo "  Steam ports: Various TCP/UDP ranges for gaming and remote play"
    echo
    echo -e "${YELLOW}Important notes:${NC}"
    echo -e "${YELLOW}  - SSH is accessible on port 22. Ensure you have access before disconnecting!${NC}"
    echo -e "${YELLOW}  - Configuration is saved in /etc/nftables.conf${NC}"
    echo -e "${YELLOW}  - Service will start automatically on boot${NC}"
    echo -e "${YELLOW}  - To modify rules, edit /etc/nftables.conf and run: systemctl reload nftables${NC}"
}
