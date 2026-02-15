# Arch Linux Installation Scripts

Modular Bash scripts that automate a full Arch Linux install and post-install
setup. Personal configuration, not a general-purpose framework.

## Highlights

| Component        | Choice                                              |
|------------------|-----------------------------------------------------|
| Filesystem       | Btrfs with subvolumes (`@`, `@var_log`, etc.)       |
| Snapshots        | Snapper with automatic timeline + numbered retention |
| Bootloader       | Limine (synced with snapper via limine-snapper-sync) |
| Kernel           | linux-zen                                           |
| Compositor       | Niri (scrollable tiling) + Noctalia shell           |
| Desktop fallback | KDE Plasma                                          |
| Display manager  | SDDM (Wayland via labwc greeter)                    |
| Shell            | Fish (with Fisher plugin manager)                   |
| Dotfiles         | chezmoi                                             |
| Privilege        | doas (sudo only for snapper/pacman wrappers)        |
| Firewall         | nftables (drop policy, Steam ports open)            |
| GPU              | Auto-detected: Nvidia (proprietary) or AMD (mesa)   |
| AUR helpers      | paru (primary), yay (fallback)                      |
| Backup           | Duplicacy to local vault with systemd timers        |

## Hosts

| Hostname     | Desktop | Development | Gaming | Embedded | Astro |
|--------------|---------|-------------|--------|----------|-------|
| `athena`     | yes     | yes         | yes    | no       | no    |
| `gaia`       | yes     | yes         | yes    | yes      | yes   |
| `hephaistos` | yes     | yes         | no     | no       | no    |

## Installation

### Phase 1: Base install (live ISO, as root)

```bash
# Boot the Arch Linux live ISO, then:
git clone https://github.com/vincentberthier/arch-install.git
cd arch-install
chmod +x install_main.sh
./install_main.sh
```

The script prompts for hostname, target disk, and (if a font zip is present)
the font archive password. It then partitions, formats, pacstraps, configures,
and installs the bootloader. Reboot when done.

### Phase 2: Post-install (installed system, as user)

```bash
cd ~/post_install
./main.sh
```

Installs packages by category, sets up systemd services, configures the shell
environment, and prints remaining manual steps (1Password, chezmoi, fonts).

### Phase 3: After chezmoi

```bash
chezmoi init https://github.com/vincentberthier/dotfiles.git
chezmoi apply
# Run twice if needed (some templates depend on first-pass files)
chezmoi apply

# Install custom fonts (requires SSH keys from chezmoi)
~/post_install/install_fonts.sh
```

## Directory Structure

```
.
├── install_main.sh              # Phase 1 orchestrator (live ISO, root)
├── lib/
│   ├── common.sh                # Logging, host checks, GPU detection
│   ├── disk_setup.sh            # GPT partitioning, btrfs, subvolumes
│   ├── system_install.sh        # pacstrap, GPU drivers, fonts
│   ├── system_config.sh         # Locale, user, doas, SSH, firewall
│   ├── bootloader.sh            # Limine install and config
│   ├── snapper.sh               # Snapper snapshot config
│   └── gpu_specific.sh          # Nvidia/AMD kernel params and env
├── post_install/
│   ├── main.sh                  # Phase 2 orchestrator (user)
│   ├── packages_core.sh         # CLI tools, audio, terminals
│   ├── packages_desktop.sh      # Niri, KDE, apps, SDDM
│   ├── packages_development.sh  # Rust, C++, Python, LaTeX, LSPs
│   ├── packages_gaming.sh       # Steam, Lutris, Wine, MangoHUD
│   ├── system_setup.sh          # Directories, systemd, duplicacy, VMs
│   ├── user_setup.sh            # Fish plugins, duplicacy config, astro
│   ├── install_fonts.sh         # Post-chezmoi font installer
│   └── vincent.png              # User avatar
└── arch_wallpaper.png           # Limine boot wallpaper
```

Library files define functions only -- the orchestrators source them and call
functions in order.

## Prerequisites

- UEFI boot mode (Secure Boot disabled)
- Internet connection
- 1 TB+ disk recommended (2 GB boot, 250 GB root, remainder home)

## Defaults

| Setting  | Value            |
|----------|------------------|
| User     | `vincent`        |
| Timezone | `Europe/Paris`   |
| Locale   | `fr_FR.UTF-8`   |
| Keyboard | French BEPO      |
