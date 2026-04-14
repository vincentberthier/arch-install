#!/usr/bin/env bash
# Core packages installation - essential for all systems

update_system() {
	print_status "Updating system packages"
	doas pacman -Syu --noconfirm
	print_success "System updated"
}

install_paru() {
	# Verify paru not only exists but actually runs. The pre-compiled binary
	# from upstream GitHub releases is frequently out of sync with Arch's
	# libalpm soname (.so.15 vs .so.16), so a stale install can be "present"
	# but broken after `pacman -Syu`.
	if command -v paru &>/dev/null && paru --version &>/dev/null; then
		print_success "paru already installed"
		return
	fi

	if command -v paru &>/dev/null; then
		print_warning "paru is installed but not runnable (likely libalpm soname mismatch); rebuilding"
		doas rm -f /usr/local/bin/paru
		doas pacman -Rns --noconfirm paru paru-bin 2>/dev/null || true
	fi

	print_status "Building paru from the AUR against the current libalpm"

	local build_dir
	build_dir="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '${build_dir}'" RETURN

	git clone --depth 1 https://aur.archlinux.org/paru.git "${build_dir}/paru"
	(
		cd "${build_dir}/paru" || exit 1
		makepkg -si --noconfirm --needed
	)

	# pacman installs paru to /usr/bin/paru, replacing any /usr/local/bin/paru
	# that bash may have cached earlier in this function via command -v. Drop
	# the hash table so the next invocation resolves the new path.
	hash -r

	if ! command -v paru &>/dev/null; then
		print_error "paru build failed"
		exit 1
	fi

	paru -Sy --noconfirm zsa-wally-cli

	print_success "paru installed"
}

install_core_packages() {
	local packages=(
		# Essential system
		"pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack" "wireplumber"

		# Essential CLI tools
		"starship" "eza" "bat" "fd" "ripgrep" "sd" "dust" "duf" "btop" "zoxide" "fzf"
		"git" "difftastic" "meld" "git-delta"
		"tree" "unzip" "wget" "curl" "rsync" "fastfetch" "tldr"
		"yazi" "rclone" "tinyxxd"

		# Shell tooling
		"shellcheck" "shfmt"

		# Security and keys
		"keychain" "gnupg" "pass"

		# Terminal
		"kitty"

		# Audio/video
		"playerctl" "pavucontrol"

		# Bluetooth
		"blueman"

		# Filesystem utilities
		"dosfstools" "ntfs-3g" "xfsprogs"

		# Networking / sysadmin
		"nmap" "iperf3" "sshpass" "screen" "waypipe"
	)

	# Add GPU-specific core packages
	if [[ "$GPU_TYPE" == "nvidia" ]]; then
		# Already installed during base install, but ensure they're there
		packages+=("nvidia-utils" "nvidia-settings")
	else
		packages+=("mesa" "lib32-mesa" "vulkan-radeon" "lib32-vulkan-radeon")
	fi

	print_status "Installing Core packages (${#packages[@]} packages)"
	install_pacman_packages "core" "${packages[@]}"

	bat cache --build

	# Install essential AUR packages
	local aur_packages=(
		"yay"           # AUR helper (fallback)
		"dprint-bin"    # Formatter
		"watchman-bin"  # Inotify-like
		"bluetuith-bin" # TUI bluetooth manager
		"anydesk-bin"   # Remote desktop
		"trashy-bin"    # Safe rm replacement
	)

	install_aur_packages "core" "${aur_packages[@]}"

	print_success "Core packages installation completed"
}
