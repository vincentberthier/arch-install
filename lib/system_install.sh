#!/usr/bin/env bash
# System installation functions

install_base_system() {
	print_status "Installing base system"

	# Refresh keyring on the live ISO before pacstrap: an older ISO ships a
	# stale archlinux-keyring and pacstrap fails with "unknown trust" PGP errors
	# for packages signed by newer packagers.
	print_status "Refreshing archlinux-keyring on live ISO"
	pacman -Sy --noconfirm --needed archlinux-keyring

	# Update mirrors
	# reflector --country France --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

	# Get GPU-specific packages. Every detected vendor gets its stack: on a
	# hybrid laptop, installing only the discrete GPU's driver leaves the
	# integrated one with no userspace at all.
	local -a gpu_packages=()
	local -a lib32_gpu_packages=()

	if gpu_has_vendor nvidia; then
		# Arch dropped the proprietary kernel modules with the 6xx series --
		# nvidia-open-dkms is the only DKMS variant that still exists.
		gpu_packages+=(nvidia-open-dkms nvidia-utils nvidia-settings libva-nvidia-driver)
		lib32_gpu_packages+=(lib32-nvidia-utils)
	fi

	# mesa backs both open stacks; add it once even when both vendors are present.
	if gpu_has_vendor amd || gpu_has_vendor intel; then
		gpu_packages+=(mesa)
		lib32_gpu_packages+=(lib32-mesa)
	fi

	if gpu_has_vendor amd; then
		gpu_packages+=(vulkan-radeon libva-mesa-driver)
		lib32_gpu_packages+=(lib32-vulkan-radeon)
	fi

	if gpu_has_vendor intel; then
		gpu_packages+=(vulkan-intel intel-media-driver)
		lib32_gpu_packages+=(lib32-vulkan-intel)
	fi

	# Install base packages. `rust` is here only so makepkg can build paru in
	# the post-install phase; install_development_packages replaces it with
	# rustup. Never spell it `cargo` -- that is a provides shared by rust and
	# rustup, so pacman stops to ask which one and the run is no longer
	# unattended.
	pacstrap -K /mnt \
		base base-devel linux-zen linux-zen-headers linux-firmware "$CPU_MICROCODE_PKG" \
		btrfs-progs snapper snap-pac \
		networkmanager bluez bluez-utils inetutils \
		git chezmoi fish \
		nano helix \
		man-db man-pages \
		reflector rust sddm \
		ttf-nerd-fonts-symbols-mono ttf-fira-code ttf-jetbrains-mono-nerd \
		"${gpu_packages[@]}" \
		libusb hidapi

	# Only keep linux-zen kernel
	arch-chroot /mnt /bin/bash <<'EOF'
pacman -R linux --noconfirm
# Remove linux preset if it exists
rm -f /etc/mkinitcpio.d/linux.preset

# Remove any stale initramfs files
rm -f /boot/initramfs-linux.img
rm -f /boot/initramfs-linux-fallback.img
rm -f /boot/vmlinuz-linux

# Only keep linux-zen files
ls -la /boot/
EOF

	# Enable multilib in the installed system
	arch-chroot /mnt /bin/bash <<'MULTILIB_EOF'
# We're using linux-zen instead
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Sy
MULTILIB_EOF

	# Now install lib32 packages
	if [[ ${#lib32_gpu_packages[@]} -gt 0 ]]; then
		arch-chroot /mnt pacman -S --noconfirm "${lib32_gpu_packages[@]}"
	fi

	# Add udev rules for ZSA keyboards
	tee /mnt/etc/udev/rules.d/50-zsa.rules <<'ZSA_EOF'
# ZSA Moonlander
SUBSYSTEM=="usb", ATTR{idVendor}=="3297", ATTR{idProduct}=="1969", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="1307", MODE="0666"

# ZSA Planck EZ
SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="6060", MODE="0666"

# ZSA Ergodox EZ (for completeness)
SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="1307", MODE="0666"
ZSA_EOF

	arch-chroot /mnt udevadm control --reload-rules
	arch-chroot /mnt udevadm trigger

	print_success "Base system installed"
}

install_fonts() {
	local font_file=""
	if [[ -f "${SCRIPT_DIR}/DankMono.zip" ]]; then
		font_file="DankMono.zip"
	elif [[ -f "${SCRIPT_DIR}/fonts.zip" ]]; then
		font_file="fonts.zip"
	fi

	if [[ -z "$font_file" ]]; then
		print_warning "No font zip found locally, skipping (run install_fonts.sh after chezmoi)"
		return
	fi

	if [[ -n "$FONT_PASSWD" ]]; then
		print_status "Installing custom fonts from $font_file"

		# Copy to a persistent location, not /tmp
		mkdir -p /mnt/opt/temp
		cp "${SCRIPT_DIR}/${font_file}" /mnt/opt/temp/

		arch-chroot /mnt /bin/bash <<EOF
# Install unzip if not available
pacman -S --noconfirm unzip

# Create temporary directory
mkdir -p /tmp/fonts

# Extract fonts with password from copied zip
unzip -P "$FONT_PASSWD" "/opt/temp/$font_file" "*.otf" -d /tmp/fonts/ 2>/dev/null || {
    echo "Failed to extract fonts or no .otf files found"
    exit 1
}

# Install fonts system-wide
mkdir -p /usr/share/fonts/custom
find /tmp/fonts -name "*.otf" -exec cp {} /usr/share/fonts/custom/ \;

# Update font cache
fc-cache -fv

# Cleanup
rm -rf /tmp/fonts "/opt/temp/$font_file"
rmdir /opt/temp 2>/dev/null || true

EOF

		print_success "Custom fonts installed system-wide"
	else
		print_warning "No font password set or font file not found, skipping font installation"
	fi
}
