# Phone cloud connection — 2026-10-04

## October 5 Settings and foreground polling

Moved connection banner/controls into a Settings destination in the phone navigation.
Foreground unlocked polling is now 1 second, still guarded against overlap and hidden
documents. Parent PIN setup accepts the Mac's four-digit format and permits changing
an existing phone PIN only after verifying the current phone PIN. The user must enter
their Mac PIN once themselves: Mac CredentialVault is device-local, so this is manual
matching, NOT automatic credential synchronization. Later changes must be repeated.
No credentials were read or copied, and no Keychain usage was added. Syntax and existing
phone domain/cloud tests passed. Cache version is v10.

## October 5 shopping rollout — PUBLISHED

The user applied shopping-sync-install.sql and updated the search Edge Function.
Remote checks confirmed family_shopping_command exists (invalid input rejected),
phone CORS preflight returns 204 with the exact website origin, and invalid child
credentials are rejected by the new handler. No real family records were changed
for verification. Local shopping SQL, phone shopping, cloud adapter and 19 search
checks passed. Real authenticated product search and cross-device shopping writes
still need user acceptance testing; these were not exercised with private accounts.

Published shop and parent goal-review controls, updated sync copy and cache v9 in
deployment dpl_CLQDAfnn4FNog3q3gdZFztjNcjxz at pocket-crew.vercel.app.
The older rollout notes below are historical.

## October 5: editable phone controls PUBLISHED

Deployment `dpl_9p1wft5m7J9BjdUh1Ysps1UynEe2` is aliased to pocket-crew.vercel.app.
The old read-only cloud UI has been replaced with protected work start/submit,
parent create/review, split/name editing, goals, withdrawals, schedule and payday.
Saved account sessions and red Sign Out are included. Existing domain/cloud checks
and syntax checks passed; the installed work RPC rejects invalid commands as expected.
No real family record was changed for verification this turn.

Cloud shopping/review-goal controls remain hidden because the shopping RPC is not
installed remotely (confirmed PGRST202). The prepared shopping code and local demo
shopping are included, but cloud shopping still requires the backend rollout below.
Normal Vercel upload returned Not authorized despite valid account/team/project;
`deploy --archive=tgz --prod --yes --scope raymonyangcodes-projects` succeeded.

## October 5 shopping integration — prepared locally, NOT deployed

The phone now has Shop, Wishlist, Cart and Purchases, a prefilled product savings-goal
form with seller/photo, parent price changes with a reason, goal reviews, parent gifts,
and approved Spend deductions. It uses the same native shoppingEntries/goals snapshot.
Local demo shopping is explicitly labeled and never substitutes for live search failures.
Cloud sign-in persistence and the earlier protected work/payday controls are also local.

Before publishing, apply `202610050001_shopping_commands.sql` and
`202610050002_child_shopping_projection.sql`, and deploy `search-shopping-products`.
The search function now authenticates guardian JWTs or child capability+PIN inside
the handler; legacy gateway JWT checking must be disabled for child access/OPTIONS.
Do not disable handler authentication. Obtain parent approval before that backend change.
The parent was asked to open Supabase and approve protected child shopping actions;
no response or production changes have occurred yet in this turn.

Checks passed: existing phone domain/cloud tests, 19 search tests (including CORS and
child authentication), new phone shopping unit checks, and shopping SQL executed in
local PGlite with synthetic auth/data. SQL checks cover exact cents, stale prices,
duplicate approval, revisions, overdraft, immutable history, child permissions and
native-only field preservation. Real remote shopping writes remain unverified.
Browser QA at 390×844 verified parent goal creation and the child cart containing only
goal/removal actions, no approve/gift/price controls. Local demo records only were used.

Known parity limits: cloud family/child creation, recurring-work editing and private
proof-photo submission still use the Mac app. The Mac menu-bar item is platform-specific.

## Protected-command rollout in progress

