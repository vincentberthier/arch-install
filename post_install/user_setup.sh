#!/usr/bin/env bash
# User environment setup

setup_shell_environment() {
    print_status "Setting up shell environment"
    doas mkdir -p /var/lib/AccountsService/icons/
    doas cp ./vincent.png -p "/var/lib/AccountsService/icons/$USER"
    doas chown root:root "/var/lib/AccountsService/icons/$USER"
    doas chmod 644 "/var/lib/AccountsService/icons/$USER"
    
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

setup_duplicacy_config() {
    local folders=("$HOME/code" "$HOME/Documents" "$HOME/Images" "$HOME/.config")
    for folder in "${folders[@]}"; do
        basename=$(basename "$folder")
        # Remove leading dot if present
        basename=${basename#.}
        # Convert to lowercase
        basename=$(echo "$basename" | tr '[:upper:]' '[:lower:]')
        # Append hostname if basename is 'config'
        if [[ "$basename" == "config" ]]; then
            basename="${basename}_$(hostname)"
        fi
        # Append /.duplicacy
        duplicacy_path="${folder}/.duplicacy"

        mkdir -p "$duplicacy_path"
        cat > "${duplicacy_path}/preferences" << DUP_EOF
[
    {
        "name": "default",
        "id": "${basename}",
        "repository": "",
        "storage": $HOME/vault",
        "encrypted": true,
        "no_backup": false,
        "no_restore": false,
        "no_save_password": false,
        "nobackup_file": "",
        "keys": null,
        "filters": "${HOME}/.config/duplicacy/filters.txt",
        "exclude_by_attribute": false
    }
]}
DUP_EOF
    done
}

install_astro_tools() {
    doas pacman -S --noconfirm remmina stellarium darktable
    paru -S --noconfirm graxpert-bin starnet2-bin siril-git
}
