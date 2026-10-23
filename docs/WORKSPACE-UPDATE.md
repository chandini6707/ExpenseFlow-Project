# ExpenseFlow workspace update — 15 October 2026

The existing website and Supabase project were updated in place. Branding, the purple/navy palette, sidebar, authentication providers and all role-specific routes remain. Existing records were not replaced with sample or browser-local data.

## What changed

- **Landing:** a clearer introduction, illustrative Bengaluru trip, four-step process, feature benefits, keyboard-accessible role tabs, common questions, and Sign in/Get started links to the existing pages. The example is labeled; it does not impersonate live expense data.
- **Employee dashboard:** next actions first, clear pending-review and unpaid-reimbursement amounts, recent claims, and expandable spending/verification details. Drafts, reports, notifications, bank tickets and all existing dashboards remain available.
- **Usability:** larger form controls, readable status colors, mobile navigation dismissal, responsive landing and dashboard grids, dark-theme surfaces, and a scrollable sidebar that keeps Sign out reachable on shorter screens.
- **Tables and CSV:** manager tables no longer duplicate control IDs. Search, category/status filters, sorting and page selection survive data refresh. CSV exports all filtered rows in the displayed sort order, includes real decision/payment references, escapes spreadsheet formula prefixes including leading whitespace, and excludes bank account data and private receipt URLs.
- **Reports:** historical date filters now determine the trend period; ranges over twelve months use annual buckets. Invalid date ranges show an error and disable export. Chart legends explain that reimbursed amounts are a portion of claims grouped by expense date, not payments grouped by payment date. Empty category charts retain their canvas so changing filters can restore the chart.
- **Workflow feedback:** a saved bank-details ticket no longer overwrites a failed-refresh warning with a success message. Submission displays the employee code where available. Existing duplicate-submit protections, required purchase details, receipt checks and server transitions are retained.
- **Security:** existing policy/notification RPCs now call authenticated, authorized implementations in the private schema. The older profile-update RPC reuses the current profile validator. Direct API execution of the platform RLS-trigger helper is revoked. No privileges are granted by public role selection.

## Supabase configuration

The migration `supabase/migrations/20261014174834_harden_workspace_helpers.sql` is **already applied** to `tzgbroijqcmsomgpvmhp`. No new tables, credentials, environment variables, Storage buckets, OAuth redirects or Edge Function deployments are required for this update. Keep `expense_private` outside the exposed Data API schemas.

For another installation, apply all six supplied migrations in filename order, once, or use the linked Supabase CLI migration workflow. Keep the existing `save-expense` version 3 function and private receipts/avatar buckets. Do not rerun the initial schema over the configured live project.

Current security advisors have no public SECURITY DEFINER execution warnings. The private bank table deliberately has no client RLS policy, so direct access is denied. Leaked-password protection remains disabled in the existing Auth configuration; it can be enabled, if supported by the plan, under [Supabase password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). The [private-table linter notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) is intentional.

Google authentication code and provider settings were preserved. A successful Google account round trip was not tested during this update. The earlier provider-client error still needs verification with the correct Google Web OAuth client ID and matching secret; see `AUTHENTICATION.md`. A Workspace-domain access restriction must be resolved by that Google Workspace administrator.

## Actual verification

Completed on 14–15 October 2026:

- `npm test`: **46 passed, 0 failed**. Includes authorization routing, session cleanup, profile-image validation, submission retries, upload-byte validation, duplicate-click suppression, status/totals consistency, historical report ranges, CSV safety, recovery after empty chart filters/CDN failures and actual table event handlers using a small DOM adapter.
- `npm run check`: **20 frontend modules and 16 HTML entry points**, JavaScript syntax, module imports and local asset references.
- Rendered landing markup check: one main heading, unique IDs, and all introductory navigation and account links resolve.
- Light-theme status text contrast: all seven status styles exceed **5:1** against their backgrounds. Existing light/dark chart text tests also pass.
- `tests/database-regression.sql`: real PostgreSQL RLS, submission validation, duplicate flags, assigned-manager decisions, bank-ticket rules, finance processing/payment, retry idempotency, consistency constraints and snapshots over 1,000 records. **Passed; all fixtures rolled back.**
- `tests/unassigned-submission.sql`: valid employee submission without manager/role approval, saved assignment warnings, private receipt access, later admin assignment, manager isolation, approval/rejection, bank ticket, processing and reimbursement. **Passed; all fixtures rolled back.**
- `tests/profile-security.sql`: profile ownership, persistent updates/removal, role requests without escalation, avatar Storage policies and trusted role authorization. **Passed; all fixtures rolled back.**
- Live HTTPS: email/password sign-in and authorized snapshot/direct-table/detail/ticket consistency passed for all four existing demo account emails. Employee, manager and finance account roles matched their expected access. The account named `expenseflow.admin@example.com` currently has an **employee** database role and correctly sees no other claims; this was not counted as an administrator HTTP test and its role was not changed. Admin authorization was tested in the rollback SQL suites. Anonymous workspace reads and expense saves were denied; the deployed upload endpoint’s CORS preflight passed.
- `tests/workspace-helpers.sql`: notification ownership, backwards-compatible profile writes, null input rejection, admin-only policy changes, audit records and anonymous/missing-user denial. **Passed; all fixtures and policy edits rolled back.**

The SQL suites use Storage metadata fixtures, not upload-byte transport. Local DOM adapters do not constitute browser tests. No new permanent claim/payment workflow was run: automatic approval review previously rejected a permanent-write test because it would leave audit/data pollution. Safe rollback tests were used instead. Visual desktop/mobile browser QA, real file-picker/OCR interactions and Google OAuth remain unverified in this environment. Earlier dated HTTP upload/profile results in other documents are historical evidence, not tests rerun in this update.

## Quick live demonstration checklist

1. On the home page, try the role tabs, questions, theme toggle and both account buttons. Resize to phone width and check navigation/forms.
2. Sign in as an employee with no manager. Add a title, category, positive amount, date, merchant, business purpose, payment method/date/reference and JPG/PNG/PDF receipt. Submit once. Refresh the details page: the claim should remain pending/flagged, with an assignment warning. Saving a draft should also persist.
3. As admin, assign that employee a manager under People & permissions. The assigned manager should see the pending claim; an unrelated manager must not see or approve it. Approve one claim and reject another with a reason.
4. As the employee, open the approved claim’s reimbursement ticket and submit **fictitious demo bank details**. As finance, start processing, then record a unique demo reference/date. Refresh each role’s dashboard and details page; the status and totals should agree. No money is transferred.
5. Use Reports & analytics with a historical date range, then an invalid range. Filter/sort the expense table and export CSV; all matching records should appear in the same order, including records on later pages.
6. Change your name and upload a JPG/PNG avatar under 2 MB; save and refresh. Remove the photo, save and refresh again. Sign out and confirm dashboard URLs redirect to sign-in. These browser steps are a rehearsal checklist, not a claim of completed browser QA.

## Changed source areas

`dist/index.html`, `dist/enterprise.css`, and the `landing`, `auth`, `dashboard`, `main`, `ui`, `utils`, `reports`, `report-data`, `charts`, `expenses` and `tickets` modules; one helper-hardening SQL migration; focused report/table/helper regression tests; README and security/setup notes. The existing profile form, authentication/session modules, expense tables and Storage buckets were reused.
