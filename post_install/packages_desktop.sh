#!/usr/bin/env bash
# Desktop environment packages

install_desktop_packages() {
	local packages=(
		# Niri compositor stack
		"niri" "fuzzel" "xwayland-satellite" "cliphist" "wlsunset"
		"xdg-desktop-portal" "xdg-desktop-portal-gnome"
		"wl-clipboard" "wtype" "grim" "slurp" "labwc"
		# Were transitive deps of noctalia-shell; noctalia v5 does not pull them in.
		# brightnessctl backs the niri XF86MonBrightness binds, wlr-randr the screen-off.
		"brightnessctl" "wlr-randr"
		"qt5-graphicaleffects" "qt5-svg" "qt5-quickcontrols2"
		"thunar" "thunar-volman" "gvfs" "gvfs-mtp" "gvfs-smb"

		# Dank Mono and the nerd fonts have no CJK coverage: kanji/kana/hanzi
		# render as placeholder boxes in wezterm and in notification bodies.
		"noto-fonts-cjk"

		# Plasma desktop (fallback)
		"plasma-meta" "kde-applications-meta"
		"xdg-desktop-portal-kde"

		# Applications
		"thunderbird" "discord" "signal-desktop" "telegram-desktop" "element-desktop"
		"libreoffice-fresh" "obsidian" "qbittorrent" "gwenview" "zathura" "okular"
		"mpv" "vlc" "gimp" "gimp-plugin-gmic"

		# mDNS: resolves <hostname>.local across the LAN without DNS entries.
		"avahi" "nss-mdns"

		# Speech-to-text. Was whisper.cpp-vulkan from the AUR; that package is
		# gone and whisper-cpp is in extra at the same upstream version.
		"whisper-cpp"
	)

	print_status "Installing Desktop packages (${#packages[@]} packages)"
	install_pacman_packages "desktop" "${packages[@]}"

	# Desktop AUR packages
	local aur_packages=(
		"zen-browser-bin"             # Primary browser
		"wl-screenrec-git"            # Screen record for Wayland (git tracks newer ffmpeg)
		"webcord"                     # Discord alternative
		"sddm-theme-corners-git"      # SDDM theme
		"limine-snapper-sync"         # Boot on snapshots
		"limine-entry-tool"           # Limine sync helpers
		"wleave-git"                  # Logout utils
		"bibata-cursor-theme-bin"     # Cursor theme
		"gimp-plugin-resynthesizer"   # GIMP plugin
		"noctalia-git"                # Niri shell/bar (v5; config is TOML via chezmoi)
		"brave-bin"                   # Fallback browser
		"onedrive-abraunegg"          # OneDrive sync backend
		"whisper.cpp-model-medium.en" # Whisper medium English model
	)

	install_aur_packages "desktop" "${aur_packages[@]}"

	# Tune and enable limine-snapper-sync now that the package -- and the
	# config file it owns -- actually exist.
	configure_limine_snapper_sync
	enable_service "desktop" system limine-snapper-sync.service --now || true

	# avahi resolves <hostname>.local across the LAN
	enable_service "desktop" system avahi-daemon.service --now || true

	# Install problematic AUR packages with PGP issues
	install_pgp_messed_up_packages

	# Add zen-browser to 1password integrations
	doas mkdir -p /etc/1password
	echo "zen-bin" | doas tee -a /etc/1password/custom_allowed_browsers

	print_success "Desktop packages installation completed"
}

# Set a key in the limine-snapper-sync config the package ships, replacing an
# existing assignment (commented or not) or appending when the key is absent.
# The file must not be created ahead of the package -- see lib/bootloader.sh.
configure_limine_snapper_sync() {
	local conf="/etc/limine-snapper-sync.conf"
	local key="LIMIT_USAGE_PERCENT"
	# The package default. limine-snapper-sync keeps a full kernel and
	# initramfs per snapshot under limine_history, so letting it fill the ESP
	# to 99% leaves no room for the next mkinitcpio run to land.
	local value="85"

	if [[ ! -f "$conf" ]]; then
		record_failure "desktop" "limine-snapper-sync" "${conf} missing, package not installed"
		return 1
	fi

	print_status "Setting ${key}=${value} in ${conf}"
	if grep -Eq "^#?\s*${key}=" "$conf"; then
		doas sed -i -E "s|^#?\s*${key}=.*|${key}=${value}|" "$conf"
	else
		echo "${key}=${value}" | doas tee -a "$conf" >/dev/null
	fi
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

	# Greeter compositor. The layout order matches the installed system's --
	# both come from detect_keyboard_layout -- so the password typed at the
	# greeter uses the same keys as the one set on the machine.
	doas tee /usr/local/bin/sddm-labwc <<EOF
#!/usr/bin/env bash

export XKB_DEFAULT_LAYOUT="${KEYBOARD_LAYOUTS}"
export XKB_DEFAULT_VARIANT="${KEYBOARD_VARIANTS}"
export XKB_DEFAULT_OPTIONS="${KEYBOARD_OPTIONS}"
exec labwc
EOF
	doas chmod +x /usr/local/bin/sddm-labwc

	# Enable SDDM now that desktop environments are installed
	doas systemctl enable sddm

	print_success "SDDM configured and enabled"
}
