#!/usr/bin/env bash
# Desktop environment packages

install_desktop_packages() {
	local packages=(
		# Niri compositor stack
		"niri" "fuzzel" "xwayland-satellite" "cliphist" "wlsunset" "mako" "cava"
		"xdg-desktop-portal" "xdg-desktop-portal-gnome"
		"wl-clipboard" "wtype" "grim" "slurp" "labwc"
		"qt5-graphicaleffects" "qt5-svg" "qt5-quickcontrols2"
		"thunar" "thunar-volman" "gvfs" "gvfs-mtp" "gvfs-smb"

		# Plasma desktop (fallback)
		"plasma-meta" "kde-applications-meta"
		"xdg-desktop-portal-kde"

		# Applications
		"thunderbird" "discord" "signal-desktop" "telegram-desktop" "element-desktop"
		"libreoffice-fresh" "obsidian" "qbittorrent" "gwenview" "zathura" "okular"
		"mpv" "vlc" "gimp" "gimp-plugin-gmic"

		# mDNS stack for Sunshine discovery
		"avahi" "nss-mdns"
	)

	# Sunshine/Moonlight split: hephaistos hosts the stream (sunshine from AUR),
	# every other desktop is a client (moonlight-qt + wakeonlan).
	if should_run_for_host "$HOSTNAME" "hephaistos"; then
		packages+=("seatd")
	else
		packages+=("moonlight-qt" "wakeonlan")
	fi

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
		"matugen-git"                 # Material You color generation
		"noctalia"                    # Noctalia CLI launcher (`noctalia run`)
		"noctalia-shell"              # Niri theme integration (Quickshell config)
		"brave-bin"                   # Fallback browser
		"onedrive-abraunegg"          # OneDrive sync backend
		"whisper.cpp-vulkan"          # Speech-to-text (Vulkan GPU)
		"whisper.cpp-model-medium.en" # Whisper medium English model
		"sunshine"                    # Game-streaming host for Moonlight
	)

	install_aur_packages "desktop" "${aur_packages[@]}"

	# Enable limine-snapper-sync service
	enable_service "desktop" system limine-snapper-sync.service --now || true

	# avahi for Sunshine/Moonlight mDNS discovery
	enable_service "desktop" system avahi-daemon.service --now || true

	# Sunshine streaming host setup (hephaistos) vs Moonlight client setup
	# (everyone else). Host boots headless to a TTY, is woken via WOL, and
	# starts niri+sunshine on demand via an SSH-triggered helper. Clients
	# get a wrapper script + fuzzel-visible desktop entry to drive it.
	if should_run_for_host "$HOSTNAME" "hephaistos"; then
		setup_streaming_host
	else
		setup_streaming_client
	fi

	# Install problematic AUR packages with PGP issues
	install_pgp_messed_up_packages

	# Add zen-browser to 1password integrations
	doas mkdir -p /etc/1password
	echo "zen-bin" | doas tee -a /etc/1password/custom_allowed_browsers

	print_success "Desktop packages installation completed"
}

