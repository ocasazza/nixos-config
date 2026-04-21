# NixOS-side event-driven pull of the obsidian repo so luna-side agents
# (LLM ingest, future RAG, future Q&A) work against an up-to-date
# CLAUDE.md and vault. Counterpart to the darwin obsidian-vault module
# which handles autosnapshots on the editing machine.
#
# Uses jj git fetch + jj rebase to handle concurrent autocommits from
# the Mac side cleanly (per the "VCS workflow — use jj" section of
# CLAUDE.md).
#
# Triggering:
#   The unit is a one-shot — no timer, no polling. Triggered cluster-
#   wide via consortium claw from a post-commit hook in the obsidian
#   repo on the editing Mac:
#       claw -w @vault-consumers systemctl start obsidian-vault-sync.service
#   The `vault-consumers` group lives in ~/.config/clustershell/
#   groups.d/cluster.cfg. Right now it's just luna; future hosts that
#   need vault sync just get added to the group with no code changes.
#
# polkit rule below grants `systemctl start obsidian-vault-sync.service`
# to the configured user without sudo, so the claw-driven ssh call
# doesn't need a TTY for password prompts.
#
# Push-back from luna isn't wired today — luna doesn't currently run
# anything that generates new commits. If a luna-side agent ever does,
# add a `jj git push` call after rebase (and a way to reconcile push
# conflicts).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.obsidianVaultSync;
in
{
  options.local.obsidianVaultSync = {
    enable = lib.mkEnableOption ''
      Periodic jj-based pull of the obsidian repo on a NixOS host.
      Keeps luna's local checkout in sync with origin (GitHub) so
      LLM agents reading CLAUDE.md or vault content see fresh state.
    '';

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/casazza/obsidian";
      description = ''
        Absolute path to the obsidian repo checkout on this host.
        Must be a `jj git clone`'d (not bare `git clone`'d) directory
        — the timer uses `jj git fetch` and `jj rebase`.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "casazza";
      description = "User that owns the repo checkout and runs the pull.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.jujutsu;
      defaultText = lib.literalExpression "pkgs.jujutsu";
      description = "jj package to use for fetch + rebase.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.obsidian-vault-sync = {
      description = "Pull obsidian repo via jj fetch + rebase";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Run as the repo owner; jj rejects operations across uid/gid
      # boundaries because of working-copy ownership checks.
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = cfg.repoPath;
        # jj git fetch needs SSH key access for the github remote.
        # systemd doesn't carry the user's environment by default;
        # HOME tells jj where to find ~/.gitconfig and ~/.ssh.
        Environment = [
          "HOME=/home/${cfg.user}"
          "PATH=${
            lib.makeBinPath [
              cfg.package
              pkgs.openssh
              pkgs.git
            ]
          }"
        ];
        # Best-effort. Network blips, transient remote errors, and
        # rebase conflicts all fail soft — they'll resolve on the
        # next tick or surface as a stuck working copy that the
        # operator deals with manually.
        ExecStart = pkgs.writeShellScript "obsidian-vault-sync" ''
          set -eu
          # Fetch every branch on origin into our local jj view.
          jj git fetch
          # Rebase any local in-flight revisions on top of the new
          # trunk. If there's nothing local (the common case here —
          # luna doesn't currently author commits), this is a no-op.
          jj rebase -d 'trunk()' || true
        '';
      };
    };

    # polkit rule: let the repo owner trigger the sync unit without
    # password. The claw-driven `ssh luna systemctl start ...` call
    # has no TTY, so without this it would silently fail with EACCES.
    # Scope is narrow — only this exact unit, only this exact action,
    # only this user.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "obsidian-vault-sync.service" &&
          subject.user == "${cfg.user}"
        ) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
