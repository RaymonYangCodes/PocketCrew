# PocketCrew cloud setup

## Using presets and sharing a family

The ad-hoc macOS build stores cloud authentication tokens in memory only to avoid Keychain authorization prompts after rebuilds. Fully quitting requires signing in again; no tokens are migrated from or deleted in Keychain. iOS continues using the SDK's Keychain storage. Profile PINs and the family ledger are unchanged. A future Developer ID-signed Mac distribution can restore persistent Keychain sign-in with a stable signing identity.

- In the parent Work screen, choose a paid gig or responsibility preset. The normal creation form opens with editable title, instructions, reward, schedule, assignee, and checklist. Nothing is assigned until you save it.
- Choose **Done!** to hide the library; **Show presets** opens it again. Completion of the initial preset setup is stored in the shared family, not only on this device.
- On another device, sign into the same parent account. For another parent's account, invite their email and have them accept the invitation using that account. Creating a separate family does not link accounts.
- Shared work, submissions, approvals, jars, and shopping history use the family snapshot. Realtime updates are supplemented by a catch-up fetch every 15 seconds while the app is running. Updates skipped during a save are fetched afterward.
- Simultaneous edits are revision-checked, not silently merged. If Settings reports **Sync needs attention**, keep the app open and resolve it there. **Replace with cloud copy** intentionally discards this device's unsaved changes. Do not sign out with unsaved changes.
- Demo families do not sync. Profile passcodes remain device-local; a guardian must set them up on each device. This is guardian-account sharing, not independent child email authentication.
- Verify on two signed-in devices before relying on sync: create a preset gig on one, confirm it appears on the other, then submit/review it and check both ledgers. Automated local tests do not establish deployed multi-device connectivity.

This setup makes email accounts, Google sign-in, shared real-family data, private proof images, and co-parent invitation email live. The app still runs the Parker demo when cloud values are absent.

## 1. Create and link Supabase

Create a Supabase project, install the Supabase CLI, and from this repository run:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

The migration creates family membership, invites, the revision-checked shared ledger, RLS policies, and a private `proof-images` bucket. It permits only authenticated active guardians to read their family or its proof images.

Copy these two public values from Supabase Project Settings → API:

- Project URL, such as `https://YOUR_PROJECT_REF.supabase.co`
- Publishable key (an `sb_publishable_...` key, or the legacy public anon key)

Put them in:

- `macos/CloudConfig.plist`
- `ios/PocketCrewIOS/CloudConfig.plist`

Do not put `SUPABASE_SERVICE_ROLE_KEY`, the Google client secret, or an email-provider key in either plist.

## 2. Configure email authentication

In Supabase Authentication:

1. Enable the Email provider.
2. Keep email confirmation enabled for a production family app.
3. Add `pocketcrew://auth-callback` and `pocketcrew://invite` to the redirect allow list.
4. Configure a production SMTP provider before inviting real families; Supabase’s default mail service is intended only for limited testing.

Password-reset links return to the native app, where PocketCrew asks the guardian to choose a new password.

## 3. Configure Google sign-in

In Google Cloud, create an OAuth 2.0 Web client. Add this exact authorized redirect URI:

```text
https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
```

Then enable Google under Supabase Authentication → Sign In / Providers and paste the Google client ID and client secret there. The secrets stay server-side. PocketCrew returns from browser OAuth through `pocketcrew://auth-callback`, already registered in both native app targets.

## 4. Configure invitation email

The `send-family-invite` Edge Function uses Resend and stores only a SHA-256 hash of each one-time invite token. Invites expire after 72 hours and are limited to five per guardian per hour.

Create a verified sending domain in Resend, then run:

```sh
supabase secrets set RESEND_API_KEY=YOUR_RESEND_KEY
supabase secrets set RESEND_FROM_EMAIL="PocketCrew <invites@YOUR_VERIFIED_DOMAIN>"
supabase secrets set POCKETCREW_APP_URL="pocketcrew://invite"
supabase functions deploy send-family-invite
supabase functions deploy delete-account
```

