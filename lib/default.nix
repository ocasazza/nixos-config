{ lib, ... }:
rec {
  user = {
    name = "casazza";
    fullName = "Olive Casazza";
    email = "olive.casazza@schrodinger.com";
  };

  isDeterminate = true;

  # Exo cluster topology
  thunderboltHosts = [
    "CK2Q9LN7PM-MBA"
    "GJHC5VVN49-MBP"
    "L75T4YHXV7-MBA"
  ];

  thunderboltLinks = [
    {
      from = "CK2Q9LN7PM-MBA";
      to = "GJHC5VVN49-MBP";
    }
    {
      from = "GJHC5VVN49-MBP";
      to = "L75T4YHXV7-MBA";
    }
  ];

  exoPeersFor = hostname: lib.filter (h: h != hostname) thunderboltHosts;

  ai = {
    providers = {
      litellm = {
        host = "litellm.pdx-nxst-001.schrodinger.com";
        port = 8080;
        endpoint = "http://litellm.pdx-nxst-001.schrodinger.com:8080";
        localEndpoint = "http://localhost:4000";
        caddyEndpoint = "http://litellm.pdx-nxst-001.schrodinger.com:8080";
        # LiteLLM /vertex passthrough (auth: false) proxies to
        # vertex-proxy.sdgr.app. Clients send gcloud id-tokens;
        # vertex-proxy validates them directly.
        vertexPassthroughEndpoint = "http://litellm.pdx-nxst-001.schrodinger.com:8080/vertex/v1";
        defaultLocalGroup = "qwen3.6-35b-a3b";
        defaultCloudGroup = "azure-kimi-k2.6";
        modelGroups = {
          "qwen3.6-35b-a3b" = "qwen3.6-35b-a3b";
          "azure-kimi-k2.6" = "azure-kimi-k2.6";
          "sdgr-glm-5.1" = "sdgr-glm-5.1";
          "sdgr-ring" = "sdgr-ring";
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
        host = "pdx-nxst-001.schrodinger.com";
        otlpGrpcPort = 4317;
        otlpHttpPort = 4318;
        otlpEndpoint = "http://pdx-nxst-001.schrodinger.com:4317";
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

  helpers = {
    # Generates a bash snippet to safely extract a value from a KEY=VALUE secret file.
    # Returns the value or an empty string if the file is missing/unreadable.
    # Used in sessionVariablesExtra and shell wrappers.
    extractSecret =
      filePath: ''$(if [ -r "${toString filePath}" ]; then cut -d= -f2- < "${toString filePath}"; fi)'';

    # Standardizes home-relative path construction.
    # On Darwin, homeBase defaults to /Users.
    mkHomePath = user: path: "/Users/${user}/${path}";
  };
}
