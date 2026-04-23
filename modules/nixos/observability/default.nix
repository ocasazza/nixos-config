# Local observability stack: Prometheus + Grafana + OTel Collector + exporters.
#
# Designed for a single host (luna) where the metrics pipeline lives
# next to the workloads it watches. No remote write, no alertmanager —
# add those when you have a second host worth comparing against.
#
# Topology:
#
#   ┌─ Claude Code (every machine) ──► OTLP gRPC :4317 ─┐ metrics+logs
#   ┌─ opencode + plugin-otel ───────► OTLP gRPC :4317 ─┤
#   ┌─ batch jobs / off-LAN macs ────► pushgateway :9091┤
#   │                                                   ▼
#   │                            ┌── otel-collector ────┐
#   │                            │  receivers: otlp,    │
#   │                            │             journald │
#   │                            │  exporters:          │
#   │                            │    prometheus :8889  │ (metrics)
#   │                            │    loki              │ (logs)
#   │                            └──────────────────────┘
#   │                                                   │
#   ├─ node_exporter        :9100 ◄─── prometheus :9090 ┤
#   ├─ nvidia-gpu-exporter  :9835 ◄────────────────────┤
#   ├─ vllm-coder /metrics  :8000 ◄────────────────────┤
#   ├─ pushgateway          :9091 ◄────────────────────┤
#   │                                                   │
#   │                            ┌── loki :3100 ◄───────┘ (logs sink)
#   │                            │
#   │                            └── grafana :3000 ─────┐
#   │                                datasources:       │
#   │                                  • Prometheus      │
#   │                                  • Loki            │
#   │                                dashboards:         │
#   │                                  • claude-code (Anthropic)
#   │                                  • luna-stack (custom)
#   └─────────────────────────────────────────────────────┘
#
# What each scrape source contributes:
#   * node_exporter        — CPU/mem/disk/net + textfile collector at
#                            /var/lib/node_exporter/textfile/*.prom
#                            for ad-hoc batch metrics (reingest runs).
#   * nvidia-gpu-exporter  — per-GPU util, VRAM, temp, power. Wraps
#                            nvidia-smi; works on consumer cards (no
#                            DCGM/datacenter driver needed).
#   * vllm                 — vLLM exposes Prometheus natively at
#                            <host>:<port>/metrics; auto-scraped per
#                            entry in `local.vllm.services`.
#   * otel-collector       — central funnel for Claude Code (built-in
#                            OTel) and opencode (via @devtheops/opencode-
#                            plugin-otel). Re-exports as Prometheus.
#
# To enable on a workload host:
#   programs.claude-code.environment = {
#     CLAUDE_CODE_ENABLE_TELEMETRY = "1";
#     OTEL_METRICS_EXPORTER = "otlp";
#     OTEL_LOGS_EXPORTER = "otlp";
#     OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
#     OTEL_EXPORTER_OTLP_ENDPOINT = "http://luna.local:4317";
#     OTEL_METRIC_EXPORT_INTERVAL = "10000";
#   };
#
# For opencode, add to project's opencode.json:
#   "plugin": ["@devtheops/opencode-plugin-otel"]
# and export OPENCODE_ENABLE_TELEMETRY=1 + OPENCODE_OTLP_ENDPOINT.
#
# Verify (from luna):
#   curl http://localhost:9090/-/healthy        # prometheus
#   curl http://localhost:3000/api/health       # grafana
#   curl http://localhost:9100/metrics | head   # node
#   curl http://localhost:9835/metrics | head   # nvidia
#   curl http://localhost:8889/metrics | head   # otel→prom bridge
#   curl http://localhost:8000/metrics | head   # vllm-coder
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.observability;
  vllmCfg =
    config.local.vllm or {
      enable = false;
      services = { };
    };

  # One Prometheus scrape job per vLLM service so adding an embedding
  # endpoint later auto-wires the dashboard.
  vllmScrapeJobs = mapAttrsToList (name: svc: {
    job_name = "vllm-${name}";
    metrics_path = "/metrics";
    static_configs = [
      {
        targets = [ "127.0.0.1:${toString svc.port}" ];
        labels = {
          instance = name;
          model = svc.model;
        };
      }
    ];
  }) vllmCfg.services;

  # Stage the Anthropic-published Claude Code dashboard as a provisioned
  # file Grafana picks up on start. Custom dashboards in the same dir
  # are also surfaced — see ./dashboards/.
  dashboardsDir = pkgs.runCommand "grafana-dashboards" { } ''
    mkdir -p $out
    cp -r ${./dashboards}/. $out/
  '';
