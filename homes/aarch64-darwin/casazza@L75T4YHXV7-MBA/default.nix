# Per-host snowfall home for casazza on this Mac.
# All four cluster Macs share the same HM config — defined in
# casazza@CK2Q9LN7PM-MBA/default.nix to avoid duplication.
{ ... }:

{
  # `@` is reserved in unquoted Nix path literals, so we build the
  # path via string concatenation (the `+` operator on a path + string
  # produces a path).
  imports = [
    (./. + "/../casazza@CK2Q9LN7PM-MBA/default.nix")
  ];
}
