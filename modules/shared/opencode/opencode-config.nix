{
  lib,
  pkgs,
  brainDir,
  ...
}:

{
  home.file.".config/opencode/opencode.json".source = pkgs.replaceVars ./files/opencode.json {
    litellmBaseURL = lib.salt.ai.providers.litellm.caddyEndpoint;
    vertexProject = lib.salt.ai.providers.vertex.projectId;
    vertexRegion = lib.salt.ai.providers.vertex.region;
    inherit brainDir;
  };
}
