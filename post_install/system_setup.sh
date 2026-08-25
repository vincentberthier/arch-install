#!/usr/bin/env bash
# System setup functions

# Apply a subset of the chezmoi source state, but only once there is a source
# state to apply. On a fresh machine `chezmoi init` has not run yet, and a bare
# `chezmoi apply <path>` exits non-zero on an unmanaged target -- which under
# the orchestrator's `set -e` kills the whole post-install. Callers get a
# recorded warning instead, and re-run the phase after `chezmoi init`.
chezmoi_apply_if_initialised() {
	local phase="$1"
	shift

	if ! command -v chezmoi &>/dev/null; then
		record_failure "$phase" "chezmoi" "not installed"
		return 1
	fi

	if ! chezmoi source-path &>/dev/null; then
		record_failure "$phase" "chezmoi apply" "no source state yet -- run 'chezmoi init' then re-run this phase"
		return 1
	fi

	print_status "${phase}: applying chezmoi state for $*"
	if ! chezmoi apply "$@"; then
		record_failure "$phase" "chezmoi apply" "apply failed for $*"
		return 1
	fi
	return 0
}

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

	# The units and the backup/prune/check scripts are chezmoi-managed
	# (private_dot_config/systemd/user and private_dot_config/duplicacy), so
	# every machine picks up changes with a plain `chezmoi apply` instead of a
	# re-run of the installer. chezmoi's run_onchange hook does the
	# daemon-reload and enables the timers.
	if ! chezmoi_apply_if_initialised "duplicacy" \
		"$HOME/.config/duplicacy" "$HOME/.config/systemd/user" "$HOME/.local/bin"; then
		return 0
	fi

	# Repository setup: writes .duplicacy/preferences for each backed-up folder
	# and registers the local Aegis storage when that drive is connected.
	print_status "Configuring duplicacy repositories"
	"$HOME/.local/bin/duplicacy-setup" || print_error "duplicacy-setup reported errors"
}

setup_vault_code() {
	# Projects the documentation living in code repositories into the Obsidian
	# vault, as directory symlinks. Hosts that have code project their own: the
	# vault's `Code` folders are derived content and are never synced between
	# machines. Design and rationale live in the vault itself, at
	# Notes/Permanentes/"Intégration du code dans le Vault.md".
	#
	# unison keeps the agent scratch (.claude/plans, brainstorm, debug) in step
	# with hephaistos. It is needed on BOTH ends and the versions must match --
	# unison refuses to talk to a different major version. unison-fsmonitor
	# ships with it and is what makes the sync event-driven rather than timed.
	install_pacman_packages "vault-code" unison inotify-tools

	# The script, the manifest and the units are chezmoi-managed
	# (private_dot_local/bin, private_dot_config/vault-code and
	# private_dot_config/systemd/user), so changes reach every machine with a
	# plain `chezmoi apply`. The run_onchange hook generates the unison profile
	# from the manifest, then reloads and enables the units.
	chezmoi_apply_if_initialised "vault-code" \
		"$HOME/.local/bin" "$HOME/.config/vault-code" "$HOME/.config/systemd/user" || true
}

setup_virtualization() {
	install_pacman_packages "virtualization" qemu-full virt-manager libvirt dnsmasq iproute2 swtpm
	enable_service "virtualization" system libvirtd --now || true
	doas usermod -a -G libvirt "$USER"
}
