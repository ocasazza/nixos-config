{ pkgs, lib, ... }:

# Cross-platform system packages. NOT auto-discovered by snowfall
# (modules/shared is not an auto-applied namespace); imported
# explicitly by the per-arch system-packages modules below.
#
# Anything that doesn't build on *both* aarch64-darwin and x86_64-linux
# MUST be gated with `optionals stdenv.isDarwin` / `optionals stdenv.isLinux`.
{
  environment.systemPackages = with pkgs; [
    # General packages for development and system management
    aspell
    aspellDicts.en
    bat
    btop
    coreutils
    killall
    openssh
    sqlite
    wget
    zip

    # networking
    netcat

    # Encryption and security tools
    age
    age-plugin-yubikey
    gnupg
    libfido2

    # Cloud-related tools and SDKs
    #docker
    #docker-compose
    awscli
    google-cloud-sdk
    #qemu
    #podman
    #podman-compose
    #podman-tui
    #dive
    #podman-desktop
    ansible
    ansible-lint
    #ansible-lint
    #terraform-ls
    #terraform-docs

    # Media-related packages
    dejavu_fonts
    ffmpeg
    fd
    font-awesome
    nerd-fonts._0xproto
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono

    # Text and terminal utilities
    htop
    iftop
    jq
    starship
    tree
    tmux
    unzip
    tio # serial console
    silver-searcher
    claude-code

    # Rust
    cargo
    clippy
    wasm-pack
    nodejs

    # Golang
    go

    # Python
    python313
    python313Packages.virtualenv
    python313Packages.pip
    direnv
    devenv

    # Nix
    nil
    nixfmt-rfc-style
    nix-tree
    nh
    cachix
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [
    # macOS-only: pinentry-mac is the GUI prompt for GnuPG. There's no
    # Linux equivalent under the same name (Linux uses pinentry-curses
    # / pinentry-gtk2 which `programs.gnupg.agent.pinentryPackage` picks
    # automatically).
    pinentry_mac

    # vscode in nixpkgs builds cleanly on Darwin via the upstream
    # binary tarball, but on x86_64-linux the package transitively
    # requires `xcbuild` (a macOS Xcode-build-system port) which fails
    # to compile against modern glibc/C++17 (uint64_t header issue).
    # Use the binary `vscode-fhs` or `vscodium` on linux instead, or
    # let users install it themselves.
    vscode
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux equivalents / extras
    vscodium # FOSS vscode build, no MS telemetry, builds cleanly on linux
  ];
}
