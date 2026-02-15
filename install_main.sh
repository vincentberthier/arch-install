#!/usr/bin/env bash
set -euo pipefail

# Arch Linux Installation Script with Btrfs + Snapper + Limine
# Main installation orchestrator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/disk_setup.sh"
source "${SCRIPT_DIR}/lib/system_install.sh"
source "${SCRIPT_DIR}/lib/system_config.sh"
source "${SCRIPT_DIR}/lib/bootloader.sh"
source "${SCRIPT_DIR}/lib/snapper.sh"
source "${SCRIPT_DIR}/lib/gpu_specific.sh"

# Configuration
HOSTNAME=""
FONT_PASSWD=""
USERNAME="vincent"
USER_EMAIL="vincent.berthier@posteo.org"
TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8"
KEYBOARD="fr"
KEYBOARD_VARIANT="bepo"

# Disk configuration
TARGET_DISK=""
BOOT_SIZE="2G"
ROOT_SIZE="250G"
SWAP_SIZE="16G"

# Subvolume configuration
declare -A SUBVOLS=(
	["@"]="/"
	["@var_log"]="/var/log"
	["@var_cache"]="/var/cache"
	["@var_tmp"]="/var/tmp"
	["@swap"]="/swap"
)

check_uefi() {
	if [[ ! -d /sys/firmware/efi ]]; then
		print_error "This script requires UEFI boot mode"
		exit 1
	fi
	print_success "UEFI boot mode detected"
}

check_internet() {
	if ! ping -c 1 www.google.fr &>/dev/null; then
		print_error "No internet connection"
		exit 1
	fi
	print_success "Internet connection verified"
}

get_user_input() {
	print_status "=== Arch Linux Installation Configuration ==="

	# Hostname
	while [[ -z "$HOSTNAME" ]]; do
		read -rp "Enter hostname: " HOSTNAME
		if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
			print_warning "Invalid hostname. Use only letters, numbers, and hyphens."
			HOSTNAME=""
		fi
	done

	# Font zip password (only ask if font zip is present)
	if [[ -f "${SCRIPT_DIR}/DankMono.zip" || -f "${SCRIPT_DIR}/fonts.zip" ]]; then
		while [[ -z "$FONT_PASSWD" ]]; do
			read -rp "Enter dank mono zip password: " FONT_PASSWD
			if [[ ! "$FONT_PASSWD" =~ ^[a-zA-Z0-9-]+$ ]]; then
				print_warning "Invalid font password. Use only letters, numbers, and hyphens."
				FONT_PASSWD=""
			fi
		done
	else
		print_warning "No font zip found, fonts will be installed post-chezmoi"
	fi

	# Target disk
	echo
	print_status "Available disks:"
	lsblk -d -o NAME,SIZE,TYPE | grep disk
	echo

	while [[ -z "$TARGET_DISK" ]]; do
		read -rp "Enter target disk (e.g., /dev/sda): " TARGET_DISK
		if [[ ! -b "$TARGET_DISK" ]]; then
			print_warning "Invalid disk. Please enter a valid block device."
			TARGET_DISK=""
		fi
	done

	# Confirmation
	echo
	print_warning "=== Configuration Summary ==="
	echo "Hostname: $HOSTNAME"
	echo "Target disk: $TARGET_DISK"
	echo "Root partition: 250GB (for system + snapshots)"
	echo "Home partition: ~750GB (remaining space)"
	echo "Username: $USERNAME"
	echo "Timezone: $TIMEZONE"
	echo "Locale: $LOCALE"
	echo "Keyboard: $KEYBOARD ($KEYBOARD_VARIANT)"
	echo
	print_warning "This will COMPLETELY ERASE $TARGET_DISK"
	read -rp "Continue? (yes/no): " confirm
	if [[ "$confirm" != "yes" ]]; then
		print_error "Installation cancelled"
		exit 1
	fi
}

check_secure_boot() {
	local sb_file
	sb_file="$(compgen -G '/sys/firmware/efi/efivars/SecureBoot-*' | head -1)"
	if [[ -d /sys/firmware/efi/efivars ]] && [[ -n "$sb_file" && -f "$sb_file" ]]; then
		if od -An -t u1 "$sb_file" 2>/dev/null | tr -d ' ' | grep -q 1; then
			print_warning "Secure Boot is currently enabled"
			print_warning "This installation requires Secure Boot to be disabled"
			print_warning "Please disable it in BIOS/UEFI settings before first boot"
		else
			print_success "Secure Boot is disabled - good to go"
		fi
	else
		print_success "Secure Boot check completed"
	fi
}

copy_post_install() {
	print_status "Copying post-install scripts"

	local dest="/mnt/home/${USERNAME}/post_install"
	mkdir -p "${dest}"

	# Copy all post-install related scripts
	for script in "${SCRIPT_DIR}"/post_install/*.sh; do
		if [[ -f "$script" ]]; then
			local script_name
			script_name="$(basename "$script")"
			cp "$script" "${dest}/"
			chmod +x "${dest}/${script_name}"
			print_status "Copied ${script_name}"
		fi
	done

	# Copy user avatar
	if [[ -f "${SCRIPT_DIR}/post_install/vincent.png" ]]; then
		cp "${SCRIPT_DIR}/post_install/vincent.png" "${dest}/"
	fi

	# Copy lib directory for post-install scripts
	if [[ -d "${SCRIPT_DIR}/lib" ]]; then
		cp -r "${SCRIPT_DIR}/lib" "${dest}/"
		print_status "Copied lib directory"
	fi

	if [[ -f "${SCRIPT_DIR}/post_install/main.sh" ]]; then
		print_success "Post-install scripts copied to /home/${USERNAME}/post_install/"
		print_status "Main script: ~/post_install/main.sh"
	else
		print_warning "No post-install scripts found in post_install directory"
	fi
}

main() {
	print_status "=================================================="
	print_status "  Arch Linux Installation with Btrfs + Snapper"
	print_status "=================================================="

	check_uefi
	check_internet
	check_secure_boot
	get_user_input

	# Export variables for use in sourced scripts
	export HOSTNAME USERNAME USER_EMAIL TIMEZONE LOCALE KEYBOARD KEYBOARD_VARIANT
	export TARGET_DISK BOOT_SIZE ROOT_SIZE SWAP_SIZE FONT_PASSWD

	# Detect GPU type early
	detect_gpu_type

	prepare_disk
	format_partitions
	create_subvolumes
	mount_filesystem
	install_base_system
	configure_system
	install_fonts
	configure_openssh
	configure_firewall
	setup_snapper
	install_limine
	copy_post_install

	print_success "Installation completed!"
	echo
	print_success "Next steps:"
	echo "1. Reboot into the new system"
	echo "2. Log in as ${USERNAME}"
	echo "3. Run ~/post_install/main.sh to complete setup"
	echo
	read -rp "Press Enter to reboot or Ctrl+C to stay in live environment..."
	reboot
}

# Run main function
main "$@"
