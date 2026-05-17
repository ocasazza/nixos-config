# twg: macOS-specific wiring (authentication secrets, config generation).
#
# Wraps the shared config from modules/shared/twg/ which provides the Home
# Manager configuration (binary, skills installation). This module adds:
#   - SOPS secrets for Atlassian credentials (email, API token, site)
#   - Declarative ~/.config/twg/auth.conf generation
#
# Snowfall auto-discovers this module from modules/darwin/twg/.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sharedTwg = import ../../shared/twg { inherit config lib pkgs; };
  user = lib.salt.user;
in
{
  imports = [ sharedTwg ];

  # Atlassian credentials stored in sops. TWG needs:
  #   - Email: Atlassian account email
  #   - Site: Site name (e.g., "schrodinger" for schrodinger.atlassian.net)
  #   - API Token: Generated via Atlassian account settings
  sops.secrets = {
    atlassian-email = {
      sopsFile = ../../../secrets/atlassian-email.yaml;
      format = "yaml";
      key = "atlassian_email";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
    atlassian-api-token = {
      sopsFile = ../../../secrets/atlassian-api-token.yaml;
      format = "yaml";
      key = "atlassian_api_token";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
    atlassian-site = {
      sopsFile = ../../../secrets/atlassian-site.yaml;
      format = "yaml";
      key = "atlassian_site";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
  };

  # Generate ~/.config/twg/auth.conf from sops secrets via template.
  # TWG stores auth state as a TOML file with [default] section containing
  # email, site, and token.
  sops.templates."twg-auth.conf" = {
    path = "/Users/${user.name}/.config/twg/auth.conf";
    mode = "0600";
    owner = user.name;
    content = builtins.readFile (
      (pkgs.formats.toml { }).generate "twg-auth.conf" {
        default = {
          email = config.sops.placeholder."atlassian-email";
          site = config.sops.placeholder."atlassian-site";
          token = config.sops.placeholder."atlassian-api-token";
        };
      }
    );
  };
}
