# Arch Linux Installation Scripts

Modular Arch Linux installation scripts with Btrfs, Snapper, and Limine bootloader.

## Directory Structure

```
.
├── arch_install_main.sh        # Main installation script
├── lib/                        # Shared library functions
│   ├── common.sh               # Common functions and utilities
│   ├── disk_setup.sh           # Disk partitioning and formatting
│   ├── system_install.sh       # Base system installation
│   ├── system_config.sh        # System configuration
│   ├── gpu_specific.sh         # GPU-specific configurations
│   ├── bootloader.sh           # Bootloader installation
│   └── snapper.sh              # Snapper configuration
└── post_install/               # Post-installation scripts
    ├── main.sh                 # Post-install orchestrator
    ├── packages_core.sh        # Core packages
    ├── packages_desktop.sh     # Desktop environment packages
    ├── packages_development.sh # Development tools
    ├── packages_gaming.sh      # Gaming packages
    ├── system_setup.sh         # System configuration
    ├── user_setup.sh           # User environment setup
    └── lib/                    # Copy of lib for post-install
        ├── common.sh
        └── gpu_specific.sh
```

## Usage

### Base Installation

1. Boot into Arch Linux live ISO
2. Place all scripts in the same directory structure
3. Make the main script executable:
   ```bash
   chmod +x arch_install_main.sh
   ```
4. Run the installation:
   ```bash
   ./arch_install_main.sh
   ```

### Post-Installation

After rebooting into the new system:

1. Log in as your user
2. Navigate to the post_install directory:
   ```bash
   cd ~/post_install
   ```
3. Run the post-installation script:
   ```bash
   ./main.sh
   ```

## Host-Specific Configuration

The scripts support hostname-based configuration. You can control which packages and features are installed on specific hosts using the `should_run_for_host` function.

### Example Hostnames

Configure your system with one of these hostnames to get specific setups:

- `workstation` - Full desktop with development and gaming
- `laptop` - Desktop and development, no gaming
- `desktop` - Desktop and gaming, limited development
- `server` - Core packages only, no desktop

### Customizing for Your Hosts

Edit `post_install/main.sh` to customize which features are installed on which hosts:

```bash
# Example: only install on specific hosts
if should_run_for_host "$HOSTNAME" "workstation" "laptop"; then
    install_development_packages
fi
```

## GPU Detection

The scripts automatically detect GPU type (Nvidia or AMD) and install appropriate drivers and configurations:

- **Nvidia**: Installs proprietary drivers, configures Wayland support
- **AMD**: Installs open-source drivers, enables AMD-specific tools

## Features

### Base Installation
- UEFI boot mode with Limine bootloader
- Btrfs filesystem with subvolumes
- Snapper for automatic snapshots
- Separate /home partition (~750GB)
- Automatic GPU detection and driver installation
- SSH enabled for remote access
- Custom font installation (Dank Mono)

### Post-Installation
- Modular package installation by category
- Host-specific configurations
- GPU-specific optimizations
- Shell environment (Fish with plugins)
- Display manager (SDDM) with Wayland
- Development tools
- Gaming support (Steam, Lutris, Wine)
- Automatic daily updates via systemd

## Customization

### Adding New Hosts

1. Choose a hostname during installation
2. Edit post-install scripts to add host-specific logic:
   ```bash
   if should_run_for_host "$HOSTNAME" "my-new-host"; then
       # Custom configuration
   fi
   ```

### Adding New Packages

Add packages to the appropriate array in the post_install scripts:
- Core packages: `post_install/packages_core.sh`
- Desktop packages: `post_install/packages_desktop.sh`
- Development packages: `post_install/packages_development.sh`
- Gaming packages: `post_install/packages_gaming.sh`

### Modifying GPU-Specific Behavior

GPU-specific functions are in `lib/gpu_specific.sh`:
- `configure_nvidia_system()` - Nvidia system configuration
- `setup_nvidia_environment()` - Nvidia environment variables
- `get_nvidia_kernel_params()` - Nvidia kernel parameters
- `get_amd_kernel_params()` - AMD kernel parameters

## Script Functions

### Common Functions (`lib/common.sh`)
- `print_status()`, `print_success()`, `print_warning()`, `print_error()` - Colored output
- `should_run_for_host()` - Check if script should run for current hostname
- `detect_gpu_type()` - Detect GPU manufacturer

### Installation Process

1. **Disk Setup** (`lib/disk_setup.sh`)
   - Partition disk (EFI, root, home)
   - Format with Btrfs
   - Create subvolumes
   - Mount filesystem

2. **System Installation** (`lib/system_install.sh`)
   - Install base packages
   - Install GPU drivers
   - Install custom fonts

3. **System Configuration** (`lib/system_config.sh`)
   - Configure locale, timezone, keyboard
   - Create user
   - Setup doas/sudo
   - Configure SSH

4. **Bootloader** (`lib/bootloader.sh`)
   - Install Limine
   - Configure with GPU-specific parameters

5. **Snapper** (`lib/snapper.sh`)
   - Configure automatic snapshots
   - Set retention policies

## Requirements

- UEFI boot mode
- 1TB+ disk recommended (250GB root + 750GB home)
- Internet connection
- Arch Linux live ISO

## Notes

- Default username: `vincent` (change in `arch_install_main.sh`)
- Default timezone: `Europe/Paris`
- Default locale: `fr_FR.UTF-8`
- Default keyboard: French BÉPO
- Secure Boot must be disabled

## Troubleshooting

### Installation Fails
- Check internet connection
- Verify UEFI boot mode
- Ensure Secure Boot is disabled

### Post-Install Script Fails
- Run as regular user, not root
- Check that all lib files were copied
- Verify hostname matches expected values

### GPU Issues
- Nvidia: May need to disable Secure Boot
- AMD: Should work out of the box
- Check `lspci | grep -i vga` to verify GPU detection

## License

These scripts are provided as-is for personal use.