Supabase automatically supplies the function’s project URL, anon key, and service-role key at runtime. The service-role key is used only inside the server function to create an invitation after independently checking the caller’s authenticated family membership.

## 5. Configure Google Shopping search (optional)

PocketCrew's demo catalog, wishlist, approval cart, and simulated purchase ledger work without a search provider. Real-family searches show only live listings, never demo fallback products. Live search uses **SerpApi's Google Shopping results**, not an official Google API. The initial integration deliberately supports US shopping results and USD family currency only, avoiding accidental currency relabeling. It does not convert prices.

In Supabase → Edge Functions → Secrets, save the SerpApi key under the exact name `SERPAPI_API_KEY`. This is the only additional provider secret needed; it must never go in a plist, app bundle, screenshot, or chat. If you already saved it, do not add it again. The previously entered spelling `SERPAI_API_KEY` is also accepted for compatibility. [Supabase secret setup](https://supabase.com/docs/guides/functions/secrets)

From this linked repository, deploy:

```sh
supabase functions deploy search-shopping-products
```

For a no-terminal deployment, follow [`GOOGLE_SHOPPING_SETUP.md`](GOOGLE_SHOPPING_SETUP.md). The function validates the signed-in user before searching. Supabase supplies its own runtime environment values; no service-role key is required in the app or as a new shopping-provider secret. Rebuild PocketCrew to pick up the new endpoint, then sign in to a real family with USD currency and search the Shop. Saving a secret alone does not deploy the function or verify live search.

Search terms are sent to SerpApi only when Search or Return is pressed; do not include personal information. External search results are not guaranteed to be child-safe; parents should supervise searches and review requests. Product prices are snapshots, not a guaranteed checkout total, and can exclude tax or delivery. Approving a cart item records a simulated family-ledger purchase: it does not place an order, collect payment, or arrange shipping. If live search is unavailable, a real family sees an error with retry guidance, not pretend listings.

The old `search-amazon-products` source and [`AMAZON_SETUP.md`](AMAZON_SETUP.md) remain optional historical references. They are not used by the current shopping client, and no Amazon credentials are needed for Google Shopping.

## 6. Build and verify

macOS:

```sh
zsh macos/test.sh
zsh macos/build.sh
```

iOS:

1. Open `ios/PocketCrewIOS.xcodeproj` in Xcode.
2. Wait for the pinned `supabase-swift` package to resolve.
3. Select a signing team and run on two devices or simulators.

Recommended smoke test:

1. Create a guardian with email/password and confirm the email.
2. Create a family and one child, including separate device PINs.
3. Sign out/in and verify the shared ledger returns.
4. Enable Google, sign in with a second unused guardian account, and verify it reaches family setup.
5. From the owner account, invite a different email; open the email on the second device and accept it with the same invited address.
6. Submit work with a proof image and verify the co-parent can view its signed private preview.
7. Edit on one device and verify the idle second device refreshes automatically.
8. From a test account, verify cloud deletion requires the local parent PIN and transfers ownership when another guardian remains.
9. As a child, add a catalog item to the cart. As a parent, approve it and verify only Spend decreases once; then give a wishlist item free and verify no jar changes.
10. With the shopping function deployed, type a simple item from a signed-in USD family and press Search. Verify live photos and listings labeled Google Shopping. Check that typing alone shows a search prompt, and a failed request shows an error without any sample products.

## Security notes

- The public publishable key is safe in the app only because every family table and storage object is protected by RLS.
- One active-family membership per guardian is enforced by a partial unique index.
- Raw proof image bytes are uploaded to private Storage and removed from the shared JSON snapshot.
- Snapshot writes require the expected server revision; stale clients cannot overwrite newer state.
- Family snapshots publish through Supabase Realtime, so idle devices refresh automatically after another guardian saves.
- Child profiles never receive separate email credentials. The native permission layer restricts child actions to the unlocked child ID, and every sibling profile has a separate local PIN.
