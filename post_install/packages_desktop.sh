#!/usr/bin/env bash
# Desktop environment packages

install_desktop_packages() {
	local packages=(
		# Niri compositor stack
		"niri" "fuzzel" "xwayland-satellite" "cliphist" "wlsunset" "mako" "cava"
		"xdg-desktop-portal" "xdg-desktop-portal-gnome"
		"wl-clipboard" "wtype" "grim" "slurp" "labwc"
		"qt5-graphicaleffects" "qt5-svg" "qt5-quickcontrols2"
		"thunar" "thunar-volman" "gvfs" "gvfs-mtp" "gvfs-smb"

		# Plasma desktop (fallback)
		"plasma-meta" "kde-applications-meta"
		"xdg-desktop-portal-kde"

		# Applications
		"thunderbird" "discord" "signal-desktop" "telegram-desktop" "element-desktop"
		"libreoffice-fresh" "obsidian" "qbittorrent" "gwenview" "zathura" "okular"
		"mpv" "vlc" "gimp" "gimp-plugin-gmic"
	)

	print_status "Installing Desktop packages (${#packages[@]} packages)"
	install_pacman_packages "desktop" "${packages[@]}"

	# Desktop AUR packages
	local aur_packages=(
		"zen-browser-bin"             # Primary browser
		"wl-screenrec"                # Screen record for Wayland
		"webcord"                     # Discord alternative
		"sddm-theme-corners-git"      # SDDM theme
		"limine-snapper-sync"         # Boot on snapshots
		"limine-entry-tool"           # Limine sync helpers
		"wleave-git"                  # Logout utils
		"bibata-cursor-theme-bin"     # Cursor theme
		"gimp-plugin-resynthesizer"   # GIMP plugin
		"matugen-git"                 # Material You color generation
		"noctalia-shell"              # Niri theme integration
		"brave-bin"                   # Fallback browser
		"onedrive-abraunegg"          # OneDrive sync backend
		"whisper.cpp-vulkan"          # Speech-to-text (Vulkan GPU)
		"whisper.cpp-model-medium.en" # Whisper medium English model
	)

	install_aur_packages "desktop" "${aur_packages[@]}"

	# Enable limine-snapper-sync service
	enable_service "desktop" system limine-snapper-sync.service --now || true

	# Install problematic AUR packages with PGP issues
	install_pgp_messed_up_packages

	# Add zen-browser to 1password integrations
	doas mkdir -p /etc/1password
	echo "zen-bin" | doas tee -a /etc/1password/custom_allowed_browsers

	print_success "Desktop packages installation completed"
}

install_pgp_messed_up_packages() {
	print_status "Installing AUR packages with PGP issues"

	local problematic_packages=("1password" "1password-cli")

	for package in "${problematic_packages[@]}"; do
		print_status "Installing $package"
		if paru -S --noconfirm "$package"; then
			continue
		fi
		print_warning "Normal install failed for $package, retrying with --skippgpcheck"
		if ! paru -S --noconfirm --mflags="--skippgpcheck" "$package"; then
			record_failure "desktop-pgp (AUR)" "$package" "install failed even with --skippgpcheck"
		fi
	done

	if ! paru -S --noconfirm --mflags="--nocheck" wezterm-git; then
		record_failure "desktop-pgp (AUR)" "wezterm-git" "install failed with --nocheck"
	fi

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

	doas tee /etc/sddm.conf.d/wayland.conf <<SDDM_EOF
[General]
DisplayServer=wayland
${sddm_gpu}

[Theme]
Current=corners

[Wayland]
CompositorCommand=/usr/local/bin/sddm-labwc
SessionDir=/usr/share/wayland-sessions
SDDM_EOF

	doas tee /usr/share/sddm/themes/corners/theme.conf.user <<'SDDM_EOF'
BgSource="backgrounds/glacier.png"
FontFamily="Dank Mono"
FontSize=9
Padding=50
Radius=10
Scale=1

DateTimeSpacing=0
SDDM_EOF

	# Use the Plasma Wayland compositor directly
	doas tee /usr/local/bin/sddm-labwc <<'EOF'
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
