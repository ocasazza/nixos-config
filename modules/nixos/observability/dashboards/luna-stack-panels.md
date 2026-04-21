# luna-stack dashboard — panel design reference

Notes for building the Grafana dashboard whose JSON should sit next to
this file as `luna-stack.json`. Build interactively in Grafana, save,
then export the JSON here. `claude-code.json` (Anthropic's published
dashboard) covers the standard cost/token/session views — this one
adds the things that dashboard doesn't know about: my reingest
pipeline, vLLM serving health, and luna's heterogeneous-GPU thermals.

Each panel: **title** | question it answers | PromQL | viz | rationale.

## Row 1 — Vault ingestion health

1. **Time since last reingest run** | "Did the launchd timer fire?" |
   `time() - reingest_last_run_timestamp_seconds` |
   stat (red >4500s, yellow >3900s) | hourly cadence; >75 min = launchd
   or the flock broke silently.

2. **Reingest candidate backlog** | "How many `ingest/auto` notes are
   queued?" | `reingest_candidates_total` | timeseries | persistent
   non-zero = `/reingest` is failing to swap `ingest/auto` →
   `ingest/done`, so the same notes burn cost every hour.

3. **Reingest success rate (24h)** | "Are runs actually succeeding?" |
   `1 - (sum_over_time((reingest_last_exit_code > bool 0)[24h:1h]) / 24)` |
   gauge | gauge sampled hourly; subquery aligns to launchd cadence.

4. **Reingest run timeline** | "When did runs happen and which failed?" |
   `reingest_last_exit_code` | state timeline | gaps = missed runs,
   red bars = exit != 0.

## Row 2 — opencode workload

5. **Cost burn rate ($/hour)** | "How fast am I spending right now?" |
   `sum(rate(opencode_cost_usd_total[1h])) * 3600` | stat |
   `rate` not `irate` — exporter polls SQLite on an interval, `irate`
   spikes artificially on every scrape.

6. **Cost by project (24h)** |
   `topk(5, sum by (project) (increase(opencode_cost_usd_total[24h])))` |
   bar chart.

7. **Cost per session** | "Are sessions getting more expensive?" |
   `sum(increase(opencode_cost_usd_total[1h])) / sum(increase(opencode_sessions_total[1h]))` |
   timeseries | rising trend = context bloat or weaker cache reuse.

8. **Cache effectiveness (read/write ratio)** |
   `sum(rate(opencode_tokens_total{type="cache_read"}[1h])) / sum(rate(opencode_tokens_total{type="cache_write"}[1h]))` |
   timeseries | NOT `read/(read+write)` (bounded [0,1] hides
   magnitude). Healthy long-context workflow: 5x–20x. Below 1 =
   caching is net-negative (paying 1.25x to write context never read).

9. **Token mix by type** |
   `sum by (type) (rate(opencode_tokens_total[5m]))` | timeseries
   stacked | watch for `output` creeping above `input` — runaway loop.

10. **Model distribution** | "Hitting luna or falling back to Anthropic?" |
    `sum by (model) (increase(opencode_sessions_total[24h]))` | table |
    table with model + provider + count + cost beats a pie chart.

## Row 3 — luna vLLM serving

11. **TTFT p50/p95/p99** |
    `histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))` |
    timeseries | aggregate `sum by (le)` *before* `histogram_quantile`,
    otherwise you get the average of quantiles (meaningless). Recording
    rule recommended — bucket cardinality on a 30B MoE makes this slow.

12. **Throughput (output tokens/s)** |
    `sum(rate(vllm:generation_tokens_total[5m]))` | stat + sparkline |
    real ceiling on 3090 Ti + 4000 SFF Ada tp=2 ≈ 40–80 tok/s for AWQ
    30B-A3B.

13. **KV cache pressure** | `vllm:gpu_cache_usage_perc` | gauge
    (yellow >0.8, red >0.95) | above ~90% vLLM evicts prefix cache —
    kills cache_read effectiveness in panel 8.

14. **Queue depth** | `vllm:num_requests_waiting` and
    `vllm:num_requests_running` | timeseries | waiting >0 sustained =
    saturated; single-user workload should sit at 0.

15. **Request error rate** |
    `sum(rate(vllm:request_success_total{finished_reason!="stop"}[5m])) / sum(rate(vllm:request_success_total[5m]))` |
    stat | `finished_reason` distinguishes `stop` (good) from
    `length`/`abort` (bad).

## Row 4 — luna hardware

16. **Per-GPU utilization** | `nvidia_gpu_duty_cycle{gpu=~"0|1"}` |
    timeseries (2 series) | asymmetric VRAM (24/20 GiB) but vLLM splits
    weights evenly — expect 4000 SFF to bottleneck first.

17. **VRAM headroom per card** |
    `nvidia_gpu_memory_total_bytes - nvidia_gpu_memory_used_bytes`
    per `gpu` | bar gauge | absolute headroom in GiB > % when cards
    differ.

18. **GPU temp & power** | `nvidia_gpu_temperature_celsius` and
    `nvidia_gpu_power_watts` | timeseries (dual axis) | the 70W SFF Ada
    thermal-throttles hard; correlate with TTFT spikes in row 3.

## Row 5 — Cross-cutting

19. **Cost per ingested note** |
    `sum(rate(opencode_cost_usd_total{project="obsidian"}[1h])) / clamp_min(rate(reingest_candidates_total[1h]), 1)` |
    timeseries | `clamp_min` avoids div-by-zero. Recording rule
    recommended.

20. **Cost per 1M tokens by provider** |
    `sum by (provider) (rate(opencode_cost_usd_total[24h])) / sum by (provider) (rate(opencode_tokens_total[24h])) * 1e6` |
    table | luna should show ~$0; non-zero = mislabeled exporter.

## Recording rules (defined in observability/default.nix)

- `job:vllm_ttft_p95:5m` — precomputed p95 TTFT
- `job:opencode_cost_per_note:1h` — panel 19
- `job:opencode_cache_ratio:1h` — panel 8

## Alerts (defined in observability/default.nix, fire to Grafana UI)

- No reingest run in 26h
- Reingest exit != 0 for 2 consecutive runs
- Reingest backlog stuck (`candidates_total > 0` for 3h)
- vLLM queue `waiting > 5` for 5m
- KV cache pressure `> 0.95` for 10m
- Cache ratio collapsed (`< 1` for 30m)
- Cost burn anomaly (hourly cost > 3x trailing 24h avg)
- GPU thermal throttle (SFF Ada `temp > 83°C` for 5m)
- luna vLLM unreachable (`up{job="vllm-coder"} == 0` for 2m)
