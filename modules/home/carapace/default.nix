{ ... }:

# Carapace multi-shell completion. Snowfall auto-discovers this module
# and applies it to every HM user.
{
  programs.carapace.enable = true;
  programs.carapace.enableNushellIntegration = true;
}
