{
  pkgs,
  lib,
  ...
}:

# SSH client config + per-host blocks. Snowfall auto-discovers this
# module and applies it to every HM user. `user.name` is read from
# `lib.salt.user`; `homeDirectory` comes from HM's own
# `config.home.homeDirectory` where possible, but a few SSH hosts
# pin the Darwin `/Users/<name>` path explicitly because they're
# reached from darwin hosts only (iLO, cluster admin keys, etc.).
let
  user = lib.salt.user;
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      # Global defaults applied to every host.
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
        identityFile =
          if pkgs.stdenv.hostPlatform.isDarwin then
            "/Users/${user.name}/.ssh/id_ed25519"
          else
            "/home/${user.name}/.ssh/id_ed25519";
      };

      "github.com" = {
        hostname = "github.com";
        identitiesOnly = true;
      };

      "CK2Q9LN7PM-MBA.local CK2Q9LN7PM-MBA.tb".extraOptions.ConnectTimeout = "5";
      "GJHC5VVN49-MBP.local GJHC5VVN49-MBP.tb".extraOptions.ConnectTimeout = "5";

      "desk-nxst-*" = {
        identitiesOnly = true;
        extraOptions = {
          CanonicalizeHostname = "yes";
          CanonicalDomains = "schrodinger.com";
          CanonicalizeMaxDots = "1";
        };
      };

      # ── Home LAN (192.168.1.0/24) ────────────────────────────
      # seir is AppGate-filtered over IPv4 (ZTNA default-deny for
      # non-entitled LAN hosts), so it routes over IPv6 via Bonjour.
      # All other home LAN hosts work fine over IPv4 through AppGate.
      #
      # NOTE: 192.168.1.35 is included as a Host pattern so that muscle
      # memory `ssh olive@192.168.1.35` still works — the HostName override
      # rewrites it to seir.local + forces IPv6 before the connect happens.
      "seir seir.local 192.168.1.35" = {
        hostname = "seir.local";
        user = "olive";
        addressFamily = "inet6";
        identitiesOnly = true;
        identityFile = "/Users/${user.name}/.ssh/olive_id_ed25519";
        # seir runs zellij at login and we don't manage its config, so
        # every plain `ssh seir` would `zellij attach` to the same
        # default session and mirror panes across terminals. Force a
        # fresh randomly-named session per interactive connect; ssh
        # ignores RemoteCommand whenever an explicit command is given,
        # so scp / rsync / git-over-ssh are unaffected.
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "zellij";
        };
      };

      # Personal home hosts — all share the olive user + key.
      # This block merges with the per-host HostName blocks below
      # (SSH applies every matching Host pattern).
      "contra rpi5 mm01 mm02 mm03 mm04 mm05 hp01 hp02 hp03" = {
        user = "olive";
        identitiesOnly = true;
        identityFile = "/Users/${user.name}/.ssh/olive_id_ed25519";
      };

      # Raspberry Pi 5
      "rpi5".hostname = "192.168.1.16";

      # contra (cluster head?)
      "contra".hostname = "192.168.1.100";

      # luna — NixOS box, RTX 3090 Ti, vLLM host. Same physical machine
      # as `desk-nxst-001` (renamed in the 2026-04-24 split). The `luna`
      # alias is kept because the flake's git-daemon transport URLs are
      # `git://luna/<repo>` (see flake.nix opencode/hermes/obsidian
      # inputs); rewriting the alias here lets every Mac resolve those
      # URLs to the current host without a flake.nix bump.
      "luna luna.local" = {
        hostname = "desk-nxst-001";
        user = "casazza";
        identitiesOnly = true;
        identityFile =
          if pkgs.stdenv.isDarwin then
            "/Users/${user.name}/.ssh/id_ed25519"
          else
            "/home/${user.name}/.ssh/id_ed25519";
        extraOptions = {
          ConnectTimeout = "5";
          CanonicalizeHostname = "yes";
          CanonicalDomains = "schrodinger.com";
          CanonicalizeMaxDots = "1";
        };
      };

      # HPE iLO BMCs (out-of-band management).
      # Web UI lives on :443, but mpSSH (iLO's smash CLI) on :22 supports
      # power on/off, virtual media, console redirection, etc.
      #
      # iLO's mpSSH only speaks legacy crypto (DH-group14-sha1 + ssh-rsa
      # host keys), which modern OpenSSH disables by default. We re-enable
      # them ONLY for these hosts. User is IPMIUSER (password also IPMIUSER);
      # SSH will prompt for it interactively. Pubkey isn't supported.
      "hp-bmc-*" = {
        user = "IPMIUSER";
        extraOptions = {
          KexAlgorithms = "+diffie-hellman-group14-sha1";
          HostKeyAlgorithms = "+ssh-rsa";
          PubkeyAuthentication = "no";
          PreferredAuthentications = "password,keyboard-interactive";
        };
      };
      "hp-bmc-01 hp-bmc-1".hostname = "192.168.1.101";
      "hp-bmc-02 hp-bmc-2".hostname = "192.168.1.102";
      "hp-bmc-03 hp-bmc-3".hostname = "192.168.1.103";

      # Mac mini cluster (mm01–mm05)
      "mm01".hostname = "192.168.1.111";
      "mm02".hostname = "192.168.1.112";
      "mm03".hostname = "192.168.1.113";
      "mm04".hostname = "192.168.1.114";
      "mm05".hostname = "192.168.1.115";

      # HP servers (hp01–hp03, paired 1:1 with their iLOs above)
      "hp01".hostname = "192.168.1.121";
      "hp02".hostname = "192.168.1.122";
      "hp03".hostname = "192.168.1.123";

      # Dell box (.250) — vague alias since hostname unknown
      "dell".hostname = "192.168.1.250";
    };
  };
}
