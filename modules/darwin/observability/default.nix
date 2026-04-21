# Darwin OpenTelemetry Collector — pushes Mac telemetry to luna.
#
# This is the Mac-side counterpart to modules/nixos/observability. It runs
# a single otelcol-contrib daemon under launchd with three intake paths:
#
#   1. Loopback OTLP receiver (gRPC :4317, HTTP :4318) for in-process
#      pushes from local scripts and SDKs. scripts/reingest-auto.sh
#      curl-posts the reingest gauges to :4318/v1/metrics — this is
#      what populates the Grafana reingest tiles, since otelcol-contrib
#      has no node_exporter-style textfile-collector receiver. The
#      script also keeps writing the .prom file as a fallback for
#      hosts that do have node_exporter.
#
#   2. filelog receiver tailing opencode pipeline logs
#      (scripts/{ingest,reingest-auto}.log). They ship to Loki on luna.
#
#   3. hostmetrics receiver — CPU / memory / disk / load / network /
#      filesystem. Replaces the need to install/manage node_exporter
#      on every Mac.
#
# All three pipelines forward via OTLP/gRPC to luna's collector at
# luna:4317. The `resource` processor stamps host.name and
# service.namespace on every signal so Grafana queries can slice by
# `host_name` consistently across luna and all Macs (matches the
# claude-code OTel attribute convention in modules/darwin/claude-code).
#
# Why a local collector instead of curl-to-pushgateway / direct OTLP:
#   * pushgateway aggregates by job — we'd lose per-host slicing.
#   * Logs and metrics need different transports / endpoints — one
#     daemon owns both.
#   * Symmetric with luna's collector (same package, same config shape,
#     same OTLP egress) so adding receivers/exporters is one place.
#   * Local OTLP loopback means scripts don't need network reachability
#     to luna — the collector batches and retries on flaky LANs.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.darwinObservability;

  # Match claude-code module's host.name source — single attribute the
  # luna dashboards filter on.
  hostName = config.networking.hostName or "darwin";

  # Default OTLP target. luna.local mDNS isn't reliable from every Mac
  # (see CLAUDE.md / SETUP.md notes), so the bare hostname is the
  # working fallback. Override per-host via cfg.endpoint if mDNS works
  # on that LAN segment.
  defaultEndpoint = "luna:4317";

  # Conditionally-included pipeline fragments. We can't use lib.mkIf
  # inside the attrset that gets toJSON'd — mkIf becomes a literal
  # `{_type, condition, content}` triple in the output and the
  # collector rejects it. So toggle via plain Nix `if/then` here.
  debugExporterAttrs = lib.optionalAttrs cfg.debugExporter {
    debug.verbosity = "basic";
  };
  pipelineDebugExporters = lib.optional cfg.debugExporter "debug";

  configFile = pkgs.writeText "otelcol-darwin.yaml" (
    builtins.toJSON {
      receivers = {
        # ── OTLP intake (loopback) ───────────────────────────────────
        # Local-only OTLP endpoint so scripts can push metrics/logs/
        # traces directly without needing an SDK. scripts/reingest-
        # auto.sh in the obsidian repo posts JSON to
        # http://127.0.0.1:4318/v1/metrics for the reingest gauges
        # (otelcol-contrib has no textfile-collector receiver, so the
        # script's textfile write stays as a fallback for hosts
        # without this collector). gRPC port also bound for any local
        # SDK-based emitters.
        otlp.protocols = {
          grpc.endpoint = "127.0.0.1:${toString cfg.otlpGrpcPort}";
          http.endpoint = "127.0.0.1:${toString cfg.otlpHttpPort}";
        };

        # ── Host metrics (CPU, mem, disk, load, network) ─────────────
        hostmetrics = {
          collection_interval = "30s";
          scrapers = {
            cpu = { };
            memory = { };
            load = { };
            disk = { };
            filesystem = { };
            network = { };
          };
        };

        # opencode pipeline logs — the two append-mode files written
        # by scripts/ingest.sh and scripts/reingest-auto.sh. The
        # `add` stanza operator stamps a service.name on every log
        # entry's resource (host.name + service.namespace come from
        # the resource processor below). Field path syntax is dotted
        # per pkg/stanza/docs/operators/add.md.
        filelog = {
          include = cfg.logFiles;
          start_at = "end";
          include_file_name = true;
          include_file_path = true;
          operators = [
            {
              type = "add";
              field = "resource.service.name";
              value = "opencode-pipeline";
            }
          ];
        };
      };

      processors = {
        # Standard OTel hygiene processors, mirroring luna's collector.
        memory_limiter = {
          check_interval = "1s";
          limit_mib = 256;
        };
        batch = {
          timeout = "5s";
          send_batch_size = 1024;
        };
        # Stamp every signal with host identity so Grafana can slice
        # by host_name across all Macs + luna.
        resource = {
          attributes = [
            {
              key = "host.name";
              value = hostName;
              action = "upsert";
            }
            {
              key = "service.namespace";
              value = "darwin-host";
              action = "upsert";
            }
          ];
        };
      };

      exporters = {
        otlp = {
          endpoint = cfg.endpoint;
          tls.insecure = true;
        };
      }
      // debugExporterAttrs;

      service = {
        pipelines = {
          metrics = {
            receivers = [
              "hostmetrics"
              "otlp"
            ];
            processors = [
              "memory_limiter"
              "resource"
              "batch"
            ];
            exporters = [ "otlp" ] ++ pipelineDebugExporters;
          };
          logs = {
            receivers = [
              "filelog"
              "otlp"
            ];
            processors = [
              "memory_limiter"
              "resource"
              "batch"
            ];
            exporters = [ "otlp" ] ++ pipelineDebugExporters;
          };
        };
        telemetry.logs.level = cfg.logLevel;
      };
    }
  );
