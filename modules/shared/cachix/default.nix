{ lib, isDeterminate, ... }:
let
  substituters = [
    "https://ocasazza.cachix.org"
    "https://na-son.cachix.org"
    "https://nix-community.cachix.org"
    "https://exo.cachix.org"
  ];
  trustedPublicKeys = [
    "ocasazza.cachix.org-1:4J9/Csix7SSPiUIyaSeISIT475va14uZPwJVipSDY+Y="
    "na-son.cachix.org-1:CM2NirYn93VKnwoRppqqwbb6XjulYKRTcHsAbVyEpcQ="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "exo.cachix.org-1:okq7hl624TBeAR3kV+g39dUFSiaZgLRkLsFBCuJ2NZI="
  ];
in
{
  # Determinate Nix manages nix.conf directly and ignores nix.settings.
  # Write to nix.custom.conf instead (included via `!include nix.custom.conf`).
  environment.etc."nix/nix.custom.conf" = lib.mkIf isDeterminate {
    text = ''
      extra-substituters = ${lib.concatStringsSep " " substituters}
      extra-trusted-public-keys = ${lib.concatStringsSep " " trustedPublicKeys}
    '';
  };

  # Standard nix.settings for non-Determinate hosts
  nix.settings = lib.mkIf (!isDeterminate) {
    substituters = substituters ++ [ "https://cache.nixos.org/" ];
    trusted-public-keys = trustedPublicKeys;
  };
}
