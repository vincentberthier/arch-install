#!/usr/bin/env bash
# User environment setup

setup_shell_environment() {
    print_status "Setting up shell environment"
    
    # Install Fisher
    install_fisher
    
    # Install Fish plugins
    install_fish_plugins
    
    print_success "Shell environment configured"
}

install_fisher() {
    print_status "Installing Fisher (Fish plugin manager)"
    
    # Ensure fish config directory exists
    mkdir -p ~/.config/fish/functions
    
    # Download and install Fisher
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish -o ~/.config/fish/functions/fisher.fish
    
    # Make it executable
    chmod +x ~/.config/fish/functions/fisher.fish
    
    print_success "Fisher installed"
}

install_fish_plugins() {
    print_status "Installing Fish plugins"
    
    # Create a fish script to install plugins
    cat > /tmp/install_fish_plugins.fish << 'FISH_SCRIPT_EOF'
#!/usr/bin/env fish

# Install Fisher plugins
fisher install jorgebucaran/autopair.fish
fisher install PatrickF1/fzf.fish
fisher install franciscolourenco/done
fisher install mattgreen/lucid.fish
fisher install jorgebucaran/replay.fish
fisher install gazorby/fish-abbreviation-tips
fisher install jethrokuan/z
FISH_SCRIPT_EOF

    # Run the script with fish
    fish /tmp/install_fish_plugins.fish
    
    # Clean up
    rm /tmp/install_fish_plugins.fish
    
    print_success "Fish plugins installed"
}
