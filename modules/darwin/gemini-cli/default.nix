# Gemini CLI configuration: Vertex AI auth + shared provider settings.
#
# Gemini CLI uses `GOOGLE_GENAI_USE_VERTEXAI=true` to route through
# Vertex AI (Application Default Credentials). Unlike opencode/claude-code,
# gemini-cli doesn't support a custom proxy baseURL — it talks to
# Vertex AI directly via the @google/genai SDK.
#
# Auth: `gcloud auth application-default login` (one-time setup).
# The identity token helper used by claude-code/opencode (gcloud auth
# print-identity-token) is NOT used here — gemini-cli handles its own
# Vertex AI auth via ADC.
#
# Snowfall auto-discovers this module from modules/darwin/gemini-cli/.
{
  lib,
  pkgs,
  ...
}:

let
  user = lib.salt.user;
in
{
  home-manager.users.${user.name} = {
    # Vertex AI env vars for gemini-cli. These are the same project/region
    # that opencode and claude-code use via lib.salt.ai.providers.vertex.
    home.sessionVariables = {
      GOOGLE_GENAI_USE_VERTEXAI = "true";
      GOOGLE_CLOUD_PROJECT = lib.salt.ai.providers.vertex.projectId;
      GOOGLE_CLOUD_LOCATION = lib.salt.ai.providers.vertex.region;
    };

    # Managed settings.json: select vertex-ai auth, skip the interactive
    # auth prompt on first launch.
    home.file.".gemini/settings.json".source = (pkgs.formats.json { }).generate "gemini-settings.json" {
      security = {
        auth = {
          selectedType = "vertex-ai";
        };
      };
    };
  };
}
