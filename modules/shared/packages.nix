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
  # tigervnc
  # networking
  #ipcalc

  # Encryption and security tools
  #age
  #age-plugin-yubikey
  #gnupg
  #libfido2
  #pinentry
  # Cloud-related tools and SDKs
  docker
  docker-compose
  awscli
  google-cloud-sdk
  #qemu
  #podman
  #podman-compose
  #podman-tui
  #dive
  #podman-desktop
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
  # lang tools
  cargo
  clippy
  go
  wasm-pack
  nodejs
  python313
  python313Packages.virtualenv
  python313Packages.pip
  ansible
  ansible-lint
  direnv
  devenv
  python313
  python313Packages.virtualenv # globally install virtualenv
  cargo
  trunk
  #ansible-lint
  # Terraform
  #terraform-ls
  #terraform-docs

  # Nix
  nil
  nixfmt-rfc-style
  nix-tree # $nix-tree .#darwinConfigurations.macos.system
  nh
  zed
  gemini-cli-bin
]
