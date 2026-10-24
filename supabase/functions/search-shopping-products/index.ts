// Self-contained so this file can also be deployed with Supabase's dashboard editor.
// No API key, raw upstream response, or search query is logged or returned to the client.
type JsonObject = Record<string, unknown>;
type Product = {
  id: string; source: "googleShopping"; title: string; detail: string; category: string;
  symbol: string; priceCents: number; imageURL: string | null; productURL: string;
  currencyCode: "USD"; merchant: string;
};
const windows = new Map<string, number[]>();
const cache = new Map<string, { expires: number; items: Product[] }>();
let publicSearches: number[] = [];
const jsonHeaders = { "Content-Type": "application/json", "Cache-Control": "no-store" };

class SearchError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}

export async function handleRequest(request: Request): Promise<Response> {
  const origin = request.headers.get("Origin");
  if (origin && origin !== "https://pocket-crew.vercel.app") return json({error:"Origin not allowed"},403);
  const response = request.method === "OPTIONS" ? new Response(null,{status:204}) : await handleSearch(request);
  if (origin) {
    response.headers.set("Access-Control-Allow-Origin",origin);
    response.headers.set("Access-Control-Allow-Methods","POST, OPTIONS");
    response.headers.set("Access-Control-Allow-Headers","authorization, apikey, content-type, x-client-info");
    response.headers.set("Vary","Origin");
  }
  return response;
}

async function handleSearch(request: Request): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const authorization = request.headers.get("Authorization");
    const payload = await readPayload(request);
    if (typeof payload.query !== "string" || payload.query.trim().length < 2 || payload.query.trim().length > 120) {
      throw new SearchError(400, "Search using 2–120 characters.");
    }
    if (payload.currency !== "USD") {
      throw new SearchError(400, "Live shopping currently supports US prices in USD only.");
    }
    const query = payload.query.trim();
    if (restricted(query)) throw new SearchError(400, "Try a family-friendly search such as books, games, or art supplies.");
    const base = env("SUPABASE_URL");
    let searchActor: string;
    if (typeof payload.childToken === "string") {
      if (!/^[0-9a-f]{64}$/.test(payload.childToken) || typeof payload.childPin !== "string" || !/^\d{6,8}$/.test(payload.childPin)) throw new SearchError(401,"Open your private child profile first.");
      const access = await fetch(`${base}/rest/v1/rpc/read_child_connection`,{method:"POST",headers:{apikey:publicKey(),"Content-Type":"application/json"},body:JSON.stringify({p_token:payload.childToken,p_pin:payload.childPin}),signal:AbortSignal.timeout(10_000)});
      const identity = object(await access.json());
      if (!access.ok || identity.error || typeof identity.child_id !== "string") throw new SearchError(401,"Your child connection needs attention. Unlock it again or ask a parent for help.");
      searchActor = "child:"+identity.child_id;
    } else if (payload.publicSearch === true) {
      // Catalog reads only: never grants family access or mutation permissions.
      // Shared fallback deliberately throttles clients when the gateway supplies no IP.
      const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "shared";
      searchActor = "public:" + ip;
    } else {
    if (!authorization?.startsWith("Bearer ")) throw new SearchError(401, "Sign in to search products.");
    const headers = { Authorization: authorization, apikey: publicKey() };
    const authResponse = await fetch(`${base}/auth/v1/user`, { headers, signal: AbortSignal.timeout(10_000) });
    if (!authResponse.ok) throw new SearchError(401, "Sign in again to search products.");
    const user = object(await authResponse.json());
    if (typeof user.id !== "string") throw new SearchError(401, "Sign in again to search products.");
    // Uses the signed-in user's JWT and RLS, never a service-role key. Child profiles use
    // their guardian-managed family session, just like the existing cloud adapter.
    const membershipURL = new URL(`${base}/rest/v1/family_guardians`);
    membershipURL.search = new URLSearchParams({ select: "family_id", user_id: `eq.${user.id}`, status: "eq.active", limit: "1" }).toString();
    const membership = await fetch(membershipURL, { headers, signal: AbortSignal.timeout(10_000) });
    if (!membership.ok) throw new SearchError(503, "Family access could not be checked. Try again shortly.");
    const families = await membership.json();
    if (!Array.isArray(families) || !families.length) throw new SearchError(403, "Create or join a family before searching.");
    searchActor = user.id;
    }
    enforceRateLimit(searchActor);
    const apiKey = Deno.env.get("SERPAPI_API_KEY") || Deno.env.get("SERPAI_API_KEY");
    if (!apiKey) throw new SearchError(503, "Live shopping is not configured yet. A parent can finish the Supabase setup.");

    // A short, bounded, in-memory cache reduces duplicate quota use. Both cache and
    // throttling are per worker, not a replacement for the provider's account quota.
    const cacheKey = query.toLowerCase();
    const cached = cache.get(cacheKey);
    if (cached && cached.expires > Date.now()) return json({ items: cached.items });
    if (payload.publicSearch === true) {
      publicSearches = publicSearches.filter(time => time > Date.now() - 3600_000);
      if (publicSearches.length >= 30) throw new SearchError(429, "Public shopping search has reached its allowance. Try again later.");
      publicSearches.push(Date.now());
    }
    const searchURL = new URL("https://serpapi.com/search.json");
    searchURL.search = new URLSearchParams({
      engine: "google_shopping", q: query, api_key: apiKey,
      google_domain: "google.com", gl: "us", hl: "en", location: "United States",
    }).toString();
    const response = await fetch(searchURL, { signal: AbortSignal.timeout(25_000), redirect: "error" });
    if (response.status === 429) throw new SearchError(429, "Shopping search has reached its allowance. Please try later.");
    if (!response.ok) throw new SearchError(502, "Google Shopping search is unavailable. Please try again later.");
    const body = object(await response.json());
    if (body.error) throw new SearchError(502, "Google Shopping search could not finish. Please try again later.");
    const items = normalizeProducts(body);
    if (cache.size >= 100) cache.delete(cache.keys().next().value!);
    cache.set(cacheKey, { expires: Date.now() + 5 * 60_000, items });
    return json({ items });
  } catch (error) {
    if (error instanceof SearchError) return json({ error: error.message }, error.status);
    // In particular, never expose a fetch error that might contain the API-key URL.
    return json({ error: "Shopping search could not connect. Please try again shortly." }, 502);
  }
}

