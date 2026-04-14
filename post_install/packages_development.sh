#!/usr/bin/env bash
# Development packages and tools

install_development_packages() {
	local packages=(
		# VPN and work essentials
		"openconnect" "iproute2"

		# Development core
		"jujutsu" "openssl" "git" "gcovr" "grcov" "tokei" "lcov"
		"taplo-cli" "marksman" "bacon" "graphviz" "gnuplot"
		"perf" "kcachegrind" "hyperfine" "valgrind" "gdb" "cgdb"
		"strace" "ltrace" "mermaid-cli"

		# Rust stuff
		"rustup" "rust-analyzer" "llvm"
		"musl" "rust-musl" "kernel-headers-musl"
		"cargo-binstall" "cargo-audit" "cargo-deny" "cargo-expand"
		"cargo-llvm-cov" "cargo-machete" "cargo-nextest"
		"cargo-outdated" "cargo-spellcheck" "tokio-console"
		"cargo-flamegraph" "aarch64-linux-gnu-gcc" "riscv64-linux-gnu-gcc"

		# C++ stuff
		"clang" "lldb" "cmake" "make" "ninja" "zlib" "catch2" "doxygen" "bear" "vcpkg"
		"cppcheck" "check" "cinclude2dot" "libmilter" "libxml2-legacy"

		# LaTeX
		"texlive-basic" "texlive-latex" "texlive-latexrecommended" "texlive-latexextra"
		"texlive-fontsrecommended" "texlive-fontsextra" "texlive-pictures"
		"texlive-mathscience" "texlive-bibtexextra" "biber"

		# Python scientific stack
		"python" "python-pip"
		"python-numpy" "python-matplotlib" "python-pandas" "python-seaborn"
		"python-scikit-image" "python-opencv" "python-pillow" "python-requests"
		"ipython" "python-black" "python-isort" "python-flake8"
		"python-lsp-server"

		# Development tools
		"eslint" "prettier" "bash-language-server" "shfmt" "buf" "yaml-language-server"
		"typescript-language-server" "cdrtools" "heaptrack"

		# Node.js
		"nodejs" "npm"

		# Modern dev tooling
		"ast-grep" "just" "ruff" "ty" "uv" "glab"
		"cargo-make" "dpkg" "syslinux"
	)

	print_status "Installing Development packages (${#packages[@]} packages)"

	doas pacman -R cargo --noconfirm >/dev/null 2>&1 || true
	doas pacman -R rust --noconfirm >/dev/null 2>&1 || true

	install_pacman_packages "development" "${packages[@]}"

	install_rust_packages

	# Development AUR packages
	local aur_packages=(
		"cargo-criterion"              # Rust benchmarks
		"cargo-mutants"                # Mutation testing
		"rr"                           # Record and replay debugger
		"hotspot"                      # GUI for perf
		"ltex-ls-bin"                  # LS for LaTeX
		"duplicacy"                    # Backup tool
		"zellij"                       # Terminal multiplexer
		"postman-bin"                  # Development
		"teams-for-linux-bin"          # Work communication
		"vscode-langservers-extracted" # LS for web stuff
		"llvm-bolt"                    # Link Time Optimization
		"gitlab-ci-local"              # Run gitlab CI locally
		"mprocs-bin"                   # Run lots of stuff
		"scls"                         # Snippet LS for Helix
		"cmake-language-server"
		"dockerfile-language-server"
		"nodejs-compose-language-service"
		"onedrivegui"
		"conan"
		"mingw-w64-gcc"
		"mingw-w64-headers"
		"bindfs"
		"opencode-bin"  # AI coding assistant
		"rustrover"     # JetBrains Rust IDE
		"rustrover-jre" # JRE for RustRover
	)

	install_aur_packages "development" "${aur_packages[@]}"

	doas sed -i "s/#user_allow_other/user_allow_other/" /etc/fuse.conf

	# Install Python packages via pip
	install_python_packages

	# Install global npm packages
	install_npm_packages

	print_success "Development packages installation completed"
}

install_rust_packages() {
	# Install rust components
	rustup toolchain install stable
	rustup default stable
	rustup component add rust-src clippy rustfmt rust-docs llvm-tools
	rustup target add x86_64-unknown-linux-musl
	rustup target add aarch64-unknown-linux-gnu
	rustup target add riscv64gc-unknown-linux-gnu
	rustup target add x86_64-pc-windows-msvc

	export PATH="$HOME/.cargo/bin:$PATH"

	# Windows cross-compilation via xwin (downloads MSVC headers/libs)
	cargo binstall --no-confirm xwin
	xwin --accept-license splat --output ~/.xwin

	cargo binstall --no-confirm cargo-criterion
	cargo binstall --no-confirm cargo-mutants
	cargo binstall --no-confirm cargo-pgo
	cargo binstall --no-confirm gitmoji-rs
	cargo binstall --no-confirm starship-jj
}

install_python_packages() {
	print_status "Installing Python packages via pip"

	local python_packages=(
		"astropy" "astroquery" "ipython"
	)

	# Create virtual environment for scientific packages
	python -m venv ~/.local/share/python-env
	# shellcheck source=/dev/null
	source ~/.local/share/python-env/bin/activate

	pip install --upgrade pip
	for package in "${python_packages[@]}"; do
		print_status "Installing Python package: $package"
		if ! pip install "$package"; then
			record_failure "python-pip" "$package"
		fi
	done

	deactivate
	print_success "Python packages installed"
}

install_npm_packages() {
	print_status "Installing global npm packages"

	local npm_packages=(
		"@anthropic-ai/claude-code" # AI coding assistant
		"ccstatusline"              # Claude Code status line
	)

	for package in "${npm_packages[@]}"; do
		print_status "Installing npm package: ${package}"
		if ! npm install -g "${package}"; then
			record_failure "npm-global" "${package}"
		fi
	done

	print_success "Global npm packages installed"
}

install_podman() {
	print_status "Installing Podman"

	doas pacman -Sy --noconfirm podman podman-compose podman-docker buildah skopeo fuse-overlayfs slirp4netns
	doas usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
	mkdir -p ~/.config/containers

	# Create storage.conf for user (unquoted heredoc to expand $HOME)
	cat >~/.config/containers/storage.conf <<EOF
[storage]
driver = "overlay"
runroot = "/run/user/1000/containers"
graphroot = "${HOME}/.local/share/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

	cat >~/.config/containers/registries.conf <<'EOF'
unqualified-search-registries = ["docker.io", "quay.io"]

[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry]]
prefix = "quay.io"
location = "quay.io"
EOF

	doas systemctl enable --now podman.socket
	systemctl --user enable --now podman.socket
	systemctl --user enable --now podman-restart.service
}

install_embedded_packages() {
	print_status "Installing embedded/electronics packages"

	local packages=(
		# ARM cross-compilation
		"arm-none-eabi-gcc" "arm-none-eabi-newlib"
		# AVR toolchain
		"avr-gcc" "avr-libc" "avrdude"
		# EDA suite
		"kicad" "kicad-library" "kicad-library-3d"
		# Serial / hardware debugging
		"minicom" "evtest"
		# BLE
		"python-bleak"
	)

	install_pacman_packages "embedded" "${packages[@]}"

	# AUR packages
	local aur_packages=(
		"arduino-ide-bin" # Arduino IDE
		"picotool"        # Raspberry Pi Pico tool
	)

	install_aur_packages "embedded" "${aur_packages[@]}"

	print_success "Embedded/electronics packages installed"
}