setup_streaming_host() {
	print_status "Setting up Sunshine streaming host (hephaistos)"

	# Sunshine itself is an AUR build.
	install_aur_packages "streaming-host" sunshine

	# seatd mediates DRM/input access without a logind graphical session, so
	# niri started from an SSH shell can grab the GPU. vincent must be in the
	# seat group for seatd's socket to be usable.
	enable_service "streaming-host" system seatd.service --now || true
	doas usermod -a -G seat "$USER"

	# Sunshine injects remote keyboard/mouse/gamepad events via /dev/uinput,
	# which needs: (1) DAC access — udev rule grants group 'input' 0660,
	# (2) CAP_SYS_ADMIN for the UI_* ioctls, (3) CAP_SYS_NICE so sunshine's
	# nice -10/-15 priority raises don't fail. The setcap is lost on every
	# paru rebuild of sunshine, so this function must re-run on upgrades.
	print_status "Configuring uinput access for sunshine"
	doas tee /etc/udev/rules.d/85-sunshine.rules >/dev/null <<'UINPUT_EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", OPTIONS+="mode=0660", GROUP="input"
UINPUT_EOF
	doas udevadm control --reload
	doas udevadm trigger
	doas usermod -a -G input "$USER"
	# The AUR package installs a versioned binary (e.g. /usr/bin/sunshine-YYYY.MM.DD…)
	# and symlinks /usr/bin/sunshine to it. setcap refuses symlinks, so
	# resolve to the real path; every upgrade bumps the versioned filename.
	local sunshine_bin
	sunshine_bin="$(readlink -f "$(command -v sunshine)")"
	doas setcap 'cap_sys_admin,cap_sys_nice+p' "$sunshine_bin"

	# Disable SDDM: hephaistos is headless, no one ever physically logs in.
	# Fall back to multi-user.target so boot lands on a TTY prompt nobody
	# touches — SSH becomes the only real entry point.
	print_status "Disabling SDDM, switching default target to multi-user"
	doas systemctl disable sddm.service 2>/dev/null || true
	doas systemctl set-default multi-user.target

	# Streaming session launcher — started on demand via SSH from a client.
	# setsid + nohup + /dev/null redirects fully detach niri and sunshine
	# from the SSH session so they survive the ssh disconnect.
	doas tee /usr/local/bin/start-streaming >/dev/null <<'STREAM_EOF'
#!/usr/bin/env bash
# Launch a headless niri + sunshine session. Idempotent: a second
# invocation while sunshine is already running is a no-op.
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/streaming"
mkdir -p "$LOG_DIR"

if pgrep -u "$USER" -x sunshine >/dev/null 2>&1; then
    echo "sunshine already running"
    exit 0
fi

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"

# Start niri fully detached. No --session flag: we don't want the systemd
# graphical-session.target dance, just a bare compositor.
setsid --fork nohup niri \
    >"$LOG_DIR/niri.log" 2>&1 </dev/null

# Wait for niri's wayland socket to appear.
WAYLAND_DISPLAY=""
for _ in $(seq 1 50); do
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [[ -S "$sock" && "$sock" != *.lock ]]; then
            WAYLAND_DISPLAY="${sock##*/}"
            break 2
        fi
    done
    sleep 0.1
done

if [[ -z "$WAYLAND_DISPLAY" ]]; then
    echo "niri wayland socket did not appear" >&2
    exit 1
fi

export WAYLAND_DISPLAY

setsid --fork nohup env WAYLAND_DISPLAY="$WAYLAND_DISPLAY" sunshine \
    >"$LOG_DIR/sunshine.log" 2>&1 </dev/null

# Give sunshine a beat to bind its ports before the caller tries to connect.
sleep 2
echo "streaming session up (WAYLAND_DISPLAY=$WAYLAND_DISPLAY)"
STREAM_EOF
	doas chmod +x /usr/local/bin/start-streaming

	doas tee /usr/local/bin/stop-streaming >/dev/null <<'STOP_EOF'
#!/usr/bin/env bash
# Tear down the headless streaming session cleanly.
set -euo pipefail
pkill -u "$USER" -x sunshine || true
pkill -u "$USER" -x niri || true
echo "streaming session stopped"
STOP_EOF
	doas chmod +x /usr/local/bin/stop-streaming

	print_success "Streaming host configured — boot into multi-user, SSH in, run start-streaming"
}

setup_streaming_client() {
	print_status "Setting up Moonlight streaming client"

	# Wrapper: WOL → wait for SSH → trigger remote start-streaming → launch
	# moonlight pointed at hephaistos. Installed system-wide so the fuzzel
	# .desktop entry can Exec= it without needing $HOME expansion.
	doas tee /usr/local/bin/stream-hephaistos >/dev/null <<'CLIENT_EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly HOST="hephaistos"
readonly MAC="fc:4c:ea:25:6a:96"
readonly APP="Desktop"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "stream-hephaistos" "$1" "${2:-}"
    fi
    echo "[stream-hephaistos] $1${2:+: $2}"
}

ssh_ready() {
    ssh -o ConnectTimeout=1 -o BatchMode=yes "$HOST" true >/dev/null 2>&1
}

if ! ssh_ready; then
    notify "Waking hephaistos"
    wakeonlan "$MAC" >/dev/null
    waited=0
    until ssh_ready; do
        if ((waited >= 60)); then
            notify "Wake timeout" "hephaistos did not respond within 60s"
            exit 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
fi

notify "Starting streaming session"
if ! ssh "$HOST" /usr/local/bin/start-streaming; then
    notify "Remote launch failed" "start-streaming returned non-zero"
    exit 1
fi

notify "Launching Moonlight"
setsid --fork moonlight stream "$HOST" "$APP" \
    >/dev/null 2>&1 </dev/null
CLIENT_EOF
	doas chmod +x /usr/local/bin/stream-hephaistos

	# Fuzzel / app-launcher entry. Lives under /usr/local/share so it's
	# picked up via XDG_DATA_DIRS without touching chezmoi territory.
	doas mkdir -p /usr/local/share/applications
	doas tee /usr/local/share/applications/stream-hephaistos.desktop >/dev/null <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=Stream hephaistos
GenericName=Moonlight Streaming
Comment=Wake hephaistos, start the streaming session, and open Moonlight
Exec=/usr/local/bin/stream-hephaistos
Icon=moonlight
Terminal=false
Categories=Network;RemoteAccess;
Keywords=moonlight;sunshine;remote;stream;wake;
DESKTOP_EOF

	print_success "Streaming client configured (stream-hephaistos + fuzzel entry)"
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

	# Use the Plasma Wayland compositor directly
	doas tee /usr/local/bin/sddm-labwc <<'EOF'
#!/usr/bin/env bash

export XKB_DEFAULT_LAYOUT="fr,fr,us"
export XKB_DEFAULT_VARIANT="bepo,,"
export XKB_DEFAULT_OPTIONS="grp:alt_shift_toggle"
exec labwc
EOF
	doas chmod +x /usr/local/bin/sddm-labwc

	# Enable SDDM now that desktop environments are installed
	doas systemctl enable sddm

	print_success "SDDM configured and enabled"
}
