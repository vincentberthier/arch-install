#!/usr/bin/env bash
# Desktop environment packages

install_desktop_packages() {
    local packages=(
        # Desktop environments
        "hyprland" "waybar" "hyprpaper" "hypridle" "hyprlock" "wofi" "mako"
        "xdg-desktop-portal" "xdg-desktop-portal-hyprland"
        "wl-clipboard" "grim" "slurp" "labwc"
        "qt5-graphicaleffects" "qt5-svg" "qt5-quickcontrols2"
        
        # Plasma desktop (fallback)
        "plasma-meta" "kde-applications-meta"
        "xdg-desktop-portal-kde"
        
        # Applications
        "thunderbird" "discord" "signal-desktop" "telegram-desktop" "element-desktop"
        "libreoffice-fresh" "obsidian" "qbittorrent"
        "mpv" "vlc" "gimp"
    )
    
    print_status "Installing Desktop packages (${#packages[@]} packages)"
    
    # Split into chunks
    local chunk_size=20
    for ((i=0; i<${#packages[@]}; i+=chunk_size)); do
        local chunk=("${packages[@]:i:chunk_size}")
        print_status "Installing chunk: ${chunk[*]}"
        
        if ! doas pacman -S --needed --noconfirm "${chunk[@]}"; then
            print_warning "Some packages in chunk failed to install, continuing..."
        fi
    done
    
    # Desktop AUR packages
    local aur_packages=(
        "zen-browser-bin"             # Your primary browser
        "wl-screenrec"                # screen record for Wayland
        "webcord"                     # Discord alternative
        "sddm-theme-corners-git"      # sddm theme
        "limine-snapper-sync"         # boot on snapshots
        "limine-entry-tool"           # limine sync helpers
        "wleave-git"                  # logout utils
        "hyprcursor-dracula-kde-git"
        "bibata-cursor-theme-bin"

    )
    
    for package in "${aur_packages[@]}"; do
        print_status "Installing $package from AUR"
        if ! paru -S --needed --noconfirm "$package"; then
            print_warning "Failed to install $package, continuing..."
        fi
    done
    
    # Enable limine-snapper-sync service
    doas systemctl enable --now limine-snapper-sync.service
    
    # Install problematic AUR packages with PGP issues
    install_pgp_messed_up_packages
    
    print_success "Desktop packages installation completed"
}

install_pgp_messed_up_packages() {
    print_status "Installing AUR packages with PGP issues"
    
    local problematic_packages=("1password" "1password-cli" "spotify")
    
    for package in "${problematic_packages[@]}"; do
        print_status "Installing $package"
        if ! paru -S --noconfirm "$package"; then
            print_warning "Normal install failed for $package, trying with skipped PGP check"
            paru -S --noconfirm --mflags="--skippgpcheck" "$package" || \
            print_warning "Failed to install $package even with skipped PGP"
        fi
    done
    paru -S --noconfirm --mflags="--nocheck" wezterm-git # test fails on SSH agent
    
    print_success "Problematic AUR packages installation completed"
}

setup_display_manager() {
    print_status "Setting up display manager"
    
    # Configure SDDM
    doas mkdir -p /etc/sddm.conf.d

    local sddm_gpu=""
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        print_status "Setting up Nvidia environment variables for SDDM"
        sddm_gpu="$(get_nvidia_sddm_config)"
    fi

    doas tee /etc/sddm.conf.d/wayland.conf << SDDM_EOF
[General]
DisplayServer=wayland
${sddm_gpu}

[Theme]
Current=corners

[Wayland]
CompositorCommand=/usr/local/bin/sddm-labwc
SessionDir=/usr/share/wayland-sessions
SDDM_EOF

    doas tee /usr/share/sddm/themes/corners/theme.conf.user << 'SDDM_EOF'
BgSource="backgrounds/glacier.png"
FontFamily="Dank Mono"
FontSize=9
Padding=50
Radius=10
Scale=1

DateTimeSpacing=0
SDDM_EOF

    # Use the Plasma Wayland compositor directly
    doas tee /usr/local/bin/sddm-labwc << 'EOF'
#!/usr/bin/env bash

export XKB_DEFAULT_LAYOUT="fr,fr,us"
export XKB_DEFAULT_VARIANT="bepo,,"
export XKB_DEFAULT_OPTIONS="grp:alt_shift_toggle"
exec labwc
EOF
    doas chmod +x /usr/local/bin/sddm-labwc
    
    # Enable SDDM now that desktop environments are installed
    doas systemctl enable sddm
    
    print_success "SDDM configured and enabled"
}