in
{
  options.local.darwinObservability = {
    enable = lib.mkEnableOption ''
      OpenTelemetry collector daemon that pushes this Mac's host metrics
      and opencode pipeline logs to luna's collector. Counterpart to the
      `local.observability` module on NixOS hosts.
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opentelemetry-collector-contrib;
      defaultText = lib.literalExpression "pkgs.opentelemetry-collector-contrib";
      description = "otelcol-contrib package to use.";
    };

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = defaultEndpoint;
      description = ''
        OTLP/gRPC endpoint on luna. Bare `luna` hostname by default
        because mDNS to `luna.local` is flaky from many Macs; override
        to `luna.local:4317` or `192.168.1.57:4317` per-host as needed.
      '';
    };

    otlpGrpcPort = lib.mkOption {
      type = lib.types.port;
      default = 4317;
      description = ''
        Port for the loopback OTLP/gRPC receiver. Local SDKs / scripts
        can push to `127.0.0.1:<port>` and the collector will relay to
        luna with the right host.name/service.namespace stamps.
      '';
    };

    otlpHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 4318;
      description = ''
        Port for the loopback OTLP/HTTP receiver. Used by curl-based
        emitters (e.g. scripts/reingest-auto.sh).
      '';
    };

    logFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/Users/casazza/Repositories/ocasazza/obsidian/scripts/ingest.log"
        "/Users/casazza/Repositories/ocasazza/obsidian/scripts/reingest-auto.log"
      ];
      description = ''
        Absolute paths to opencode log files to tail and ship to Loki
        via the OTel filelog receiver.
      '';
    };

    # textfileDir option intentionally not exposed: otelcol-contrib has
    # no node_exporter-style textfile receiver, so reingest metric
    # ingestion happens via the loopback OTLP/HTTP push path documented
    # at the top of this file. The script's .prom write remains as a
    # fallback for hosts that do run node_exporter (luna). Add a
    # `textfileDir` option here only if otelcol-contrib gains a
    # textfile receiver in a future release.

    debugExporter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add the `debug` exporter to every pipeline so signals are also
        printed to launchd's stdout. Useful during initial bring-up;
        leave off in steady state.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = "Collector internal log level.";
    };
  };

  config = lib.mkIf cfg.enable {
    # nix-darwin doesn't ship a `services.opentelemetry-collector`
    # module like NixOS does, so we manage the daemon directly under
    # launchd. Runs as the LaunchDaemon variant (system-wide, root) so
    # filelog can read root-owned files in /var/lib/node_exporter and
    # hostmetrics has access to the full system. KeepAlive restarts on
    # crash; throttle prevents launchd from hammering crash loops.
    launchd.daemons.opentelemetry-collector = {
      command = "${cfg.package}/bin/otelcol-contrib --config=${configFile}";
      serviceConfig = {
        Label = "local.opentelemetry-collector";
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardOutPath = "/var/log/opentelemetry-collector.out.log";
        StandardErrorPath = "/var/log/opentelemetry-collector.err.log";
        # Modest resource cap; Mac collectors are tiny.
        SoftResourceLimits.NumberOfFiles = 4096;
      };
    };

    # Ensure the log file directory exists. nix-darwin doesn't have
    # systemd.tmpfiles, so we create via launchd `RunAtLoad` of a
    # one-shot — but simpler: rely on otelcol creating its own logs
    # via the StandardOut/Err paths (launchd creates parent dirs).
  };
}