export function normalizeProducts(body: unknown): Product[] {
  const root = object(body);
  const raw = [...array(root.shopping_results)];
  for (const group of array(root.categorized_shopping_results)) raw.push(...array(object(group).shopping_results));
  const items: Product[] = [];
  const seen = new Set<string>();
  // Deliberately exclude sponsored inline results and all installment-only prices.
  for (const value of raw.slice(0, 200)) {
    const item = object(value);
    const title = text(item.title, 240);
    const productId = text(item.product_id, 100);
    const priceCents = parseUSDPrice(item.price);
    const productURL = googleProductURL(item.product_link);
    if (!title || !productId || !productURL || priceCents === null || item.installment || restricted(title)) continue;
    const id = `google-shopping-${productId}`;
    if (seen.has(id)) continue;
    seen.add(id);
    const merchant = text(item.source, 100) || "Store listing";
    items.push({
      id, source: "googleShopping", title, merchant, currencyCode: "USD",
      detail: `${merchant} · US price snapshot; tax and shipping may be extra`,
      category: "Google Shopping", symbol: "shippingbox.fill", priceCents,
      imageURL: thumbnailURL(item.thumbnail), productURL,
    });
    if (items.length >= 20) break;
  }
  return items;
}

// Parse the displayed USD amount directly into integer cents, without multiplying floats.
// Reject ranges, other currencies, subscriptions, monthly payments and missing prices.
export function parseUSDPrice(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const match = value.trim().match(/^(?:US\$|\$)\s*((?:\d{1,3}(?:,\d{3})+|\d+))(?:\.(\d{1,2}))?$/);
  if (!match) return null;
  const cents = Number(match[1].replaceAll(",", "")) * 100 + Number((match[2] || "").padEnd(2, "0"));
  return Number.isSafeInteger(cents) && cents > 0 && cents <= 10_000_000 ? cents : null;
}

function googleProductURL(value: unknown): string | null {
  const url = httpsURL(value);
  if (!url || !["www.google.com", "google.com"].includes(url.hostname)) return null;
  if (!(url.pathname.startsWith("/shopping/product/") || (url.pathname === "/search" && url.searchParams.get("udm") === "28"))) return null;
  return url.href;
}
function thumbnailURL(value: unknown): string | null {
  const url = httpsURL(value);
  if (!url) return null;
  const host = url.hostname;
  // Google/SerpApi images only; arbitrary merchant trackers are not loaded in a child view.
  return ["gstatic.com", "googleusercontent.com", "serpapi.com"].some((domain) => host === domain || host.endsWith(`.${domain}`)) ? url.href : null;
}
function httpsURL(value: unknown): URL | null {
  if (typeof value !== "string" || value.length > 8192) return null;
  try { const url = new URL(value); return url.protocol === "https:" && !url.username && !url.password && !url.port ? url : null; }
  catch { return null; }
}
function restricted(value: string): boolean {
  // Basic safeguards, not a guarantee of age-appropriate results. Parents review all purchases.
  return /\b(porn|pornographic|sex toys?|dildos?|vibrators?|tobacco|cigarettes?|vapes?|vaping|cannabis|marijuana|vodka|whiskey|whisky|firearms?|handguns?|ammunition)\b/i.test(value);
}
function object(value: unknown): JsonObject { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {}; }
function array(value: unknown): unknown[] { return Array.isArray(value) ? value : []; }
function text(value: unknown, max: number): string { return typeof value === "string" ? value.trim().slice(0, max) : ""; }
function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new SearchError(503, "Shopping service setup is incomplete.");
  return value;
}
function publicKey(): string {
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (keys) { const key = object(JSON.parse(keys)).default; if (typeof key === "string" && key) return key; }
  return env("SUPABASE_ANON_KEY");
}
function enforceRateLimit(userId: string): void {
  const now = Date.now();
  for (const [key, times] of windows) if (!times.some((time) => time > now - 60_000)) windows.delete(key);
  const recent = (windows.get(userId) || []).filter((time) => time > now - 60_000);
  if (recent.length >= 6 || (!windows.has(userId) && windows.size >= 1000)) throw new SearchError(429, "Please wait a minute before searching again.");
  recent.push(now); windows.set(userId, recent);
}
async function readPayload(request: Request): Promise<JsonObject> {
  const reader = request.body?.getReader();
  if (!reader) throw new SearchError(400, "A search is required.");
  const chunks: Uint8Array[] = []; let length = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    length += value.length;
    if (length > 4096) { await reader.cancel(); throw new SearchError(413, "Search request is too large."); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try { return object(JSON.parse(new TextDecoder().decode(bytes))); }
  catch { throw new SearchError(400, "Send a valid search request."); }
}
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: status === 429 ? { ...jsonHeaders, "Retry-After": "60" } : jsonHeaders });
}

if (typeof Deno !== "undefined") Deno.serve(handleRequest);
