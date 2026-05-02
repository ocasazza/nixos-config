{ lib, ... }:

let
  # ── Thunderbolt point-to-point links ────────────────────────────────────
  # Each cable is a /30 subnet between two (host, interface) endpoints.
  # Side "a" gets .1, side "b" gets .2.  No L2 bridging — pure L3.
  thunderboltLinks = [
    {
      subnet = "10.99.3"; # 10.99.3.0/30
      a = {
        host = "CK2Q9LN7PM-MBA";
        iface = "en1";
      };
      b = {
        host = "GJHC5VVN49-MBP";
        iface = "en2";
      };
    }
    {
      subnet = "10.99.4"; # 10.99.4.0/30
      a = {
        host = "GJHC5VVN49-MBP";
        iface = "en1";
      };
      b = {
        host = "L75T4YHXV7-MBA";
        iface = "en1";
      };
    }
  ];

  thunderboltHosts = lib.unique (
    [
      "GN9CFLM92K-MBP"
    ]
    ++ lib.concatMap (link: [
      link.a.host
      link.b.host
    ]) thunderboltLinks
  );

  exoPort = 52416;

  linksForHost =
    hostname:
    lib.concatMap (
      link:
      if link.a.host == hostname then
        [
          {
            ip = "${link.subnet}.1";
            peerIp = "${link.subnet}.2";
            peerHost = link.b.host;
            iface = link.a.iface;
            subnet = link.subnet;
          }
        ]
      else if link.b.host == hostname then
        [
          {
            ip = "${link.subnet}.2";
            peerIp = "${link.subnet}.1";
            peerHost = link.a.host;
            iface = link.b.iface;
            subnet = link.subnet;
          }
        ]
      else
        [ ]
    ) thunderboltLinks;

  exoPeersFor =
    hostname:
    let
      links = linksForHost hostname;
    in
    map (l: "/ip4/${l.peerIp}/tcp/${toString exoPort}") links;
in
{
  inherit
    thunderboltLinks
    thunderboltHosts
    exoPort
    linksForHost
    exoPeersFor
    ;

  user = {
    name = "casazza";
    fullName = "Olive Casazza";
    email = "olive.casazza@schrodinger.com";
  };

  isDeterminate = true;

  ai = {
    providers = {
      litellm = {
        host = "desk-nxst-001.schrodinger.com";
        port = 4000;
        endpoint = "http://desk-nxst-001.schrodinger.com:4000";
        localEndpoint = "http://localhost:4000";
        caddyEndpoint = "http://desk-nxst-001.schrodinger.com:8080/litellm";
        defaultLocalGroup = "local-coder";
        defaultCloudGroup = "coder-cloud-claude";
        modelGroups = {
          local-coder = "local-coder";
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
      claudeSonnet = "claude-sonnet-4-6";
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
}
