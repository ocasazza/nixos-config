// Vertex AI passthrough plugin for opencode.
//
// Uses @ai-sdk/google-vertex/anthropic which constructs proper Vertex AI
// URLs (e.g. /v1beta1/projects/.../publishers/anthropic/models/...:streamRawPredict).
// The plugin's custom fetch rewrites these URLs to go through LiteLLM's
// /vertex passthrough (which dumb-forwards to vertex-proxy.sdgr.app), and
// replaces the SDK's ADC access token with a fresh gcloud identity token.
//
// URL rewrite: https://{region}-aiplatform.googleapis.com/{path}
//           → http://litellm.pdx-nxst-001.schrodinger.com:8080/vertex/{path}
//           with v1beta1 → v1 (Vertex AI Anthropic endpoint requires v1)

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getIdentityToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 5 * 60 * 1000) {
    return cachedToken.token;
  }
  const proc =
    Bun.$`CLOUDSDK_CORE_PROJECT=@projectId@ gcloud auth print-identity-token`;
  const token = (await proc.text()).trim();
  const payload = JSON.parse(atob(token.split(".")[1]));
  cachedToken = { token, expiresAt: payload.exp * 1000 };
  return token;
}

async function vertexProxyFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const token = await getIdentityToken();

  const url = new URL(typeof input === "string" ? input : input.toString());

  // Rewrite Google Vertex AI URLs → LiteLLM /vertex passthrough
  if (url.hostname.endsWith("-aiplatform.googleapis.com")) {
    const path = url.pathname.replace(/^\/v1beta1\//, "/v1/");
    url.hostname = "litellm.pdx-nxst-001.schrodinger.com";
    url.port = "8080";
    url.pathname = `/vertex${path}`;
    url.protocol = "http:";
  }

  const headers = new Headers(init?.headers);
  // Replace ADC access token with gcloud identity token
  headers.set("Authorization", `Bearer ${token}`);

  return globalThis.fetch(url.toString(), { ...init, headers });
}

export default async () => ({
  config: async (config) => {
    const vp = config.provider?.["vertex-proxy"];
    if (vp) {
      vp.options = vp.options || {};
      vp.options.fetch = vertexProxyFetch;
    }
  },
});
