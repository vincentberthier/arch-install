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

	print_success "paru installed"
}

install_core_packages() {
	local packages=(
		# Essential system
		"pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack" "wireplumber"

		# Essential CLI tools
		"starship" "eza" "bat" "fd" "ripgrep" "sd" "dust" "duf" "btop" "zoxide" "fzf"
		"git" "difftastic" "meld" "git-delta" "github-cli"
		"tree" "unzip" "wget" "curl" "rsync" "sshfs" "fastfetch" "tldr"
		"yazi" "rclone" "tinyxxd" "chafa" "patchelf" "xclip"

		# Safe rm replacement. trash-cli, not trashy: the verbs are separate
		# binaries (trash-put, trash-restore, trash-list) and that is what the
		# shell aliases and the documented workflow expect.
		"trash-cli"

		# Shell tooling
		"shellcheck" "shfmt" "dprint"

		# Security and keys
		"keychain" "gnupg" "pass" "age" "yara"

		# Backup
		"borg" "restic"

		# Documents and text
		"typst" "pandoc-cli"

		# Terminal
		"kitty"

		# Audio/video
		"playerctl" "pavucontrol"

		# Bluetooth
		"blueman"

		# Filesystem utilities
		"dosfstools" "ntfs-3g" "xfsprogs"

		# Networking / sysadmin
		"nmap" "iperf3" "sshpass" "screen" "waypipe" "tcpdump" "wireshark-cli"

		# Filesystem support beyond the basics
		"exfatprogs"
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
		"watchman-bin"  # Inotify-like
		"bluetuith-bin" # TUI bluetooth manager
		"anydesk-bin"   # Remote desktop
		"hadolint-bin"  # Dockerfile linter
		"scc-bin"       # Source code line counter

		# ZSA keyboard flasher. Must go through install_aur_packages: it was a
		# bare `paru -S` call, and when upstream dropped the package the
		# non-zero exit took the whole post-install down with it under set -e.
		"zsa-wally-cli-git"
	)

	install_aur_packages "core" "${aur_packages[@]}"

	print_success "Core packages installation completed"
}

# Power management and firmware tooling for portables. Gated on is_laptop, not
# on a hostname list, so a new machine gets it without editing this file.
#
# power-profiles-daemon rather than tlp: the two conflict, and it is the one
# the desktop shell's power widget talks to over D-Bus.
install_laptop_packages() {
	print_status "Installing laptop power-management packages"

	local packages=(
		"power-profiles-daemon" # Balanced/performance/saver profiles over D-Bus
		"upower"                # Battery state for the shell
		"acpi"                  # Battery and thermal state from the CLI
		"powertop"              # Power draw diagnostics
		"fwupd"                 # Firmware updates (LVFS)
		"brightnessctl"         # Backlight control for the niri binds
	)

	# thermald only understands Intel's thermal interfaces.
	if [[ "$CPU_VENDOR" == "intel" ]]; then
		packages+=("thermald")
	fi

	# Hands the compositor a way to pick which GPU an application runs on.
	if ((${#GPU_VENDORS[@]} > 1)); then
		print_status "Hybrid graphics detected, adding switcheroo-control"
		packages+=("switcheroo-control")
	fi

	install_pacman_packages "laptop" "${packages[@]}"

	enable_service "laptop" system power-profiles-daemon.service --now || true
	enable_service "laptop" system fwupd.service || true
	if [[ "$CPU_VENDOR" == "intel" ]]; then
		enable_service "laptop" system thermald.service --now || true
	fi
	if ((${#GPU_VENDORS[@]} > 1)); then
		enable_service "laptop" system switcheroo-control.service --now || true
	fi

	print_success "Laptop packages installation completed"
}
