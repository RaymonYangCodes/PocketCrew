# Connect Amazon search to PocketCrew

Use Amazon.com (US) with a USD family for this setup.

## 1. Get your Amazon credentials

1. Open [Amazon Associates](https://affiliate-program.amazon.com/) and sign in. Complete any verification Amazon asks for in your browser.
2. Open **Tools → Creators API**.
3. Click **Create Application** and enter **PocketCrew** as the application name.
4. Click **Add New Credential**. Keep the **Credential ID**, **Secret**, and **Version** somewhere private.
5. Find your Associates **Store ID / Tracking ID** (usually ending in `-20` for the US). This is your Partner Tag.

Amazon controls eligibility: its documentation currently requires final Associates acceptance and at least 10 qualifying referred sales in the past 30 days for catalog access. If the Creators API page says you are ineligible, you cannot enable live search just by adding settings in PocketCrew. A normal Amazon shopping account alone does not provide these credentials.

## 2. Enter the values in Supabase

Open [your project's Edge Function Secrets](https://supabase.com/dashboard/project/bvfzqfeyxyjycmkpifgz/functions/secrets).

Under **Add new secrets**, enter these name/value pairs. Use **Add another** for each extra row, then **Save**.

| Name | Value |
| --- | --- |
| `AMAZON_CREATORS_CREDENTIAL_ID` | Credential ID copied from Amazon |
| `AMAZON_CREATORS_CREDENTIAL_SECRET` | Secret copied from Amazon |
| `AMAZON_CREATORS_CREDENTIAL_VERSION` | Exact Version shown by Amazon, such as `3.1` |
| `AMAZON_ASSOCIATE_PARTNER_TAG` | Your US Store ID / Tracking ID, usually ending in `-20` |
| `AMAZON_MARKETPLACE` | `www.amazon.com` |

Put the secret directly into Supabase; you do not need to paste it into chat. These are Amazon credentials, not the Supabase publishable key or Google sign-in client ID.

## 3. Deploy the search function if it is not listed yet

1. Open [your project's Edge Functions](https://supabase.com/dashboard/project/bvfzqfeyxyjycmkpifgz/functions).
2. Choose **Deploy a new function → Via Editor** (or **Open Editor** on an empty functions page).
3. Open `supabase/functions/search-amazon-products/index.ts` in this PocketCrew folder. Copy the entire file into the dashboard's `index.ts` editor, replacing its example code.
4. Set **Function name** to exactly `search-amazon-products`.
5. Click **Deploy function**. Keep JWT verification enabled: PocketCrew calls this function while signed into a real family.

If `search-amazon-products` is already listed, it does not need redeployment just because you saved new secrets.

## 4. Try it

Sign into your real family in PocketCrew, open **Home → Shopping center**, type **headphones**, and click **Search**. Live results have an **AMAZON** label. The demo family uses the built-in catalog.

Approval updates the PocketCrew family ledger. An actual Amazon order still needs a parent to complete Amazon checkout separately.

Sources: [Amazon registration](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/onboarding/register-for-creators-api), [Amazon eligibility](https://affiliate-program.amazon.com/creatorsapi/docs/), [Supabase secrets](https://supabase.com/docs/guides/functions/secrets), [dashboard deployment](https://supabase.com/docs/guides/functions/quickstart-dashboard).
