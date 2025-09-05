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
  ipcalc
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
  # rust
  cargo
  clippy
  wasm-pack
  # nodejs
  nodejs
  # Python
  python313
  python313Packages.virtualenv # globally install virtualenv
  python313Packages.pip
  ansible
  ansible-lint
  # devtools
  direnv
  devenv
  # Terraform
  #terraform-ls
  #terraform-docs
  # Nix
  nil
  nixfmt-rfc-style
  nix-tree # $nix-tree .#darwinConfigurations.macos.system
  update-daemon
]
