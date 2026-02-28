{ pkgs }:

with pkgs;
[
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
  pinentry_mac

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
  vscode
  crush
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
]
