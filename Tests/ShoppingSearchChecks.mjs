import assert from "node:assert/strict";
import test from "node:test";

// No real account, API key, or network access is used by these checks.
const environment = new Map();
globalThis.Deno = {
  env: { get: (name) => environment.get(name) },
  serve: () => {},
};

const { parseUSDPrice, normalizeProducts, handleRequest } = await import(
  "../supabase/functions/search-shopping-products/index.ts"
);

test("phone preflight allows only PocketCrew and never calls upstream",async()=>{
  const response=await handleRequest(new Request('https://test-project.supabase.co/functions/v1/search-shopping-products',{method:'OPTIONS',headers:{Origin:'https://pocket-crew.vercel.app'}}));
  assert.equal(response.status,204);assert.equal(response.headers.get('Access-Control-Allow-Origin'),'https://pocket-crew.vercel.app');
  const blocked=await handleRequest(new Request('https://test-project.supabase.co/functions/v1/search-shopping-products',{method:'OPTIONS',headers:{Origin:'https://untrusted.example'}}));
  assert.equal(blocked.status,403);
});

test("child shopping authenticates the private connection without a parent token",async()=>{
  environment.set('SUPABASE_URL','https://test-project.supabase.co');environment.set('SUPABASE_ANON_KEY','public');environment.set('SERPAPI_API_KEY','test-secret');
  let calls=0;
  globalThis.fetch=async (input,options)=>{
    calls++;const url=String(input);
    if(url.includes('read_child_connection')){assert.equal(options.headers.Authorization,undefined);return Response.json({child_id:'synthetic-child'});}
    assert.ok(url.startsWith('https://serpapi.com/'));assert.ok(!url.includes('123456'));return Response.json({shopping_results:[]});
  };
  const response=await handleRequest(new Request('https://test-project.supabase.co/functions/v1/search-shopping-products',{method:'POST',headers:{Origin:'https://pocket-crew.vercel.app','Content-Type':'application/json'},body:JSON.stringify({query:'safe child test',currency:'USD',childToken:'a'.repeat(64),childPin:'123456'})}));
  assert.equal(response.status,200);assert.equal(calls,2);
  globalThis.fetch=async()=>Response.json({error:'Invitation revoked'});
  const denied=await handleRequest(new Request('https://test-project.supabase.co/functions/v1/search-shopping-products',{method:'POST',body:JSON.stringify({query:'safe child test',currency:'USD',childToken:'a'.repeat(64),childPin:'123456'})}));
  assert.equal(denied.status,401);
});

const product = (overrides = {}) => ({
  product_id: "catalog-101",
  title: "Art supplies set",
  source: "Example Store",
  price: "$19.99",
  extracted_price: 19.99,
  product_link: "https://www.google.com/shopping/product/101",
  thumbnail: "https://encrypted-tbn0.gstatic.com/shopping/art-set.jpg",
  ...overrides,
});

test("public catalog searches need no family and are throttled",async()=>{
  environment.set('SUPABASE_URL','https://test-project.supabase.co');
  environment.set('SERPAPI_API_KEY','test-secret');
  let calls=0;
  globalThis.fetch=async input=>{
    calls++;assert.ok(String(input).startsWith('https://serpapi.com/'));
    return Response.json({shopping_results:[product()]});
  };
  const request=()=>new Request('https://test-project.supabase.co/functions/v1/search-shopping-products',{method:'POST',headers:{Origin:'https://pocket-crew.vercel.app','Content-Type':'application/json','x-forwarded-for':'192.0.2.5'},body:JSON.stringify({query:'public art supplies',currency:'USD',publicSearch:true})});
  const first=await handleRequest(request());assert.equal(first.status,200);
  assert.equal((await first.json()).items.length,1);
  for(let i=0;i<5;i++)assert.equal((await handleRequest(request())).status,200);
  assert.equal((await handleRequest(request())).status,429);
  assert.equal(calls,1,'repeated queries use the cache');
});

