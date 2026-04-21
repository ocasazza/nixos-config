{
  config,
  lib,
  pkgs,
  user,
  obsidianVault,
  opencode,
  system,
  ...
}:

with lib;

let
  cfg = config.local.obsidianVault;

  isDarwin = builtins.elem system [
    "aarch64-darwin"
    "x86_64-darwin"
  ];

  watcherPkg = obsidianVault.packages.${system}.vault-snapshot-watch;

  # The reingest-auto.sh script lives in the obsidian repo (the same
  # checkout the vault is in), one level above `vaultPath`. We don't bake
  # it into the obsidian-vault flake because (a) it's a one-line wrapper
  # around `opencode run /reingest -` and (b) the user iterates on it
  # alongside the slash command + doctype registry, so pulling it from
  # the live checkout is the right ergonomics.
  defaultRepoPath = builtins.dirOf cfg.vaultPath;

  # launchd's PATH is minimal (`/usr/bin:/bin:/usr/sbin:/sbin`), so the
  # agent script can't find `opencode`, `rg`, or even `git mv` unless we
  # splice nixpkgs paths in via EnvironmentVariables.PATH. The script
  # uses an mkdir-based lock instead of flock so we don't need util-linux.
  reingestPath = lib.makeBinPath [
    opencode.packages.${system}.default
    pkgs.ripgrep
    pkgs.bash
    pkgs.coreutils
    pkgs.git
  ];
in
{
  options.local.obsidianVault = {
    enable = mkEnableOption "Obsidian vault auto-snapshot launchd agent (jj-based)";

    vaultPath = mkOption {
      type = types.str;
      example = "/Users/casazza/Repositories/ocasazza/obsidian/vault";
      description = ''
        Absolute path to the Obsidian vault directory. The watcher's
        repo root is `vaultPath/..`, which must contain `.git` (and after
        the first run, `.jj`).
      '';
    };

    debounce = mkOption {
      type = types.int;
      default = 30;
      description = ''
        Trailing-edge debounce window in seconds. Edits within this window
        are coalesced into a single snapshot. The default of 30s is a
        compromise between fresh history and keeping commit volume sane
        during interactive editing.
      '';
    };

    logPath = mkOption {
      type = types.str;
      default = "/tmp/vault-snapshot-watch.log";
      description = "Path for combined stdout/stderr from the watcher.";
    };

    reingestAuto = {
      enable = mkEnableOption "periodic LLM re-ingestion of notes tagged `ingest/auto`";

      interval = mkOption {
        type = types.int;
        default = 3600;
        description = ''
          launchd `StartInterval` for the reingest-auto agent, in seconds.
          Default 3600 (hourly) — the LLM call is non-trivial and the
          trigger tag has to be set by the user (or another pipeline)
          for anything to happen, so a tight interval just wastes
          cycles.
        '';
      };

      repoPath = mkOption {
        type = types.str;
        default = defaultRepoPath;
        defaultText = literalExpression "builtins.dirOf cfg.vaultPath";
        description = ''
          Absolute path to the obsidian repo checkout that contains
          `scripts/reingest-auto.sh`, `.opencode/command/reingest.md`,
          and `.opencode/doctypes.json`. Defaults to one level above
          `vaultPath`.
        '';
      };
    };
  };

  config = mkIf (cfg.enable && isDarwin) {
    launchd.user.agents.vault-snapshot-watch = {
      command = "${watcherPkg}/bin/vault-snapshot-watch ${cfg.vaultPath}";
      serviceConfig = {
        Label = "local.vault-snapshot-watch";
        RunAtLoad = true;
        # Long-lived process: fswatch streams events forever. KeepAlive
        # restarts it if it crashes (shouldn't happen but cheap insurance).
        KeepAlive = true;
        # jj reads ~/.gitconfig for identity backfill, and `jj git push`
        # uses ~/.ssh for the GitHub remote — both require HOME to be set
        # explicitly in the launchd plist.
        EnvironmentVariables = {
          HOME = "/Users/${user.name}";
          VAULT_SNAPSHOT_DEBOUNCE = toString cfg.debounce;
        };
        StandardOutPath = cfg.logPath;
        StandardErrorPath = cfg.logPath;
      };
    };

    launchd.user.agents.reingest-auto = mkIf cfg.reingestAuto.enable {
      command = "${cfg.reingestAuto.repoPath}/scripts/reingest-auto.sh";
      serviceConfig = {
        Label = "local.reingest-auto";
        # Don't fire on every login — the StartInterval timer drives this.
        RunAtLoad = false;
        StartInterval = cfg.reingestAuto.interval;
        EnvironmentVariables = {
          # opencode reads ~/.config/opencode/opencode.json + ~/.local/share/opencode
          # for auth. Without HOME, launchd inherits / which breaks lookup.
          HOME = "/Users/${user.name}";
          # launchd's default PATH is too minimal for opencode/rg/flock.
          PATH = reingestPath;
        };
        StandardOutPath = "/tmp/reingest-auto.log";
        StandardErrorPath = "/tmp/reingest-auto.log";
      };
    };
  };
}
