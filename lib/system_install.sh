#!/usr/bin/env bash
# System installation functions

install_base_system() {
	print_status "Installing base system"

	# Update mirrors
	# reflector --country France --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

	# Get GPU-specific packages
	local -a gpu_packages
	local -a lib32_gpu_packages
	local microcode

	if [[ "$GPU_TYPE" == "nvidia" ]]; then
		gpu_packages=(nvidia-dkms nvidia-utils nvidia-settings)
		lib32_gpu_packages=(lib32-nvidia-utils)
		microcode="intel-ucode"
	else
		gpu_packages=(mesa vulkan-radeon xf86-video-amdgpu)
		lib32_gpu_packages=(lib32-mesa lib32-vulkan-radeon)
		microcode="amd-ucode"
	fi

	# Install base packages
	pacstrap -K /mnt \
		base base-devel linux-zen linux-zen-headers linux-firmware "$microcode" \
		btrfs-progs snapper snap-pac \
		networkmanager bluez bluez-utils inetutils \
		git chezmoi fish \
		nano helix \
		man-db man-pages \
		reflector cargo sddm \
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
