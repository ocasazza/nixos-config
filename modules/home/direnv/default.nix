{ ... }:

# direnv + nix-direnv for per-directory shell envs. Snowfall
# auto-discovers this module and applies it to every HM user.
{
  programs.direnv = {
    enable = true;
    # nix-direnv caches the result of `nix develop` so subsequent shell
    # activations are near-instant instead of re-evaluating the flake.
    # Without this, every `direnv allow` (and every `cd` into a flake
    # directory) re-runs `nix develop` from scratch, which can hang for
    # minutes when the devshell pulls in heavy packages like Obsidian
    # or TeX Live.
    nix-direnv.enable = true;
    config = {
      global = {
        hide_env_diff = true;
        warn_timeout = 0;
      };
    };
  };
}