let testUserSequence = 0;
function configure({ providerBody = { shopping_results: [product()] }, providerStatus = 200,
  authStatus = 200, families = [{ family_id: "test-family" }], membershipStatus = 200,
  missingKey = false, providerThrows = false } = {}) {
  environment.clear();
  environment.set("SUPABASE_URL", "https://test-project.supabase.co");
  environment.set("SUPABASE_ANON_KEY", "test-public-key");
  if (!missingKey) environment.set("SERPAPI_API_KEY", "test-private-key-not-for-output");
  const userId = `test-user-${++testUserSequence}`;
  const calls = [];
  globalThis.fetch = async (input, options = {}) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    calls.push({ url, options });
    if (url.origin === "https://test-project.supabase.co" && url.pathname === "/auth/v1/user") {
      return Response.json(authStatus === 200 ? { id: userId } : { error: "invalid token" },
        { status: authStatus });
    }
    if (url.origin === "https://test-project.supabase.co" && url.pathname === "/rest/v1/family_guardians") {
      assert.equal(url.searchParams.get("user_id"), `eq.${userId}`);
      assert.equal(url.searchParams.get("status"), "eq.active");
      return Response.json(families, { status: membershipStatus });
    }
    assert.equal(url.hostname, "serpapi.com", "Unexpected network destination is prohibited in tests");
    if (providerThrows) throw new Error("Upstream leaked test-private-key-not-for-output");
    return Response.json(providerBody, { status: providerStatus });
  };
  return calls;
}

function request(body = { query: `art supplies ${testUserSequence}`, currency: "USD", locale: "en_US" }, {
  auth = "Bearer test-user-jwt", method = "POST", rawBody,
} = {}) {
  const headers = { "Content-Type": "application/json" };
  if (auth) headers.Authorization = auth;
  return new Request("https://test-project.supabase.co/functions/v1/search-shopping-products", {
    method, headers,
    ...(method === "POST" ? { body: rawBody ?? JSON.stringify(body) } : {}),
  });
}

test("USD prices become exact integer cents without rounding malformed values", () => {
  for (const [value, cents] of [["$1,234.56", 123456], ["US$1.99", 199], ["$0.29", 29], ["$42.00", 4200]]) {
    assert.equal(parseUSDPrice(value), cents, value);
  }
  for (const value of ["€1.99", "CA$1.99", "£1.99", "$2.99/month", "$2.99/mo", "$1,23.45",
    "$1.234", "$-1.00", "NaN", "", null, "$999999999999999999.99"]) {
    assert.equal(parseUSDPrice(value), null, String(value));
  }
});

test("catalog results preserve USD price, merchant, and native app product fields", () => {
  const items = normalizeProducts({ shopping_results: [product()] });
  assert.equal(items.length, 1);
  assert.equal(items[0].source, "googleShopping");
  assert.equal(items[0].currencyCode, "USD");
  assert.equal(items[0].merchant, "Example Store");
  assert.equal(items[0].title, "Art supplies set");
  assert.equal(items[0].priceCents, 1999);
  assert.equal(items[0].imageURL, "https://encrypted-tbn0.gstatic.com/shopping/art-set.jpg");
  assert.equal(items[0].productURL, "https://www.google.com/shopping/product/101");
  for (const field of ["id", "detail", "category", "symbol"]) {
    assert.equal(typeof items[0][field], "string", field);
  }
});

test("untrusted thumbnails are removed without losing an otherwise valid product", () => {
  for (const thumbnail of ["https://tracking.example.com/pixel", "http://gstatic.com/image.jpg",
    "https://gstatic.com.attacker.example/image.jpg", "https://user:secret@gstatic.com/image.jpg"]) {
    const items = normalizeProducts({ shopping_results: [product({ thumbnail })] });
    assert.equal(items.length, 1);
    assert.equal(items[0].imageURL, null);
  }
});

test("categorized results merge with flat results and duplicate IDs appear only once", () => {
  const items = normalizeProducts({
    shopping_results: [product()],
    categorized_shopping_results: [{
      title: "More ideas",
      shopping_results: [product(), product({ product_id: "catalog-102", title: "Sketchbook", price: "$4.00" })],
    }],
  });
  assert.equal(items.length, 2);
  assert.deepEqual(new Set(items.map((item) => item.title)), new Set(["Art supplies set", "Sketchbook"]));
  assert.equal(new Set(items.map((item) => item.id)).size, 2);
});