Update: the corrected installation subsequently succeeded in Supabase SQL Editor.
The rollback-only test returned PASS for work, child isolation, approval retry,
payday retry, exact split, purchase, overdraw, invalid split, parent-only actions,
revision conflict, unpaid responsibilities, and preserved redo history. All test
fixtures were rolled back. The earlier blocked-install notes below are historical.
The local phone controls are being connected; they have not yet been published.

The guardian/child command functions and command-receipt table were installed through
Supabase SQL Editor on October 4 after explicit authorization. The phone UI is still
read-only: no new deployment has been made. Rollback-only tests reached child start,
submit, scoped response, and approval retry successfully, then failed in the payday
helper because a PL/pgSQL variable conflicted with a query alias. The local money
migration now includes `#variable_conflict use_column`; this correction is NOT yet
applied remotely. The attempted corrected script had a copied dollar-delimiter error
and did not execute. Resume by applying `supabase/phone-commands-install.sql`, then
rerun the complete transaction tests before enabling any phone mutation buttons.
The test fixture uses a synthetic auth user/family and rolls back; no real balances
were changed. Chrome switched windows during correction, so UI work is waiting for
the user to return to the Supabase SQL Editor.

Local form requests now capture the reviewed revision and discard responses after
profile lock/sign-out. PhoneCloudChecks and the command module syntax check pass.

Implemented: parent Google PKCE and email sign-in, an in-memory authenticated session,
read-only translation of the native family snapshot, 15-second foreground refresh,
and acceptance of existing parent email invitation tokens. Local browser families
remain separate and are not overwritten. No native or cloud financial records were
changed while implementing this connection.

The exact website callback `https://pocket-crew.vercel.app/app/` was added to the
existing Supabase redirect allowlist with the user's explicit approval. The two
native callback addresses and default Site URL were preserved.

Verification: domain tests and read-adapter tests pass. The current Mac build reached
the real family's locked profile screen after its Google button was activated. The
phone also completed Google sign-in and displayed the existing Mac family without
console errors. No real ledger mutations were made.

Child invitations added: guardian-only creation and revocation, random 256-bit links,
separate bcrypt-hashed 6–8 digit passcodes, 30-day expiry, five-attempt lockout, and
server-side child-only snapshot projection. Child sessions retain no parent token.
Links use URL fragments (removed immediately) and credentials stay in memory only.
Hiding the app locks the connection; a refresh failure also locks child views.
Invitations do not grant editing or purchase permission.

Applied migration: 202610040001_child_connections.sql. Supabase transaction tests
passed child/sibling isolation, parent-data exclusion, lockout, revocation, expiry,
and table/function privileges; synthetic test records were rolled back. Client
tests verify that child requests never send parent tokens and reject multi-child
responses. No real child invitation was created by the agent; a parent chooses
the passcode and submits the invitation form.

Not complete: phone cloud writes, cloud-family creation from the phone, and unified
Mac/phone profile passcodes. Cloud mode remains read-only, with mutation controls
removed and a mutation guard. An invitation passcode is separate from the native
Mac profile passcode.

Do not enable child mode with the parent's Supabase token: existing snapshot RLS
is guardian-only and would expose the full family. Add server-validated child-scoped
sessions and commands before enabling child sync. Do not round-trip the reduced
phone view into `save_family_snapshot`: it omits native fields and would destroy
data. A write adapter must preserve native-only data and use revision checks.

The Mac has two application copies registered with the same bundle identifier:
`dist/PocketCrew.app` and `dist/PocketCrew 2.app`. This is a possible callback routing
hazard, not a confirmed sign-in failure. Neither copy was deleted or modified.

Tests: `node Tests/PhoneAppChecks.mjs` and `node Tests/PhoneCloudChecks.mjs`.

Child UI deployment verified at production (v5). The built-in browser displays the
join form, but its test request reported a network fetch failure. Direct HTTPS tests
with the website Origin successfully reject an invalid link and return correct CORS
headers. Real child sign-in remains unverified; do not claim end-to-end completion.
