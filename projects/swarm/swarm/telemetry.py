"""OpenTelemetry wiring that ships every LangChain + OpenAI span to Phoenix.

Phoenix's live UI groups spans into a tree keyed by the root trace id, so
the LangGraph fan-out pattern (planner → N workers → reducer) renders as
a real swarm visualization out of the box.
"""

from __future__ import annotations

from openinference.instrumentation.langchain import LangChainInstrumentor
from openinference.instrumentation.openai import OpenAIInstrumentor
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

_initialized = False
_provider: TracerProvider | None = None


def init(endpoint: str, service_name: str = "swarm") -> None:
    """Idempotently configure the global tracer provider.

    Safe to call multiple times — subsequent calls are no-ops so the CLI
    and long-running server can both invoke it without double-instrumenting.
    """
    global _initialized, _provider
    if _initialized:
        return

    resource = Resource.create({"service.name": service_name})
    _provider = TracerProvider(resource=resource)
    _provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
    )
    trace.set_tracer_provider(_provider)

    # OpenInference auto-instruments both LangChain's runnables and the
    # OpenAI SDK used under the hood by langchain-openai / browser-use.
    # We attach both so spans are captured regardless of which path a
    # subagent happens to take through the stack.
    LangChainInstrumentor().instrument()
    OpenAIInstrumentor().instrument()

    _initialized = True


def shutdown() -> None:
    """Flush pending spans and tear down the provider.

    The CLI exits immediately after `run_sync` returns; without an
    explicit flush the BatchSpanProcessor's queue is dropped and spans
    never reach Phoenix. Call this at process end.
    """
    global _provider
    if _provider is not None:
        _provider.force_flush(timeout_millis=5000)
        _provider.shutdown()
        _provider = None
