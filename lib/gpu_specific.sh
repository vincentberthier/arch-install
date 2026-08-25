#!/usr/bin/env bash
# GPU-specific configuration functions

configure_nvidia_system() {
	print_status "Applying Nvidia-specific system configuration"

	# The initramfs MODULES list and the mkinitcpio run live in
	# configure_initramfs, which owns /etc/mkinitcpio.conf.d and runs after
	# this function.
	arch-chroot /mnt /bin/bash <<'EOF'
echo "Configuring Nvidia drivers..."

mkdir -p /etc/modprobe.d
echo "options nvidia-drm modeset=1" | tee /etc/modprobe.d/nvidia-drm.conf

# Create Nvidia udev rules
echo 'ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="/usr/bin/nvidia-modprobe -c0 -u"' > /etc/udev/rules.d/70-nvidia.rules

# Enable nvidia-persistenced
systemctl disable nvidia-persistenced
systemctl mask nvidia-persistenced
EOF

	print_success "Nvidia-specific configuration applied"
}

setup_nvidia_environment() {
	print_status "Setting up Nvidia environment variables"

	# Append, never overwrite: configure_system already wrote the bepo XKB
	# defaults into /etc/environment during the base install, and a plain
	# `tee` here would silently drop them and leave the machine on a QWERTY
	# layout. The marker keeps re-runs of the post-install idempotent.
	local marker="# >>> nvidia wayland (arch-install) >>>"

	if doas grep -qF "$marker" /etc/environment 2>/dev/null; then
		print_status "Nvidia environment block already present, leaving it alone"
		return
	fi

	doas tee -a /etc/environment >/dev/null <<ENV_EOF
${marker}
LIBVA_DRIVER_NAME=nvidia
XDG_SESSION_TYPE=wayland
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
NVIDIA_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
# <<< nvidia wayland (arch-install) <<<
ENV_EOF

	print_success "Nvidia environment configured"
}

get_nvidia_sddm_config() {
	echo "GreeterEnvironment=QT_QPA_PLATFORM=wayland,GBM_BACKEND=nvidia-drm,__GLX_VENDOR_LIBRARY_NAME=nvidia"
}

get_nvidia_kernel_params() {
	echo "nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
}

get_amd_kernel_params() {
	echo "rd.systemd.show_status=auto rd.udev.log_level=3"
}