test("Google Shopping search links are accepted and normalized responses contain at most 20 items", () => {
  const productURL = "https://www.google.com/search?udm=28&q=art+supplies&prds=pid%3A101";
  const items = normalizeProducts({ shopping_results: Array.from({ length: 25 }, (_, index) =>
    product({ product_id: `catalog-${index}`, product_link: productURL })) });
  assert.equal(items.length, 20);
  assert.equal(items[0].productURL, productURL);
  assert.equal(new Set(items.map((item) => item.id)).size, 20);
  assert.deepEqual(normalizeProducts({ shopping_results: [
    product({ product_link: "https://www.google.com/search?q=art+supplies" }),
    product({ product_link: "https://www.google.com/search?udm=2&q=art+supplies" }),
  ] }), []);
});

test("installments, non-USD prices, missing IDs, and unsafe product links are excluded", () => {
  const items = normalizeProducts({ shopping_results: [
    product({ product_id: "installment", price: "$4.00/mo" }),
    product({ product_id: "installment-property", installment: { down_payment: "$4.00" } }),
    product({ product_id: "foreign", price: "CA$19.99" }),
    product({ product_id: "unsafe", product_link: "javascript:alert(1)" }),
    product({ product_id: "insecure", product_link: "http://example.com/product" }),
    product({ product_id: "spoofed", product_link: "https://www.google.com.evil.example/shopping/product/1" }),
    product({ product_id: "credentials", product_link: "https://user:secret@www.google.com/shopping/product/1" }),
    product({ product_id: "adult", title: "Tobacco assortment" }),
    product({ product_id: "", title: "Missing catalog ID" }),
    product({ product_id: "missing-price", price: undefined }),
    product({ product_id: "valid" }),
  ] });
  assert.equal(items.length, 1);
  assert.equal(items[0].title, "Art supplies set");
  assert.equal(items[0].priceCents, 1999);
  assert.deepEqual(normalizeProducts({}), []);
  assert.deepEqual(normalizeProducts(null), []);
});

test("search rejects unsupported methods and unauthenticated calls without provider access", async () => {
  const calls = configure();
  assert.equal((await handleRequest(request(undefined, { method: "GET" }))).status, 405);
  assert.equal((await handleRequest(request(undefined, { auth: null }))).status, 401);
  assert.equal(calls.length, 0);
  configure({ authStatus: 401 });
  assert.equal((await handleRequest(request())).status, 401);
});

test("search requires active family membership and forwards only the caller's auth", async () => {
  for (const [options, expected] of [
    [{ families: [] }, 403],
    [{ membershipStatus: 503 }, 503],
  ]) {
    const calls = configure(options);
    assert.equal((await handleRequest(request())).status, expected);
    assert.ok(calls.every((call) => call.url.hostname === "test-project.supabase.co"));
    for (const call of calls) {
      assert.equal(call.options.headers.Authorization, "Bearer test-user-jwt");
      assert.equal(call.options.headers.apikey, "test-public-key");
    }
  }
});

test("valid authenticated USD searches return normalized products", async () => {
  const calls = configure();
  const response = await handleRequest(request());
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.items.length, 1);
  assert.equal(body.items[0].priceCents, 1999);
  const providerCall = calls.find((call) => call.url.hostname === "serpapi.com");
  assert.ok(providerCall);
  assert.equal(providerCall.url.searchParams.get("engine"), "google_shopping");
  assert.equal(providerCall.url.searchParams.get("q"), `art supplies ${testUserSequence}`);
  assert.equal(providerCall.url.searchParams.get("gl"), "us");
  assert.equal(providerCall.url.searchParams.get("api_key"), "test-private-key-not-for-output");
  assert.ok(!JSON.stringify(body).includes("test-private-key"));
});

