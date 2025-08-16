#!/usr/bin/env bash
# Core packages installation - essential for all systems

update_system() {
    print_status "Updating system packages"
    doas pacman -Syu --noconfirm
    print_success "System updated"
}

install_paru() {
    if command -v paru &> /dev/null; then
        print_success "paru already installed"
        return
    fi
    
    print_status "Installing paru from pre-compiled binary"
    
    # Download latest paru release
    cd /tmp
    curl -L -o paru.tar.zst $(curl -s https://api.github.com/repos/Morganamilo/paru/releases/latest | grep "browser_download_url.*x86_64.*tar.zst" | cut -d '"' -f 4)
    
    # Extract and install
    tar -xf paru.tar.zst
    doas mv paru /usr/local/bin/
    chmod +x /usr/local/bin/paru

    paru -Sy --noconfirm zsa-wally-cli
        
    print_success "paru installed"
}

install_core_packages() {
    local packages=(
        # Essential system
        "pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack" "wireplumber"
        
        # Essential CLI tools
        "starship" "eza" "bat" "fd" "ripgrep" "sd" "dust" "duf" "btop" "zoxide" "fzf"
        "git" "lazygit" "difftastic" "meld" "git-delta"
        "tree" "unzip" "wget" "curl" "rsync" "fastfetch" "tldr"
        "yazi"
        
        # Security and keys
        "keychain" "gnupg" "pass"
        
        # Terminals
        "kitty" "foot"
        
        # Audio/video
        "playerctl" "pavucontrol"
    )
    
    # Add GPU-specific core packages
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        # Already installed during base install, but ensure they're there
        packages+=("nvidia-utils" "nvidia-settings")
    else
        packages+=("mesa" "lib32-mesa" "vulkan-radeon" "lib32-vulkan-radeon")
    fi
    
    print_status "Installing Core packages (${#packages[@]} packages)"
    
    # Split into chunks to avoid command line length issues
    local chunk_size=20
    for ((i=0; i<${#packages[@]}; i+=chunk_size)); do
        local chunk=("${packages[@]:i:chunk_size}")
        print_status "Installing chunk: ${chunk[*]}"
        
        if ! doas pacman -S --needed --noconfirm "${chunk[@]}"; then
            print_warning "Some packages in chunk failed to install, continuing..."
        fi
    done
    
    bat cache --build
    
    # Install essential AUR packages
    local aur_packages=(
        "paru"                        # AUR helper (if not already installed)
        "dprint-bin"                  # formatter
        "watchman-bin"                # inotify-like
    )
    
    for package in "${aur_packages[@]}"; do
        print_status "Installing $package from AUR"
        if ! paru -S --needed --noconfirm "$package"; then
            print_warning "Failed to install $package, continuing..."
        fi
    done
    
    print_success "Core packages installation completed"
}
