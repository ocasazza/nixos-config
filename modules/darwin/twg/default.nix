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

  # Generate ~/.config/twg/auth.conf from sops secrets.
  # TWG stores auth state as a TOML file with [default] section containing
  # email, site, token, and optional bitbucket_token.
  home-manager.users.${user.name} = {
    home.activation.twgAuth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            # Generate TWG auth.conf from sops-decrypted secrets
            TWG_CONFIG_DIR="$HOME/.config/twg"
            mkdir -p "$TWG_CONFIG_DIR"

            if [ -r "${config.sops.secrets.atlassian-email.path}" ] && \
               [ -r "${config.sops.secrets.atlassian-api-token.path}" ] && \
               [ -r "${config.sops.secrets.atlassian-site.path}" ]; then

              EMAIL=$(cat "${config.sops.secrets.atlassian-email.path}")
              TOKEN=$(cat "${config.sops.secrets.atlassian-api-token.path}")
              SITE=$(cat "${config.sops.secrets.atlassian-site.path}")

              cat > "$TWG_CONFIG_DIR/auth.conf" <<EOF
      [default]
      email = "$EMAIL"
      site = "$SITE"
      token = "$TOKEN"
      EOF
              chmod 600 "$TWG_CONFIG_DIR/auth.conf"
            fi
    '';
  };
}