in

{
  options.local.observability = {
    enable = mkEnableOption "local Prometheus + Grafana + OTel stack";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open Grafana (3000), Prometheus (9090), and the OTLP receivers
        (4317 gRPC, 4318 HTTP) on the host firewall. Off by default —
        Grafana ships with a default admin password and the OTLP
        endpoints are unauthenticated.
      '';
    };

    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = ''
        How many days of metrics Prometheus keeps on disk. At 15s scrape
        and the exporters here, expect roughly 1 GiB / month.
      '';
    };

    scrapeInterval = mkOption {
      type = types.str;
      default = "15s";
      description = "Default Prometheus scrape interval.";
    };

    textfileDir = mkOption {
      type = types.path;
      default = "/var/lib/node_exporter/textfile";
      description = ''
        Directory the node_exporter `textfile` collector reads. Drop
        `*.prom` files here from cron / launchd / scripts to surface
        ad-hoc batch metrics. Used by `scripts/reingest-auto.sh` for
        the Obsidian reingest pipeline.
      '';
    };

    grafana = {
      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Grafana HTTP port.";
      };

      domain = mkOption {
        type = types.str;
        default = "luna.local";
        description = ''
          Public hostname Grafana renders into URLs (alert links, share
          links). Keep aligned with how the box is actually reached.
        '';
      };

      adminPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Initial admin password (set on first start; ignored on later
          starts unless the admin user is reset). Plaintext — fine for
          a LAN-only box. Use `adminPasswordFile` if you'd rather not
          commit it.
        '';
      };

      adminPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/grafana-admin";
        description = ''
          Path to a file holding the admin password. Takes precedence
          over `adminPassword`. Use sops-nix / agenix for the secret.
        '';
      };
    };

    otelCollector = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Run the OpenTelemetry Collector as the OTLP intake for Claude
          Code, opencode (via @devtheops/opencode-plugin-otel), and any
          other OTel-emitting workload. Re-exports as Prometheus on
          :8889 which the local Prometheus scrapes.
        '';
      };

      grpcPort = mkOption {
        type = types.port;
        default = 4317;
        description = "OTLP gRPC receiver port.";
      };

      httpPort = mkOption {
        type = types.port;
        default = 4318;
        description = "OTLP HTTP receiver port.";
      };

      prometheusPort = mkOption {
        type = types.port;
        default = 8889;
        description = "Port the Prometheus exporter binds to.";
      };

      metricExpiration = mkOption {
        type = types.str;
        default = "180m";
        description = ''
          How long the prometheus exporter retains a metric after the
          last datapoint. Long enough to cover sporadic Claude Code
          sessions; short enough that decommissioned hosts age out.
        '';
      };
    };

    loki = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Run single-binary Loki and route both Claude Code's OTLP logs
          and the local systemd journal (via the OTel collector's contrib
          `journald` receiver) into it. Filesystem storage, no object
          store — fine for a single host.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 3100;
        description = "Loki HTTP port.";
      };

      retentionDays = mkOption {
        type = types.int;
        default = 14;
        description = ''
          How many days of logs Loki keeps. Lower than Prometheus
          retention because logs grow ~10x faster than metrics.
        '';
      };
    };

    pushgateway = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Run Prometheus Pushgateway so off-LAN / batch jobs (Macs on
          cellular, GitHub Actions, opencode runs from a coffee-shop
          laptop) can push metrics over a single outbound HTTP request
          instead of being scraped. The port is opened by `openFirewall`
          since the entire point is reachability from outside the host.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 9091;
        description = "Pushgateway HTTP port.";
      };
    };
  };

  config = mkIf cfg.enable {
    # ── Prometheus ─────────────────────────────────────────────────────
    services.prometheus = {
      enable = true;
      port = 9090;
      retentionTime = "${toString cfg.retentionDays}d";

      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = cfg.scrapeInterval;
      };

      # Recording rules precompute the heavy queries used in
      # ./dashboards/luna-stack-panels.md. PromQL `histogram_quantile`
      # over wide-cardinality vLLM buckets and per-project cost ratios
      # are slow to evaluate at dashboard refresh rate.
      ruleFiles = [
        (pkgs.writeText "luna-stack-rules.yml" (
          builtins.toJSON {
            groups = [
              {
                name = "luna-stack-recording";
                interval = "30s";
                rules = [
                  {
                    record = "job:vllm_ttft_p95:5m";
                    expr = "histogram_quantile(0.95, sum by (le, instance) (rate(vllm:time_to_first_token_seconds_bucket[5m])))";
                  }
                  {
                    record = "job:opencode_cost_per_note:1h";
                    expr = ''sum(rate(opencode_cost_usd_total{project="obsidian"}[1h])) / clamp_min(rate(reingest_candidates_total[1h]), 1)'';
                  }
                  {
                    record = "job:opencode_cache_ratio:1h";
                    expr = ''sum(rate(opencode_tokens_total{type="cache_read"}[1h])) / clamp_min(sum(rate(opencode_tokens_total{type="cache_write"}[1h])), 1)'';
                  }
                ];
              }
              {
                name = "luna-stack-alerts";
                interval = "1m";
                rules = [
                  {
                    alert = "ReingestStale";
                    expr = "time() - reingest_last_run_timestamp_seconds > 93600";
                    for = "5m";
                    labels.severity = "warning";
                    annotations.summary = "No reingest run in over 26h — launchd timer or flock broke.";
                  }
                  {
                    alert = "ReingestFailing";
                    expr = "reingest_last_exit_code != 0";
                    for = "2h";
                    labels.severity = "warning";
                    annotations.summary = "Reingest has exited non-zero for 2+ consecutive runs.";
                  }
                  {
                    alert = "ReingestBacklogStuck";
                    expr = "reingest_candidates_total > 0";
                    for = "3h";
                    labels.severity = "warning";
                    annotations.summary = "Candidates_total > 0 for 3h — notes aren't being tag-swapped to ingest/done.";
                  }
                  {
                    alert = "VllmQueueSaturated";
                    expr = "vllm:num_requests_waiting > 5";
                    for = "5m";
                    labels.severity = "warning";
                    annotations.summary = "vLLM queue depth > 5 sustained — luna is saturated.";
                  }
                  {
                    alert = "VllmKVCacheHigh";
                    expr = "vllm:gpu_cache_usage_perc > 0.95";
                    for = "10m";
                    labels.severity = "warning";
                    annotations.summary = "KV cache > 95% for 10m — vLLM is evicting prefix cache, killing cache reuse.";
                  }
                  {
                    alert = "OpencodeCacheRatioCollapsed";
                    expr = "job:opencode_cache_ratio:1h < 1";
                    for = "30m";
                    labels.severity = "warning";
                    annotations.summary = "Cache reads < cache writes — paying to write context that's never read.";
                  }
                  {
                    alert = "GpuThermalThrottle";
                    # Index 1 is the RTX 4000 SFF Ada (70W TDP, throttles at 83°C).
                    # Adjust gpu label if nvidia-gpu-exporter uses a different one.
                    expr = ''nvidia_gpu_temperature_celsius{gpu="1"} > 83'';
                    for = "5m";
                    labels.severity = "warning";
                    annotations.summary = "RTX 4000 SFF Ada > 83°C for 5m — thermal throttle imminent.";
                  }
                  {
                    alert = "VllmCoderDown";
                    expr = ''up{job="vllm-coder"} == 0'';
                    for = "2m";
                    labels.severity = "critical";
                    annotations.summary = "luna's vLLM coder endpoint is unreachable.";
                  }
                ];
              }
            ];
          }
        ))
      ];

      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "127.0.0.1:9090" ]; } ];
        }
        {
          job_name = "node";
          static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
        }
        {
          job_name = "nvidia-gpu";
          static_configs = [ { targets = [ "127.0.0.1:9835" ]; } ];
        }
      ]
      ++ optional cfg.otelCollector.enable {
        job_name = "otel-collector";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString cfg.otelCollector.prometheusPort}" ];
          }
        ];
      }
      ++ optional cfg.pushgateway.enable {
        job_name = "pushgateway";
        # honor_labels keeps the `instance` and `job` labels the pusher
        # set, instead of letting prometheus rewrite them to point at
        # the pushgateway itself — otherwise every batch job appears as
        # "pushgateway" and you can't tell them apart.
        honor_labels = true;
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString cfg.pushgateway.port}" ];
          }
        ];
      }
      ++ vllmScrapeJobs;

      pushgateway = mkIf cfg.pushgateway.enable {
        enable = true;
        web.listen-address = ":${toString cfg.pushgateway.port}";
      };

      exporters = {
        node = {
          enable = true;
          port = 9100;
          enabledCollectors = [
            "systemd"
            "processes"
            "textfile"
          ];
          extraFlags = [
            "--collector.textfile.directory=${cfg.textfileDir}"
          ];
        };

        nvidia-gpu = {
          enable = true;
          port = 9835;
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.textfileDir} 0777 root root -"
    ];

    # ── OpenTelemetry Collector (OTLP intake) ──────────────────────────
    # Mirror of Anthropic's reference pipeline from
    # github.com/anthropics/claude-code-monitoring-guide, adapted to a
    # single-process collector (no Docker Compose).
    services.opentelemetry-collector = mkIf cfg.otelCollector.enable {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;

      settings = {
        receivers = {
          otlp.protocols = {
            grpc.endpoint = "0.0.0.0:${toString cfg.otelCollector.grpcPort}";
            http.endpoint = "0.0.0.0:${toString cfg.otelCollector.httpPort}";
          };
        }
        // optionalAttrs cfg.loki.enable {
          # contrib `journald` receiver tails the local systemd journal
          # so Loki gets every unit's logs (vllm-coder, ollama, sshd...)
          # tagged with `_SYSTEMD_UNIT` → exposed as the `unit` resource
          # attribute. The collector runs `journalctl -f` under the hood.
          journald = {
            directory = "/var/log/journal";
            priority = "info";
          };
        };

        processors = {
          batch = {
            timeout = "1s";
            send_batch_size = 1024;
          };
          memory_limiter = {
            check_interval = "1s";
            limit_mib = 512;
          };
        };

        exporters = {
          prometheus = {
            endpoint = "0.0.0.0:${toString cfg.otelCollector.prometheusPort}";
            send_timestamps = true;
            metric_expiration = cfg.otelCollector.metricExpiration;
            enable_open_metrics = true;
            # Don't strip the resource attributes Claude Code attaches
            # (user.account_uuid, host.name, service.version) — they're
            # the only way to slice cost across machines.
            resource_to_telemetry_conversion.enabled = true;
          };
          # Forward spans to Phoenix via OTLP/HTTP protobuf. Phoenix's
          # receiver rejects OTLP/HTTP JSON with "Unsupported content
          # type" — which breaks opencode's Effect runtime that only
          # exports JSON (`effect/unstable/observability.Otlp.layerJson`).
          # Solution: point every OTLP/HTTP JSON client (opencode on the
          # Mac fleet, ad-hoc scripts) at this otelcol's :4318 intake,
          # and let the otelcol re-serialize as protobuf on the way out.
          "otlphttp/phoenix" = {
            endpoint = "http://127.0.0.1:6006";
            tls.insecure = true;
          };
        }
        // optionalAttrs cfg.loki.enable {
          # contrib `loki` exporter speaks Loki's push API directly. We
          # turn resource attributes into stream labels so a Grafana
          # query like `{service_name="claude-code", host_name="luna"}`
          # works without further parsing.
          loki = {
            endpoint = "http://127.0.0.1:${toString cfg.loki.port}/loki/api/v1/push";
            default_labels_enabled = {
              exporter = false;
              job = true;
              instance = true;
              level = true;
            };
          };
        };

        service = {
          pipelines = {
            metrics = {
              receivers = [ "otlp" ];
              processors = [
                "memory_limiter"
                "batch"
              ];
              exporters = [ "prometheus" ];
            };
            # Traces pipeline: OTLP intake → Phoenix. Dedicated so
            # opencode spans coming in as JSON get re-encoded as
            # protobuf by the otlphttp exporter before hitting Phoenix's
            # protobuf-only receiver.
            traces = {
              receivers = [ "otlp" ];
              processors = [
                "memory_limiter"
                "batch"
              ];
              exporters = [ "otlphttp/phoenix" ]; # quoted key above matches this pipeline ref
            };
          }
          // optionalAttrs cfg.loki.enable {
            # Logs pipeline merges:
            #   * otlp     — Claude Code / opencode tool calls, decisions
            #   * journald — every systemd unit on this host
            # Both flow through the same batch+memory_limiter and land in
            # Loki, queryable side-by-side in the same Grafana panel.
            logs = {
              receivers = [
                "otlp"
                "journald"
              ];
              processors = [
                "memory_limiter"
                "batch"
              ];
              exporters = [ "loki" ];
            };
          };
          telemetry = {
            logs.level = "info";
            # Default internal-metrics listener is `127.0.0.1:8888` —
            # collides with seaweedfs-filer (which wants `0.0.0.0:8888`
            # by default). Move to 8893 so both can run; seaweedfs uses
            # 8888-8892 for master/volume/filer/s3 + their metrics ports.
            #
            # Old `metrics.address` is deprecated in collector ≥ 0.124.
            # Use the new `metrics.readers` shape.
            metrics.readers = [
              {
                pull.exporter.prometheus = {
                  host = "127.0.0.1";
                  port = 8893;
                };
              }
            ];
          };
        };
      };
    };

    # ── Loki (logs) ────────────────────────────────────────────────────
    # Single-binary Loki backed by the local filesystem. Fine for one
    # host: no object store, no microservices split, no replication.
    # Bumps to a real backend (S3/MinIO) once we have a second host.
    # The journald receiver lives inside the OTel collector above, so
    # there's no separate promtail / grafana-alloy daemon to manage.
    services.loki = mkIf cfg.loki.enable {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_port = cfg.loki.port;
          grpc_listen_port = 9096;
        };
        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/var/lib/loki";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config = {
          retention_period = "${toString (cfg.loki.retentionDays * 24)}h";
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
          allow_structured_metadata = true;
        };
        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };
        # Single-binary mode: run all rings/components in one process.
        analytics.reporting_enabled = false;
      };
    };

    # The OTel collector's `journald` receiver runs `journalctl` to
    # follow /var/log/journal. journalctl reads its own group ACL, so
    # add the collector's service user to systemd-journal — otherwise
    # the receiver fails with "permission denied" on every line.
    systemd.services.opentelemetry-collector.serviceConfig.SupplementaryGroups = mkIf cfg.loki.enable [
      "systemd-journal"
    ];

    # ── Grafana ────────────────────────────────────────────────────────
    services.grafana = {
      enable = true;

      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = cfg.grafana.port;
          domain = cfg.grafana.domain;
          root_url = "http://${cfg.grafana.domain}:${toString cfg.grafana.port}/";
        };

        "auth.anonymous".enabled = false;

        # Make the categorized links + health-tile homepage the landing
        # view instead of Grafana's stock empty home. Path must match
        # where the provisioner copies the file (see dashboardsDir +
        # `provision.dashboards.settings.providers[].options.path`).
        dashboards.default_home_dashboard_path = "${dashboardsDir}/homepage.json";

        security = mkMerge [
          {
            # NixOS 26.05+ requires this be set explicitly. Used for
            # encrypting datasource credentials at rest in Grafana's DB.
            # Hard-coded is acceptable on a LAN-only box with no
            # sensitive datasource secrets; rotate via secret_key /
            # adminPasswordFile + sops-nix when that changes.
            secret_key = "d6de19aca69ec2df40cb81afceb27f00";
          }
          (mkIf (cfg.grafana.adminPassword != null) {
            admin_password = cfg.grafana.adminPassword;
          })
          (mkIf (cfg.grafana.adminPasswordFile != null) {
            admin_password = "$__file{${toString cfg.grafana.adminPasswordFile}}";
          })
        ];

        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
      };

      provision = {
        enable = true;

        # Force re-provisioning of these datasource names — Grafana
        # otherwise keeps the row from a previous provisioning run with
        # a stale uid, and the new (uid = "prometheus") provisioning
        # then fails with "data source not found". This deletes the
        # old rows on every Grafana start so the settings block below
        # is the source of truth.
        datasources.settings.deleteDatasources = [
          {
            name = "Prometheus";
            orgId = 1;
          }
        ]
        ++ optional cfg.loki.enable {
          name = "Loki";
          orgId = 1;
        };

        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
        ]
        ++ optional cfg.loki.enable {
          name = "Loki";
          uid = "loki";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:${toString cfg.loki.port}";
          jsonData = {
            maxLines = 5000;
            timeout = 30;
          };
        };

        # Provision dashboards from the module's ./dashboards/ dir.
        # Drop additional .json files there (or override with
        # `services.grafana.provision.dashboards.settings`) and they
        # show up in Grafana on next start.
        dashboards.settings.providers = [
          {
            name = "luna-stack";
            type = "file";
            updateIntervalSeconds = 30;
            allowUiUpdates = true;
            options.path = "${dashboardsDir}";
          }
        ];
      };
    };

    # ── Firewall ───────────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      [
        cfg.grafana.port
        9090 # prometheus
      ]
      ++ optionals cfg.otelCollector.enable [
        cfg.otelCollector.grpcPort
        cfg.otelCollector.httpPort
      ]
      ++ optional cfg.pushgateway.enable cfg.pushgateway.port
      # Loki + exporters intentionally NOT opened — Prometheus and
      # Grafana reach them over loopback. Open per-service for
      # federation / cross-host log queries later.
    );
  };
}
