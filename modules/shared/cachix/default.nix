{ ... }:
{
  nix.settings = {
    substituters = [
      "https://ocasazza.cachix.org"
      "https://nix-community.cachix.org"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "ocasazza.cachix.org-1:CM2NirYn93VKnwoRppqqwbb6XjulYKRTcHsAbVyEpcQ="
    ];
  };
}
