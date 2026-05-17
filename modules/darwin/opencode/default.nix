# opencode: macOS-specific wiring (sops secrets, LaunchAgent, binary, MCP).
#
# Wraps the shared config from modules/shared/opencode/ which provides
# the Home Manager configuration (opencode.json, plugins, env vars,
# activation scripts). This module adds:
#   - SOPS secrets for API keys
#   - LaunchAgent to inject OPENAI_API_KEY into GUI sessions (Zed, etc.)
#   - Binary installation (pkgs.opencode, pkgs.opencode-voice, pkgs.bun)
#     — NOTE: binaries are in shared/opencode/ too; this just ensures the
#     correct package pins via the nixpkgs-opencode flake input.
#   - Platform-specific MCP server config
#
# Snowfall auto-discovers this module from modules/darwin/opencode/.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sharedOpencode = import ../../shared/opencode { inherit config lib pkgs; };
in
{
  imports = [ sharedOpencode ];

  # gcloud CLI needed by the vertex-proxy plugin for identity token refresh.
  environment.systemPackages = [
    pkgs.google-cloud-sdk
  ];

  # Per-client LiteLLM virtual key + Schrodinger Azure OpenAI key.
  # Both decrypt to single `KEY=value` lines — modules use the
  # `lib.salt.helpers.extractSecret` helper to peel the value off.
  sops.secrets = {
    # hybrid-olive key: covers opencode and hermes (hybrid team — local + cloud).
    # Migrated from litellm-key-opencode-darwin to the new multi-tenant key model.
    litellm-key-opencode-darwin = {
      sopsFile = ../../../secrets/litellm-key-hybrid-olive.yaml;
      format = "yaml";
      key = "litellm_api_key";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
    azure-api-key-opencode-darwin = {
      sopsFile = ../../../secrets/azure-api-key-opencode-darwin.yaml;
      format = "yaml";
      key = "azure_api_key";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
  };

  # Inject OPENAI_API_KEY (= LiteLLM key) into the GUI session so Zed and
  # other OpenAI-compatible GUI apps see it without manual keychain setup.
  # Runs at login; the sops secret is always decrypted before login.
  environment.userLaunchAgents."dev.schrodinger.opencode-env.plist".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>dev.schrodinger.opencode-env</string>
      <key>RunAtLoad</key>
      <true/>
      <key>ProgramArguments</key>
      <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>
          KEY="${lib.salt.helpers.extractSecret config.sops.secrets.litellm-key-opencode-darwin.path}"
          if [ -n "$KEY" ]; then
            launchctl setenv OPENAI_API_KEY "$KEY"
            launchctl setenv LITELLM_API_KEY_OPENCODE_DARWIN "$KEY"
          fi
        </string>
      </array>
      <key>StandardOutPath</key>
      <string>/tmp/opencode-env.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/opencode-env.err</string>
    </dict>
    </plist>
  '';
}
