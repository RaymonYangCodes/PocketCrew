# Google Shopping for PocketCrew

PocketCrew uses **SerpApi**, a third-party service that supplies Google Shopping results—not an official Google API. Products appear inside PocketCrew's native Shop. This version uses US results and USD only. [SerpApi documentation](https://serpapi.com/google-shopping-api)

## 1. Save the one secret

If you already saved your SerpApi key, skip this step.

Open [your Supabase function secrets](https://supabase.com/dashboard/project/bvfzqfeyxyjycmkpifgz/functions/secrets). Enter:

- **Name / Key:** `SERPAPI_API_KEY`
- **Value:** your SerpApi API key

Click **Save**. Keep the key out of chat, screenshots, and both apps' configuration files. [Supabase secrets documentation](https://supabase.com/docs/guides/functions/secrets)

If you already saved it as `SERPAI_API_KEY`, PocketCrew also accepts that spelling. You do not need to re-enter the key; use `SERPAPI_API_KEY` for future setups.

## 2. Deploy the search function

### Dashboard option

1. Open [your Supabase Edge Functions](https://supabase.com/dashboard/project/bvfzqfeyxyjycmkpifgz/functions).
2. Choose **Deploy a new function → Via Editor** (or **Open Editor**).
3. Replace the entire example `index.ts` with the contents of [`supabase/functions/search-shopping-products/index.ts`](supabase/functions/search-shopping-products/index.ts). The file is self-contained; no other source files need copying.
4. Set the function name to exactly **`search-shopping-products`**.
5. Click **Deploy function** and wait for a successful deployment. For an existing function, update its code and choose **Deploy updates**. [Dashboard deployment instructions](https://supabase.com/docs/guides/functions/quickstart-dashboard)

The function requires a signed-in PocketCrew user. A test with only the public project key is not a valid signed-in search; do not remove the user checks to bypass an authentication error.

### CLI option

From this repository, with the Supabase CLI installed:

```sh
supabase login
supabase link --project-ref bvfzqfeyxyjycmkpifgz
supabase functions deploy search-shopping-products
```

The secret already saved in the dashboard is available to the deployed function. No Amazon credentials or SerpApi key in the native app are needed.

## 3. Try it in the updated app

1. Rebuild with `zsh macos/build.sh`, then open the new `dist/PocketCrew.app`.
2. Sign in to a real family using USD currency. The local demo continues to use its starter catalog.
3. Open **Shop**, type something like **headphones**, and press **Search** or Return. Typing alone does not send an API request.
4. Check for live Google Shopping products. Add one to a wishlist or cart and check that parent approval is still required.

For iOS, rebuild the shared app project in Xcode. A saved key or successful function deployment alone is not proof that live search works; verify it from a signed-in app.

## If results do not load

- Check the function name and the exact secret name above.
- Sign out and back in if the app reports an expired session.
- Check your SerpApi account if its key is rejected or its search allowance is exhausted.
- Use a USD family for live search; no currency conversion is performed.
- A real family sees only live listings, never sample fallback products. Failed searches show an error with retry guidance; the sample catalog is only for demo mode.

Displayed prices are snapshots and may exclude tax or delivery. PocketCrew does not place orders or move real money; parent approval only records the agreed amount in the family's learning ledger. Avoid personal information in search terms.

Shopping search results come from an external provider and are not guaranteed to be child-safe. Parents should supervise searches and review the item, seller, and price before approving a request.

## Offline checks

Run `node --experimental-strip-types --test Tests/ShoppingSearchChecks.mjs` with Node 24, and `zsh macos/test.sh` for the native ledger and access checks. Search tests use fixtures and never spend SerpApi search credits.

The search service checks the signed-in user and active family membership using that user's permissions. It has a bounded five-minute result cache and a six-searches-per-minute throttle per user per running worker. This throttle is best-effort, not a global spending cap; keep SerpApi account usage limits in place.
