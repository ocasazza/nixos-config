{
  pkgs,
  inputs,
  ...
}:
# Bifrost HTTP gateway. We can't use upstream's `packages.<sys>.bifrost-http`
# directly because their `bifrost-ui` derivation has a stale `npmDepsHash`
# that's drifted since the v1.5.0 tag (upstream bug). Their `bifrost-http`
# build, however, gracefully falls back to a tiny index.html stub when
# `${bifrost-ui}/ui` doesn't exist (see preBuild in their bifrost-http.nix).
#
# So we callPackage upstream's bifrost-http.nix directly and pass a stub
# bifrost-ui — which gives us the gateway without the unfixable UI build.
# The web UI at localhost:8080/ui is non-functional in this build; the API
# surface (/v1/chat/completions, /v1/models, etc.) works fully.
#
# `inputs` is passed by snowfall-lib's package-discovery convention.
let
  bifrost-ui-stub = pkgs.runCommand "bifrost-ui-stub" { } ''
    mkdir -p $out/ui
    printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Bifrost API</title><body>Bifrost gateway is running. UI is intentionally disabled in this Nix build; use the API at /v1/* directly.</body>' > $out/ui/index.html
  '';

  # Upstream's bifrost-http.nix expects `inputs.nixpkgs` (just the path)
  # and uses it to find a Go 1.26.2+ toolchain. Forward bifrost's OWN
  # nixpkgs (staging-next) — our pinned one only has Go 1.26.1.
  bifrostNixpkgs = inputs.bifrost.inputs.nixpkgs;
  forwardedInputs = {
    nixpkgs = bifrostNixpkgs;
  };
  bifrostPkgs = import bifrostNixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  unpinnedBifrost = bifrostPkgs.callPackage "${inputs.bifrost}/nix/packages/bifrost-http.nix" {
    inputs = forwardedInputs;
    src = inputs.bifrost;
    version = "1.5.0";
    bifrost-ui = bifrost-ui-stub;
  };
in
# Re-pin vendorHash because upstream's hardcoded sha drifts when bifrost
# inputs.nixpkgs moves between staging-next revs (changes Go toolchain
# and hence go.sum resolution). Override via overrideAttrs so we can bump
# without forking upstream's bifrost-http.nix.
unpinnedBifrost.overrideAttrs (_: {
  vendorHash = "sha256-VfVc4iqraXSKqp8cdPCecC7f/yFzJsqnpJh+kLwseuY=";
})
