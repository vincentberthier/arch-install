#!/usr/bin/env bash
# Development packages and tools

install_development_packages() {
    local packages=(
        # VPN and work essentials
        "openconnect" "iproute2" "iptables"
        
        # Development core
        "rustup" "cargo" "rust-analyzer"
        "clang" "lldb" "python" "python-pip"
        "typescript-language-server" "jujutsu"
        "musl" "rust-musl" "kernel-headers-musl"

        # LaTeX
        "texlive-basic" "texlive-latex" "texlive-latexrecommended" "texlive-latexextra"
        "texlive-fontsrecommended" "texlive-fontsextra" "texlive-pictures"
        "texlive-science" "texlive-bibtexextra" "biber"        

        # Python scientific stack
        "python-numpy" "python-matplotlib" "python-pandas" "python-seaborn"
        "python-scikit-image" "python-opencv" "python-pillow" "python-requests"
        "ipython" "python-black" "python-isort" "python-flake8"
        "python-lsp-server"
        
        # Development tools
        "eslint" "prettier" "bash-language-server" "shfmt" "buf" "yaml-language-server"

        # Rust tools
        "bacon" "cargo-binstall" "cargo-audit" "tokio-console"
        "cargo-deny" "cargo-expand" "cargo-flamegraph"
        "cargo-llvm-cov" "cargo-machete" "cargo-nextest"
        "cargo-outdated" "cargo-spellcheck"

        # C++ development
        "clang" "llvm" "lldb" "lld" "cmake" "make" "ninja"
        "bear" "gdb" "valgrind" "gcovr"

        # Utils
        "cdrtools" "hyperfine" "lcov" "tokei"
    )
    
    print_status "Installing Development packages (${#packages[@]} packages)"
    
    # Split into chunks
    local chunk_size=20
    for ((i=0; i<${#packages[@]}; i+=chunk_size)); do
        local chunk=("${packages[@]:i:chunk_size}")
        print_status "Installing chunk: ${chunk[*]}"
        
        if ! doas pacman -S --needed --noconfirm "${chunk[@]}"; then
            print_warning "Some packages in chunk failed to install, continuing..."
        fi
    done
    
    # Development AUR packages
    local aur_packages=(
        "ltex-ls-bin"                  # LS for LaTeX
        "duplicacy"                    # Backup tool
        "zellij"                       # Terminal multiplexer
        "postman-bin"                  # Development
        "teams-for-linux-bin"          # Work communication
        "vscode-langservers-extracted" # LS for web stuff
        "llvm-bolt"                    # Link Time Optimization
        "gitlab-ci-local"              # Run gitlab CI locally
        "mprocs-bin"                   # Run lots of stuff
        "taplo"                        # toml formatter
        "marksman"                     # Markdown formatter
        "scls"                         # Snippet LS for Helix
        "cmake-language-server"
        "dockerfile-language-server"
        "nodejs-compose-language-service"
        "onedrivegui"
    )
    
    for package in "${aur_packages[@]}"; do
        print_status "Installing $package from AUR"
        if ! paru -S --needed --noconfirm "$package"; then
            print_warning "Failed to install $package, continuing..."
        fi
    done

    # Install rust components
    rustup toolchain install stable
    rustup component add rust-src clippy rustfmt rust-docs
    rustup target add x86_64-unknown-linux-musl
    
    # Install Python packages via pip
    install_python_packages
    # Install Rust packages with cargo
    install_rust_packages
    
    print_success "Development packages installation completed"
}

install_rust_packages() {
    cargo binstall --no-confirm cargo-criterion
    cargo binstall --no-confirm cargo-mutants
    cargo binstall --no-confirm cargo-pgo
    cargo binstall --no-confirm gitmoji-rs
}

install_python_packages() {
    print_status "Installing Python packages via pip"
    
    local python_packages=(
        "astropy" "astroquery" "ipython"
    )
    
    # Create virtual environment for scientific packages
    python -m venv ~/.local/share/python-env
    source ~/.local/share/python-env/bin/activate
    
    pip install --upgrade pip
    for package in "${python_packages[@]}"; do
        print_status "Installing Python package: $package"
        pip install "$package" || print_warning "Failed to install $package"
    done
    
    deactivate
    print_success "Python packages installed"
}

install_podman() {
    print_status "Installing Podman"

    pacman -Sy --no-confirm podman podman-compose podman-docker buildah skopeo fuse-overlayfs slirp4netns
    doas usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
    mkdir -p ~/.config/containers

    # Create storage.conf for user
    cat > ~/.config/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/user/1000/containers"
graphroot = "/home/$USER/.local/share/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

    cat > ~/.config/containers/registries.conf << 'EOF'
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
