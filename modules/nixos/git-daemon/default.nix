# LAN-only git-daemon for serving bare repos over the read-only `git://`
# protocol on port 9418.
#
# Why this exists:
#   The flake under ~/.config/nixos-config has three `git+file://` inputs
#   (opencode, hermes, obsidian-vault) that point at working copies on
#   one specific machine — historically the Mac at /Users/casazza/...
#   When a NixOS host (luna) tries to evaluate the flake it can't see
#   that path; conversely if the input is moved to /home/casazza/...
#   the Mac breaks. The previous workarounds (rsync mirrors paired with
#   a second flake input, or symlink trickery) all leaked state.
#
#   git-daemon on luna gives us a single canonical bare repo per
#   logical project, served at `git://luna.local/<name>` for anonymous
#   read access from anywhere on the LAN. Pushes go via ssh
#   (`casazza@luna.local:/srv/git/<name>.git`), so the auth contract is
#   the existing ssh-key fleet — nothing new to manage.
#
# Auth posture:
#   git-daemon is intentionally unauthenticated for reads. Per nixpkgs'
#   own option description: "mostly intended for read-only access" in
#   "a closed LAN setting". We only enable openFirewall for trusted
#   networks. If/when we federate beyond the LAN, this needs to move
#   behind a Tailscale ACL or a TLS reverse proxy with HTTP basic auth
#   (cgit/nginx + auth_basic, or gitea). For the personal cluster on a
#   single LAN this is appropriate.
#
# Why not bigger options (gitea, cgit, gitlab):
#   The only consumer at module-author time is `nix flake` which only
#   needs raw git transport, not a UI / issues / CI. Adding a UI server
#   later is non-disruptive — git-daemon stays for `nix flake` and the
#   UI runs alongside on a different port.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.gitDaemon;
in
{
  options.local.gitDaemon = {
    enable = lib.mkEnableOption "LAN-only git-daemon for serving bare repos";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.git;
      defaultText = lib.literalExpression "pkgs.git";
      description = "git package providing the daemon binary.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "git-daemon";
      description = ''
        System user the daemon runs as. Owns `basePath` and all bare
        repos beneath it. Pushes (over ssh) go through the operator's
        own user account — see the `casazza` user's
        `git push casazza@luna.local:/srv/git/<name>.git` workflow.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "git-daemon";
      description = "System group; mirrors the user.";
    };

    basePath = lib.mkOption {
      type = lib.types.path;
      default = "/srv/git";
      description = ''
        Directory containing the bare repos. Each entry in `repos` must
        exist as `<basePath>/<name>.git` for the daemon to export it.
        The module pre-creates the directory with the right ownership;
        the bare repos themselves are created out-of-band by the
        operator (`git clone --bare <source> <basePath>/<name>.git`)
        because git-daemon never auto-creates repos.
      '';
    };

    repos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "opencode"
        "hermes-agent"
        "obsidian"
      ];
      description = ''
        Repo names exposed by the daemon. Each entry maps to
        `<basePath>/<name>.git` — both the systemd unit's
        `repositories` argument and the operator's clone command must
        agree on this list. Repos not in this list are NOT exported
        even if they exist under basePath (we set `exportAll = false`
        on the daemon to make that explicit).
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Bind address for the daemon. Default `0.0.0.0` is appropriate
        when this host is firewalled at the network edge and the LAN
        itself is trusted. Tighten to a specific LAN IP if the host
        has both LAN and untrusted interfaces.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9418;
      description = "TCP port. 9418 is the git-protocol IANA assignment.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open `port` on the host firewall. Only flip to true on hosts
        whose network reach is already trusted (LAN + Tailscale ACL).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "git-daemon (read-only LAN git transport)";
      home = cfg.basePath;
      createHome = false;
    };
    users.groups.${cfg.group} = { };

    # `services.gitDaemon` from nixpkgs handles the systemd unit shape
    # (Type=simple, restart, hardening). We just wire the namespaced
    # options through.
    services.gitDaemon = {
      enable = true;
      inherit (cfg)
        package
        user
        group
        basePath
        listenAddress
        port
        ;
      # We always enumerate the exposed repos explicitly — the
      # nixpkgs option's name is `exportAll`, which when true would
      # walk basePath for any repo with a `git-daemon-export-ok`
      # marker file. Closed-list mode is safer.
      exportAll = false;
      # The upstream module accepts `repositories` as a list of
      # absolute paths (one per exposed repo). Compose them from
      # cfg.basePath + cfg.repos so callers don't repeat the prefix.
      repositories = map (n: "${cfg.basePath}/${n}.git") cfg.repos;
    };

    # Pre-create the basePath. The bare repos themselves are NOT
    # created here — the operator does
    # `sudo -u ${cfg.user} git clone --bare <source> ${cfg.basePath}/<name>.git`
    # so each repo's initial commit history is the operator's choice
    # (typically the local working copy on whichever Mac happens to
    # have the right branch checked out).
    #
    # `f` rules also touch the `git-daemon-export-ok` marker for each
    # repo named in `cfg.repos`. Without it, git-daemon refuses to
    # serve the repo (`access denied or repository not exported`)
    # even when the path is in the daemon's `repositories=` list and
    # `exportAll = false` is set.
    systemd.tmpfiles.rules = [
      "d ${cfg.basePath} 0755 ${cfg.user} ${cfg.group} -"
    ]
    ++ map (
      n: "f ${cfg.basePath}/${n}.git/git-daemon-export-ok 0644 ${cfg.user} ${cfg.group} - -"
    ) cfg.repos;

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    # Sanity: every entry in `repos` SHOULD exist as a bare repo at
    # `<basePath>/<name>.git` before the daemon actually serves it,
    # but we don't enforce at eval time because the bare clone is an
    # out-of-band operator step. journalctl -u git-daemon will show
    # `[<repo>] does not appear to be a git repository` on any name
    # that's listed here but missing on disk; that's the operational
    # signal.
  };
}
