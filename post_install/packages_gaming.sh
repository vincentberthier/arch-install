#!/usr/bin/env bash
# Gaming packages installation

install_gaming_packages() {
    local packages=(
        # Gaming
        "gamemode" "lib32-gamemode" "mangohud" "lib32-mangohud"
        "steam" "lutris" "wine-staging"
    )
    
    # Add GPU-specific gaming tools
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        packages+=("nvidia-utils" "lib32-nvidia-utils")
    else
        packages+=("radeontop" "corectrl")
    fi
    
    print_status "Installing Gaming packages (${#packages[@]} packages)"
    
    # Split into chunks
    local chunk_size=20
    for ((i=0; i<${#packages[@]}; i+=chunk_size)); do
        local chunk=("${packages[@]:i:chunk_size}")
        print_status "Installing chunk: ${chunk[*]}"
        
        if ! doas pacman -S --needed --noconfirm "${chunk[@]}"; then
            print_warning "Some packages in chunk failed to install, continuing..."
        fi
    done
    
    print_success "Gaming packages installation completed"
}
