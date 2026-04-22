"""Phoenix / OpenInference wiring — same pattern as ~/swarm.

Tracer is lazy: if Phoenix is unreachable or the env is missing the
collector endpoint, we silently fall back to a no-op provider so the
pipeline keeps working in dev shells.
"""

from __future__ import annotations

import logging
import os

log = logging.getLogger(__name__)

_initialized = False


def init_tracing(service_name: str = "ingest") -> None:
    global _initialized
    if _initialized:
        return
    _initialized = True

    endpoint = os.environ.get("PHOENIX_COLLECTOR_ENDPOINT", "")
    if not endpoint:
        log.debug("PHOENIX_COLLECTOR_ENDPOINT not set — skipping tracing init")
        return

    try:
        from openinference.instrumentation.langchain import LangChainInstrumentor
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
    except ImportError as exc:
        log.warning("tracing deps missing (%s) — skipping", exc)
        return

    try:
        provider = TracerProvider(resource=Resource.create({"service.name": service_name}))
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint)))
        trace.set_tracer_provider(provider)
        LangChainInstrumentor().instrument(tracer_provider=provider)
        log.info("phoenix tracing initialized → %s", endpoint)
    except Exception as exc:  # noqa: BLE001
        log.warning("phoenix tracing init failed (%s) — continuing without traces", exc)
