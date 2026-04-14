#!/usr/bin/env bash
# System setup functions

setup_directories() {
	print_status "Setting up user directories"

	# Create standard directories
	mkdir -p ~/code ~/pcloud ~/vault
	mkdir -p ~/.config ~/.local/bin ~/.local/share

	print_success "Directories created"
}

setup_systemd_services() {
	print_status "Setting up systemd user services"

	# Enable user services
	enable_service "systemd" user pipewire || true
	enable_service "systemd" user pipewire-pulse || true
	enable_service "systemd" user wireplumber || true

	# Create update timer
	mkdir -p ~/.config/systemd/user

	# Daily update service
	cat >~/.config/systemd/user/daily-update.service <<'EOF'
[Unit]
Description=Daily system update
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/paru -Syu --noconfirm
ExecStart=/usr/bin/flatpak update -y

[Install]
WantedBy=default.target
EOF

	# Daily update timer (5 minutes after boot, then daily)
	cat >~/.config/systemd/user/daily-update.timer <<'EOF'
[Unit]
Description=Daily system update timer
Requires=daily-update.service

[Timer]
OnBootSec=5min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

	# Enable the timer
	systemctl --user daemon-reload
	enable_service "systemd" user daily-update.timer || true

	# Automount
	install_pacman_packages "automount" udisks2 udiskie
	enable_service "systemd" system udisks2.service --now || true
	doas usermod -a -G storage,disk "$USER"

	mkdir -p ~/.config/autostart
	cat >~/.config/autostart/udiskie.desktop <<EOF
[Desktop Entry]
Type=Application
Name=udiskie
Exec=udiskie --tray
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

	doas tee /etc/polkit-1/rules.d/50-udisks.rules <<'EOF'
polkit.addRule(function(action, subject) {
    var YES = polkit.Result.YES;
    var permission = {
        // only required for udisks1:
        "org.freedesktop.udisks.filesystem-mount": YES,
        "org.freedesktop.udisks.luks-unlock": YES,
        "org.freedesktop.udisks.drive-eject": YES,
        "org.freedesktop.udisks.drive-detach": YES,
        // only required for udisks2:
        "org.freedesktop.udisks2.filesystem-mount": YES,
        "org.freedesktop.udisks2.encrypted-unlock": YES,
        "org.freedesktop.udisks2.eject-media": YES,
        "org.freedesktop.udisks2.power-off-drive": YES,
        // required for udisks2 if using udiskie from another seat (e.g. systemd):
        "org.freedesktop.udisks2.filesystem-mount-other-seat": YES,
        "org.freedesktop.udisks2.filesystem-unmount-others": YES,
        "org.freedesktop.udisks2.encrypted-unlock-others": YES,
        "org.freedesktop.udisks2.eject-media-others": YES,
        "org.freedesktop.udisks2.power-off-drive-others": YES
    };
    if (subject.isInGroup("storage")) {
        return permission[action.id];
    }
});
EOF
	doas systemctl restart polkit

	print_success "Systemd services configured"
}

setup_duplicacy() {
	if ! command -v duplicacy &>/dev/null; then
		paru -S --noconfirm duplicacy rclone
	fi

	SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
	mkdir -p "$SYSTEMD_USER_DIR"

	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
	XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

	print_status "Creating systemd service files"
	cat >"$SYSTEMD_USER_DIR/duplicacy-backup.service" <<'EOF'
[Unit]
Description=Duplicacy backups

[Service]
Type=simple
ExecStart=/bin/bash -c 'set -eou pipefail; export HOME="%h"; export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"; export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; /bin/bash "$XDG_CONFIG_HOME/duplicacy/backup.sh"'

[Install]
WantedBy=default.target
EOF

	# Create duplicacy-prune.service
	cat >"$SYSTEMD_USER_DIR/duplicacy-prune.service" <<'EOF'
[Unit]
Description=Duplicacy prune all backups

[Service]
Type=simple
ExecStart=/bin/bash -c 'set -eou pipefail; export HOME="%h"; export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"; export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; /bin/bash "$XDG_CONFIG_HOME/duplicacy/prune.sh"'

[Install]
WantedBy=default.target
EOF

	# Create duplicacy-backup.timer
	cat >"$SYSTEMD_USER_DIR/duplicacy-backup.timer" <<'EOF'
[Unit]
Description=Timer for duplicacy backups

[Timer]
Unit=duplicacy-backup.service
OnBootSec=15m
OnUnitActiveSec=60m

[Install]
WantedBy=timers.target
EOF

	# Create duplicacy-prune.timer
	cat >"$SYSTEMD_USER_DIR/duplicacy-prune.timer" <<'EOF'
[Unit]
Description=Timer for duplicacy pruning

[Timer]
Unit=duplicacy-prune.service
OnBootSec=120m

[Install]
WantedBy=timers.target
EOF

	systemctl --user daemon-reload
	print_status "Enabling and starting services"

	enable_service "duplicacy" user duplicacy-backup.service || true
	enable_service "duplicacy" user duplicacy-prune.service || true
	enable_service "duplicacy" user duplicacy-backup.timer --now || true
	enable_service "duplicacy" user duplicacy-prune.timer --now || true
}

setup_virtualization() {
	install_pacman_packages "virtualization" qemu-full virt-manager libvirt dnsmasq iproute2 swtpm
	enable_service "virtualization" system libvirtd --now || true
	doas usermod -a -G libvirt "$USER"
}
