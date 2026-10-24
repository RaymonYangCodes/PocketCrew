# PocketCrew download site

Static, dependency-free site for the native Mac developer preview and iOS Xcode source ZIP. Only `public/` is published. Do not deploy the repository root: it contains local build output and application configuration.

Refresh releases with `zsh macos/build.sh`, `zsh ios/package.sh`, and `zsh macos/package-dmg.sh` from the repository root. Recompute `public/downloads/SHA256SUMS.txt` after replacing either download.

Preview: `python3 -m http.server 4173 --bind 127.0.0.1 --directory public`

Deploy from this directory using an authenticated Vercel CLI: `vercel link --project pocket-crew`, then `vercel deploy --prod`. Confirm the project belongs to the intended account and the requested production alias is available before publishing.

The DMG is ad-hoc signed, not notarized. The ZIP is source, not a signed IPA. Keep both disclosures visible.

## Phone Home Screen preview

`public/app/` is a standalone, device-local PWA. It has no backend calls, analytics, Google login or Mac synchronization. Keep that limitation visible. It deliberately does not expose the guardian-only cloud snapshot service to child sessions. Cloud support needs server-enforced child scopes and mutation validation before enabling it here.

The app supports a seeded demo or local family, hashed per-profile PIN gates, editable one-time presets, claiming/submitting/reviewing work, integer-cent payday, goals, withdrawals and a searchable ledger. PINs are a shared-device convenience, not encryption or a server security boundary. Local state is one atomic localStorage write per mutation, with revision guards and Web Locks where available; persistence errors do not commit the in-memory change. Export is a readable record, not an implemented import/restore flow.

Run `node Tests/PhoneAppChecks.mjs` from the repository root. Browser QA covers the demo create → submit → approve → payday → jars loop at phone width. Actual iPhone Home Screen installation must still be checked on a physical phone. The service worker caches only the public app shell; no family records are uploaded or cached by the service worker.

Generate icons with `swift -module-cache-path .build/phone-icon-cache download-site/scripts/make-icons.swift download-site/public/app` from the repository root. Increment the service worker cache version when the shell changes. Preserve localStorage keys for compatibility.
