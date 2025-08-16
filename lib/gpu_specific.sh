#!/usr/bin/env bash
# GPU-specific configuration functions

configure_nvidia_system() {
    print_status "Applying Nvidia-specific system configuration"
    
    arch-chroot /mnt /bin/bash << 'EOF'
echo "Configuring Nvidia drivers..."

# Add Nvidia modules to mkinitcpio
sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkdir -p /etc/modprobe.d
echo "options nvidia-drm modeset=1" | tee /etc/modprobe.d/nvidia-drm.conf

# Regenerate initramfs
mkinitcpio -P

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
    
    # Create environment file for Nvidia Wayland
    doas tee /etc/environment << 'ENV_EOF'
# Nvidia Wayland support
LIBVA_DRIVER_NAME=nvidia
XDG_SESSION_TYPE=wayland
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
NVIDIA_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
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
