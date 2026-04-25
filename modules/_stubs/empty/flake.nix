# Empty stub flake. Used as `--override-input` target for darwin-only
# inputs (opencode, hermes, git-fleet*) when building NixOS systems
# that don't have access to the underlying private repos.
#
# Every output mimics what the real input might expose, but as a no-op:
#   * darwinModules.default     → empty NixOS module
#   * darwinModules.autopkgserver → empty
#   * homeManagerModule         → empty
#   * packages.<system>.default → smallest possible derivation
#
# Usage:
#   nix build .#nixosConfigurations.desk-nxst-001.config.system.build.toplevel \
#     --override-input opencode  path:./modules/_stubs/empty \
#     --override-input hermes    path:./modules/_stubs/empty \
#     --override-input git-fleet path:./modules/_stubs/empty \
#     --override-input git-fleet-runner path:./modules/_stubs/empty
#
# The `cast-on` deploy package and the nixos-rebuild scripts on
# desk-nxst-001 add these overrides automatically.
{
  description = "Empty stub flake for darwin-only inputs that should not be fetched on linux";

  outputs = _: {
    # NixOS / nix-darwin module shapes — empty modules so any `imports`
    # referencing them succeed without contributing config.
    darwinModules = {
      default = { ... }: { };
      autopkgserver = { ... }: { };
    };
    nixosModules = {
      default = { ... }: { };
    };
    homeManagerModule = { ... }: { };
    homeModules = {
      default = { ... }: { };
    };
    # Empty package set — `inputs.opencode.packages.<system>.default`
    # references will fail loudly which is desired (caller code
    # should be guarded by `lib.optional (inputs ? opencode ...)`).
    packages = { };
    lib = { };
  };
}
