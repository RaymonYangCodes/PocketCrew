# PocketCrew for macOS and iOS

> **Public beta source — still in development.** PocketCrew is a learning ledger, not a bank or store checkout. No real money is held or transferred. Platform features differ, and some older setup notes below describe earlier versions.
>
> The iPhone experience is the web app in `download-site/public/app`; the native Xcode project is experimental. Public password-reset email delivery requires a configured email provider. Mac builds are not Apple-notarized. Test with sample data before relying on this beta for family records.

Website: https://pocket-crew.vercel.app/ · Web app: https://pocket-crew.vercel.app/app/

For your own deployment, configure your own Supabase project and public client settings. Public publishable keys are client identifiers, not server credentials; never commit service-role keys, provider secrets, session tokens, or family data. Built installers and local deployment files are intentionally excluded from this repository.

PocketCrew is a native SwiftUI family-finance learning app. Children complete responsibilities and paid gigs, guardians review the work, approved earnings wait for payday, and payday divides integer cents into Spend, Save, and Give jars.

## Architecture and route map

- Native clients: one shared Swift domain/UI layer with dedicated macOS sidebar and iOS five-tab shells.
- Local mode: atomic JSON demo repository, no account or setup required.
- Cloud mode: Supabase Auth, Postgres row-level security, revision-checked family snapshots, private proof-image Storage, email invitations, and a server-side Google Shopping search adapter through SerpApi.
- Guardian route: Welcome → email/Google auth → create or join family → device PIN setup → locked profile picker → Home / Work / Payday / Family / Settings.
- Child route: locked profile picker → Home / Work / Payday / Jars / Profile. Children are parent-managed profiles and do not need email addresses.
- Domain rules: `FinanceEngine` owns approvals, exactly-once earnings, integer-cent splits, append-only ledger writes, withdrawal guards, and idempotent payday processing.

Every profile has a separate four-digit device PIN. Parent view always requires the parent PIN; each child view requires that child’s PIN, preventing siblings from opening one another’s profiles. PINs are salted and hashed locally. Supabase Auth separately protects the real family account.

PocketCrew is a learning ledger. It does not hold, insure, or transfer real funds.

The native PocketCrew Shop includes a demo-only sample catalog, per-child wishlists, ask-to-buy carts, parent approval or free-gift actions, and shared purchase history. An approved cart request deducts the snapshotted integer-cent price from Spend exactly once. Real families see only live Google Shopping listings supplied by SerpApi, a third-party service rather than an official Google API, through the authenticated `search-shopping-products` Supabase Edge Function. Search or Return starts the request; typing alone shows a prompt. The first version supports US results in USD without conversion. Search results stay inside the native PocketCrew interface. PocketCrew never embeds the SerpApi key or places an external order.

For the one-secret shopping setup, follow [`GOOGLE_SHOPPING_SETUP.md`](GOOGLE_SHOPPING_SETUP.md). Deployment and a successful search from a signed-in app are required before live results are ready. The old Amazon function and [`AMAZON_SETUP.md`](AMAZON_SETUP.md) remain as optional historical implementation references; the current app does not call that endpoint.

## Run the demo

Requirements: macOS 14 or later and Apple Command Line Tools.

```sh
xcrun swift run PocketCrew
zsh macos/build.sh
```

The macOS app is produced at `dist/PocketCrew.app`. Demo PINs: Parent `2468`, Jordan `1212`, Riley `0808`.

Run the business and access checks with:

```sh
zsh macos/test.sh
```

## Turn on real family accounts

Real email accounts and Google sign-in need a Supabase project. No service-role key or Google client secret belongs in either app.

1. Follow [`CLOUD_SETUP.md`](CLOUD_SETUP.md) to push the database migration, configure Google, deploy the server functions, and set server-only secrets.
2. Add the project URL and public publishable key to both `macos/CloudConfig.plist` and `ios/PocketCrewIOS/CloudConfig.plist`.
3. Rebuild the macOS app and iOS project. The app automatically switches from local-only mode to the authenticated flow when those public values are present.

The cloud implementation provides:

- email sign-up, confirmation, sign-in, password reset, and recovery;
- Google OAuth using PKCE and the `pocketcrew://auth-callback` app link;
- one real family per guardian account, with email-verified co-parent invitations;
- family-isolated Postgres reads/writes enforced with RLS;
- optimistic revision checks so one device cannot silently overwrite a newer family ledger;
- automatic cross-device refresh through family-filtered Realtime updates;
- private family-scoped proof-image uploads and five-minute signed previews;
- persistent auth sessions and persistent invitation links across app restarts;
- authenticated guardian IDs in approvals and audit events;
- parent-PIN-gated cloud deletion with ownership transfer when a co-parent remains;
- local, separate parent and per-child PINs on every device;
- an authenticated Google Shopping search proxy through SerpApi, with clearly separated demo samples and live results.

## macOS sharing

Run `zsh macos/build.sh`, then send `dist/PocketCrew-macOS.zip`. The local build is Apple-silicon and ad-hoc signed. A recipient may need to Control-click → Open because it is not notarized with an Apple Developer ID. Public Supabase values must be embedded before building if recipients should use real accounts.

## iOS sharing

Requirements: Xcode 16 or later and iOS 17 or later.

1. Open `ios/PocketCrewIOS.xcodeproj`.
2. Select the `PocketCrewIOS` target, choose an Apple Developer team, and use a unique bundle identifier if requested.
3. Run on a simulator/device, then use Product → Archive and TestFlight for sharing.

Run `zsh ios/package.sh` to refresh the source handoff at `dist/PocketCrew-iOS-Xcode.zip`. Apple requires a developer signing identity for an installable iPhone app.

## Deliberate product decisions

- Responsibilities never create earnings; only an approved paid gig can do that.
- Child accounts remain email-free; the signed-in guardian session syncs the shared family.
- Device PINs are not synced, so a newly invited co-parent chooses fresh local PINs rather than receiving the owner’s PINs.
- Proof images live in a private object bucket; shared ledger JSON never contains raw image bytes or local file bookmarks.
- Snapshot writes use a server revision check. A conflict becomes a visible sync error instead of silently discarding another guardian’s changes.
- Optional parent match is a separate Save ledger line, and every rounding remainder goes deterministically to Spend.
- Shopping approval is a simulated ledger purchase, not checkout: only Spend can be debited, parent gifts debit nothing, and product details are preserved as a purchase-time snapshot.
