{ lib, ... }:
{
  user = {
    name = "casazza";
    fullName = "Olive Casazza";
    email = "olive.casazza@schrodinger.com";
  };

  isDeterminate = true;

  salt = {
    ai = {
      providers = {
        litellm = {
          host = "desk-nxst-001.schrodinger.com";
          port = 4000;
          endpoint = "http://desk-nxst-001.schrodinger.com:4000";
          localEndpoint = "http://localhost:4000";
          caddyEndpoint = "http://desk-nxst-001.schrodinger.com:8080/litellm";
          defaultLocalGroup = "desk-nxst-001-qwen3.6-35b-a3b";
          defaultCloudGroup = "coder-cloud-claude";
          modelGroups = {
            "desk-nxst-001-qwen3.6-35b-a3b" = "desk-nxst-001-qwen3.6-35b-a3b";
            coder-cloud-claude = "coder-cloud-claude";
            embedding = "embedding";
          };
        };

        vertex = {
          projectId = "vertex-code-454718";
          region = "us-east5";
          proxyBaseURL = "https://vertex-proxy.sdgr.app";
          proxyEndpoint = "https://vertex-proxy.sdgr.app/v1";
        };

        azure = {
          resourceName = "schrodinger-code";
          deployment = "Kimi-K2.6";
          baseURL = "https://schrodinger-code.openai.azure.com/openai/deployments/Kimi-K2.6";
        };

        omlx = {
          baseURL = "http://localhost:8000/v1";
        };

        exo = {
          apiPort = 52415;
          libp2pPort = 52416;
          baseURL = "http://localhost:52415/v1";
        };

        telemetry = {
          host = "desk-nxst-001.schrodinger.com";
          otlpGrpcPort = 4317;
          otlpHttpPort = 4318;
          otlpEndpoint = "http://desk-nxst-001.schrodinger.com:4317";
        };
      };

      models = {
        claudeOpus = "claude-opus-4-7";
        claudeSonnet = "claude-sonnet-4-7";
        claudeHaiku = "claude-haiku-4-5";
        gemini3Pro = "gemini-3-pro";
        gemini3Flash = "gemini-3-flash";
        gemini25Pro = "gemini-2.5-pro";
        gemini25Flash = "gemini-2.5-flash";
      };

      scripts = {
        getIamToken = ''
          #!/usr/bin/env bash
          set -euo pipefail
          exec gcloud auth print-identity-token 2>/dev/null
        '';
      };
    };
  };
}