test("the saved SERPAI_API_KEY alias works without returning the private key", async () => {
  const calls = configure({ missingKey: true });
  environment.set("SERPAI_API_KEY", "test-alias-private-key-not-for-output");
  const response = await handleRequest(request());
  assert.equal(response.status, 200);
  const providerCall = calls.find((call) => call.url.hostname === "serpapi.com");
  assert.ok(providerCall);
  assert.equal(providerCall.url.searchParams.get("api_key"), "test-alias-private-key-not-for-output");
  const body = await response.json();
  assert.equal(body.items.length, 1);
  assert.ok(!JSON.stringify(body).includes("test-alias-private-key-not-for-output"));
});

test("the modern default publishable key takes precedence over the legacy anon key", async () => {
  const calls = configure();
  environment.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: "test-modern-publishable-key" }));
  const response = await handleRequest(request());
  assert.equal(response.status, 200);
  const supabaseCalls = calls.filter((call) => call.url.hostname === "test-project.supabase.co");
  assert.equal(supabaseCalls.length, 2);
  for (const call of supabaseCalls) {
    assert.equal(call.options.headers.apikey, "test-modern-publishable-key");
    assert.equal(call.options.headers.Authorization, "Bearer test-user-jwt");
  }
  const body = await response.json();
  assert.equal(body.items.length, 1);
  assert.ok(!JSON.stringify(body).includes("test-modern-publishable-key"));
  assert.ok(!JSON.stringify(body).includes("test-private-key-not-for-output"));
});

test("invalid query, JSON, and unsupported currencies never call the product provider", async () => {
  const calls = configure();
  for (const body of [{ query: "x", currency: "USD" }, { query: "art", currency: "EUR" },
    { query: "x".repeat(121), currency: "USD" }, { query: "cigarettes", currency: "USD" },
    { query: 123, currency: "USD" }]) {
    assert.equal((await handleRequest(request(body))).status, 400);
  }
  assert.equal((await handleRequest(request(undefined, { rawBody: "{" }))).status, 400);
  assert.equal((await handleRequest(request(undefined, { rawBody: " ".repeat(4097) }))).status, 413);
  assert.ok(calls.every((call) => call.url.hostname !== "serpapi.com"));
});

test("identical searches use the short-lived cache while still verifying each caller", async () => {
  const calls = configure();
  const first = await handleRequest(request());
  const second = await handleRequest(request());
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.deepEqual(await first.json(), await second.json());
  assert.equal(calls.filter((call) => call.url.hostname === "serpapi.com").length, 1);
  assert.equal(calls.filter((call) => call.url.pathname === "/auth/v1/user").length, 2);
  assert.equal(calls.filter((call) => call.url.pathname === "/rest/v1/family_guardians").length, 2);
});

test("missing search configuration returns a useful 503 without exposing environment values", async () => {
  configure({ missingKey: true });
  const response = await handleRequest(request());
  assert.equal(response.status, 503);
  const body = await response.json();
  assert.equal(typeof body.error, "string");
  assert.ok(!JSON.stringify(body).includes("test-public-key"));
});

test("provider failures and network exceptions are sanitized", async () => {
  for (const options of [
    { providerStatus: 500, providerBody: { error: "test-private-key-not-for-output is invalid" } },
    { providerStatus: 200, providerBody: { error: "test-private-key-not-for-output is invalid" } },
    { providerThrows: true },
  ]) {
    configure(options);
    const response = await handleRequest(request());
    assert.ok(response.status >= 500);
    const body = await response.json();
    assert.equal(typeof body.error, "string");
    assert.ok(!JSON.stringify(body).includes("test-private-key-not-for-output"));
  }
});

test("provider quota errors produce an actionable rate-limited response", async () => {
  configure({ providerStatus: 429 });
  const response = await handleRequest(request());
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(typeof (await response.json()).error, "string");
});

test("repeated searches by one authenticated user eventually return 429", async () => {
  configure();
  let limited = false;
  for (let count = 0; count < 61; count++) {
    const response = await handleRequest(request());
    if (response.status === 429) { limited = true; break; }
    assert.equal(response.status, 200);
  }
  assert.ok(limited, "Expected a per-user limit within 61 requests");
});
