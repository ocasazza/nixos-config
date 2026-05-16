{ lib, pkgs, ... }:

{
  home.file.".config/opencode/plugins/vertex-proxy.ts".source =
    pkgs.replaceVars ./files/vertex-proxy.ts
      {
        projectId = lib.salt.ai.providers.vertex.projectId;
      };
}
