import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const jsonHeaders = { "Content-Type": "application/json" };
const requestWindows = new Map<string, number[]>();
let cachedToken: { value: string; expiresAt: number } | null = null;

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) throw new SearchError(401, "Authentication required");
    const userClient = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await userClient.auth.getUser();
    if (error || !data.user) throw new SearchError(401, "Authentication required");
    enforceRateLimit(data.user.id);

    const payload = await request.json();
    const query = String(payload.query ?? "").trim().slice(0, 120);
    if (query.length < 2) throw new SearchError(400, "Search for at least two characters");
    const marketplace = Deno.env.get("AMAZON_MARKETPLACE") ?? "www.amazon.com";
    const token = await creatorsAccessToken();
    const response = await fetch("https://creatorsapi.amazon/catalog/v1/searchItems", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        "x-marketplace": marketplace,
      },
      body: JSON.stringify({
        keywords: query,
        itemCount: 10,
        marketplace,
        partnerTag: requiredEnv("AMAZON_ASSOCIATE_PARTNER_TAG"),
        searchIndex: "All",
        resources: ["images.primary.medium", "itemInfo.title", "offersV2.listings.price"],
      }),
    });
    const body = await response.json();
    if (!response.ok) {
      console.error("Creators API search failed", response.status, body);
      throw new SearchError(502, "Amazon product search is temporarily unavailable");
    }

    const rawItems = Array.isArray(body?.searchResult?.items) ? body.searchResult.items : [];
    const items = rawItems.flatMap((item: Record<string, unknown>) => {
      const price = readPrice(item);
      const title = readPath(item, ["itemInfo", "title", "displayValue"]);
      const asin = String(item.asin ?? "");
      if (!asin || typeof title !== "string" || !Number.isFinite(price) || price <= 0) return [];
      const imageURL = readPath(item, ["images", "primary", "medium", "url"]);
      return [{
        id: `amazon-${asin}`,
        source: "amazon",
        title,
        detail: "Amazon catalog result · price captured when added",
        category: "Amazon",
        symbol: "shippingbox.fill",
        priceCents: Math.round(price * 100),
        imageURL: typeof imageURL === "string" ? imageURL : null,
        productURL: typeof item.detailPageURL === "string" ? item.detailPageURL : null,
      }];
    });
    return json({ items });
  } catch (error) {
    const status = error instanceof SearchError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unable to search products";
    return json({ error: message }, status);
  }
});

async function creatorsAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const version = Deno.env.get("AMAZON_CREATORS_CREDENTIAL_VERSION") ?? "3.1";
  const tokenEndpoints: Record<string, string> = {
    "3.1": "https://api.amazon.com/auth/o2/token",
    "3.2": "https://api.amazon.co.uk/auth/o2/token",
    "3.3": "https://api.amazon.co.jp/auth/o2/token",
  };
  const tokenEndpoint = Deno.env.get("AMAZON_CREATORS_TOKEN_URL") ?? tokenEndpoints[version];
  if (!tokenEndpoint) throw new Error("Unsupported AMAZON_CREATORS_CREDENTIAL_VERSION");
  const response = await fetch(tokenEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: requiredEnv("AMAZON_CREATORS_CREDENTIAL_ID"),
      client_secret: requiredEnv("AMAZON_CREATORS_CREDENTIAL_SECRET"),
      scope: "creatorsapi::default",
    }),
  });
  const body = await response.json();
  if (!response.ok || typeof body.access_token !== "string") {
    console.error("Creators API token failed", response.status, body);
    throw new SearchError(502, "Amazon product search credentials were rejected");
  }
  cachedToken = {
    value: body.access_token,
    expiresAt: Date.now() + Math.max(60, Number(body.expires_in ?? 3600)) * 1000,
  };
  return cachedToken.value;
}

function readPrice(item: Record<string, unknown>): number {
  const candidates: (string | number)[][] = [
    ["offersV2", "listings", 0, "price", "money", "amount"],
    ["offersV2", "listings", "price", "money", "amount"],
    ["offers", "listings", 0, "price", "money", "amount"],
  ];
  for (const path of candidates) {
    const value = readPath(item, path);
    if (typeof value === "number") return value;
    if (typeof value === "string" && Number.isFinite(Number(value))) return Number(value);
  }
  return Number.NaN;
}

function readPath(value: unknown, path: (string | number)[]): unknown {
  let cursor: unknown = value;
  for (const key of path) {
    if (cursor === null || cursor === undefined || typeof cursor !== "object") return undefined;
    cursor = (cursor as Record<string | number, unknown>)[key];
  }
  return cursor;
}

function enforceRateLimit(userId: string) {
  const now = Date.now();
  const recent = (requestWindows.get(userId) ?? []).filter((time) => time > now - 60_000);
  if (recent.length >= 30) throw new SearchError(429, "Search limit reached. Try again in a minute.");
  recent.push(now);
  requestWindows.set(userId, recent);
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

class SearchError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
