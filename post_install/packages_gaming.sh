#!/usr/bin/env bash
# Gaming packages installation

install_gaming_packages() {
    local packages=(
        # Gaming
        "gamemode" "lib32-gamemode" "mangohud" "lib32-mangohud"
        "steam" "lutris" "wine-staging"
        "ttf-liberation" "ttf-dejavu" "noto-fonts"
    )
    
    # Add GPU-specific gaming tools
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        packages+=("nvidia-utils" "lib32-nvidia-utils" "lib32-opencl-nvidia" "lib32-libpulse" "lib32-openal" "lib32-mesa" "lib32-vulkan-icd-loader")
    else
        packages+=("radeontop" "corectrl" "lib32-mesa" "lib32-vulkan-radeon" "lib32-vulkan-intel")
    fi
    
    print_status "Installing Gaming packages (${#packages[@]} packages)"
    install_pacman_packages "gaming" "${packages[@]}"

    print_success "Gaming packages installation completed"
}
