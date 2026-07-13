#!/usr/bin/env bash
# User environment setup

setup_shell_environment() {
	print_status "Setting up shell environment"
	doas mkdir -p /var/lib/AccountsService/icons/
	doas cp "${SCRIPT_DIR}/vincent.png" -p "/var/lib/AccountsService/icons/$USER"
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
	cat >/tmp/install_fish_plugins.fish <<'FISH_SCRIPT_EOF'
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

# Repository setup moved to ~/.local/bin/duplicacy-setup (chezmoi-managed) and
# is invoked from setup_duplicacy in system_setup.sh. Hand-writing preferences
# here is what silently dropped the second, local storage during the 2025
# rebuild: the generated file only ever described the pcloud vault.

install_astro_tools() {
	install_pacman_packages "astro" remmina stellarium darktable tk
	install_aur_packages "astro" graxpert-bin starnet2-bin siril-git
}
