# ExpenseFlow — Enterprise Expense Verification & Reimbursement Platform

A modular college-project application built with **HTML5, CSS3, vanilla JavaScript, Supabase Auth/PostgreSQL/Storage, Chart.js, Lucide and optional Tesseract.js image OCR**. No React or frontend build step. Core workflows use real Supabase operations, never fake login or browser-local expense records.

**Live project, updated 14 October 2026:** `tzgbroijqcmsomgpvmhp.supabase.co` has the complete schema, role permissions, private purchase/payment proof storage and the deployed `save-expense` function. Approved purchases generate in-app bank-details tickets. Email confirmation is disabled. Reimbursements record a simulation, never a bank transfer. See `docs/BANK-TICKETS.md` for the new workflow and `docs/AUTHENTICATION.md` for Google setup. The latest observed Google callback error during troubleshooting was an invalid Client Secret; matching Google credentials must be configured in Supabase.

See [Database consistency update and test steps](docs/DATABASE-CONSISTENCY.md) for the current workflow fixes, status definitions and verification limits.

## Project structure

| Directory / file | Purpose |
| --- | --- |
| `dist/` | All 16 HTML pages, styles, icons and public configuration |
| `dist/js/` | Modular frontend: Auth, API, UI, charts, expenses, OCR, admin and reports |
| `supabase/migrations/20261011043101_expenseflow_initial_schema.sql` | Tables, constraints, indexes, RLS, Storage and secure RPCs |
| `supabase/functions/save-expense/` | Authenticated server upload, validation and receipt hashing |
| `samples/` | Clearly labeled Bengaluru demonstration PNG receipts |
| `scripts/seed-demo.mjs` | Creates actual Auth accounts and submits real database claims |
| `tests/` | Local unit tests and transactional database regression SQL |
| `docs/DEMO_GUIDE.md` | Presentation and manual test instructions |
| `docs/SECURITY.md` | Permission matrix and implementation boundaries |
| `.env.example` | Server-only local seed configuration |

The HTML pages are: Landing, Login, Registration, Forgot Password, Reset Password, Employee Dashboard, Submit Expense, My Expenses, Expense Details, Manager Dashboard, Finance Dashboard, Reports & Analytics, Notifications, User Profile Admin Settings and Reimbursement Tickets.

## 1. Create Supabase and initialize the database

The live project already has all six migrations. The following installation steps apply only to a fresh project; do not rerun the initial migration in the live database.

1. Create a fresh project at https://supabase.com. This application models **one organization per project**.
2. Open **SQL Editor → New query**.
3. Run the complete `supabase/migrations/20261011043101_expenseflow_initial_schema.sql` file **once**. It creates all seven tables, relationships, indexes, secure functions, RLS, notifications, audit logs and the private receipts bucket.
4. Then run `supabase/migrations/20261011133337_purchase_proof_and_bank_tickets.sql` once. This adds transaction details, reimbursement tickets and the protected bank-details workflow.
5. Run `supabase/migrations/20261014045843_profile_roles_and_private_avatars.sql`, then `supabase/migrations/20261014122754_expense_workflow_consistency.sql`, then `supabase/migrations/20261014165032_allow_unassigned_employee_submissions.sql`, then `supabase/migrations/20261014174834_harden_workspace_helpers.sql`.
6. Keep the default API exposed schema as `public`. Do not expose the internal `expense_private` schema.
7. Alternatively, link with the Supabase CLI and run `supabase db push`; do not apply the migration through both methods.

The migration is transactional and intended for a fresh project. If it fails, fix the reported error before rerunning the complete file.

## 2. Configure the frontend

Set **Project URL** and **public publishable key** (or legacy **anon** key) in `dist/config.js`:

```js
window.EXPENSEFLOW_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',
  supabaseKey: 'YOUR_PUBLIC_PUBLISHABLE_OR_ANON_KEY',
  configVersion: 2,
  appName: 'ExpenseFlow',
  organization: 'Northstar Technologies'
};
```

The landing/sign-in pages also have **Project configuration**, which stores these public settings in the current browser and overrides `config.js` for the matching `configVersion`. Increment that version when deploying a different Supabase project so old browser settings cannot keep visitors on the previous backend. It does not store expenses locally or bypass authentication.

**Never put a service-role key, secret key, database password or Google client secret in `dist/`.** Public keys identify the project; authenticated server functions and RLS determine access.

## 3. Deploy the secure expense-saving function

Use the Supabase CLI (official setup: https://supabase.com/docs/guides/cli/getting-started). Run from the project root:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set ALLOWED_ORIGINS=http://localhost:5500,http://127.0.0.1:5500
supabase functions deploy save-expense --no-verify-jwt
```

The function defaults to the existing hosted website origin plus `http://localhost:5500` and `http://127.0.0.1:5500`. To override these, include every permitted origin in the comma-separated `ALLOWED_ORIGINS` value, without trailing slashes. Setting this value replaces the complete allowlist.

The gateway setting `verify_jwt = false` is intentional: **the handler itself verifies the Bearer token using Supabase Auth.getUser before any privileged action**. This supports projects using legacy/asymmetric signing keys. It does not permit anonymous expense submission. Do not remove that check.

The function uses Supabase’s built-in server-only `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` environment values. It validates authenticated identity, draft ownership, bounded request/file sizes and file signatures, calculates SHA-256 from the actual bytes, and invokes the protected database writer. Browser-supplied hashes/roles/employee IDs are not trusted.

See [Profile, role requests and theme update](docs/PROFILE-AND-THEME.md) for the latest account features and security tests. Fresh installations must also run `supabase/migrations/20261014045843_profile_roles_and_private_avatars.sql` after the first two migrations. It creates the private avatar bucket automatically.

## 4. Storage configuration

The migration creates the `receipts` bucket with:

- **Public: false**
- **Maximum size: 5 MB**
- MIME types: `image/jpeg`, `image/png`, `application/pdf`
- Path: `authenticated-user-id/expense-id/random-file-id.ext`

Client SELECT access is restricted to receipts attached to authorized claims. Clients have no direct upload/update/delete policies; the authenticated Edge Function manages files. Authorized receipt URLs expire in 120 seconds. When using a pre-existing project, check that unrelated permissive Storage policies do not grant broader access.

## 5. Email Auth and redirect URLs

In **Authentication → URL Configuration**, set:

- Site URL: `http://localhost:5500`
- Redirect: `http://localhost:5500/login.html`
- Redirect: `http://localhost:5500/reset-password.html`
- Add corresponding `127.0.0.1` URLs if you use that hostname.
- Add the hosted frontend’s login/reset URLs when deploying.

Enable email/password sign-in. For this college demonstration, open **Authentication → Sign In / Providers → Email**, switch **Confirm email OFF**, and save. New registrations then receive a real Supabase session immediately without a confirmation email. The frontend checks this setting before registration and does not initiate signup while confirmation remains required. Changing frontend code or local `config.toml` does not change a hosted project's Auth settings.

Accounts created before this change may still require administrator activation. A trusted administrator can activate the specific account using the Supabase Auth Admin API with `email_confirm: true`; never expose that API's secret key in the browser. See `docs/AUTHENTICATION.md` for the full fix. Password recovery still uses an explicitly requested secure reset email; it is separate from the removed registration-confirmation step.

Every new account, including Google accounts, receives **employee** access from the database trigger. Registration offers role requests; selecting manager or finance does not grant those privileges. Employees can submit complete claims immediately, including before a manager is assigned. Unassigned claims remain pending review with a clear warning. Administrator assignment later routes all undecided claims to the selected manager; it does not grant the employee manager privileges.

## 6. Google OAuth

1. Open https://console.cloud.google.com and select/create a project.
2. Configure Google Auth Platform / the OAuth consent screen. Add your demonstration Google accounts as test users if the app is in testing mode.
3. Create **OAuth client ID → Web application**.
4. Add `http://localhost:5500` as an authorized JavaScript origin; add your hosted frontend origin if applicable.
5. Add this authorized redirect URI:

   ```text
   https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
   ```

6. In Supabase **Authentication → Sign In / Providers → Google**, enable Google and enter its client ID and client secret. Keep the secret in provider settings only.
7. Include the frontend `login.html` URL in Supabase’s redirect allowlist.
8. Use **Continue with Google**. The app uses a Supabase session and redirects according to the database-assigned role.

Google publishing/authorized-domain requirements depend on hosting. Localhost and configured test users support the local college demonstration. Official guide: https://supabase.com/docs/guides/auth/social-login/auth-google.

## 7. Run locally

Serve `dist/` using Python 3. Do not open HTML using `file://`. An internet connection is needed for Supabase and the pinned CDN libraries.

Windows:

```powershell
py -m http.server 5500 --directory dist --bind 127.0.0.1
```

macOS / Linux:

```bash
python3 -m http.server 5500 --directory dist --bind 127.0.0.1
```

Open http://localhost:5500. `npm run dev` runs the same command on systems with Node and `python3`. No `npm install` is needed.

## 8. Safe sample accounts and real seed data

The live project is already seeded with the four accounts listed below. Use `DEMO-ACCOUNTS.txt` in the downloaded ZIP for the generated demo password; it is excluded from Git and is not published to the website. The ₹2,000 travel claim completed a real database approval and simulated reimbursement. The ₹1,500 hotel and ₹500 food claims are pending for your presentation. The following seed-script instructions are for a fresh installation or an intentional reset of the demo accounts.

Use **Node 20.6+**. Copy `.env.example` to `.env` and fill the URL, server-only service-role key and a strong `DEMO_PASSWORD` (minimum 10 characters). Keep `.env` at the project root; do not serve or commit it.

```bash
node --env-file=.env scripts/seed-demo.mjs
```

The script creates real Auth accounts, assigns roles in the trusted server context and submits sample receipts through the authenticated Edge Function:

| Role | Email (default domain) | Purpose |
| --- | --- | --- |
| Employee | expenseflow.employee@example.com | Submit/edit drafts and track claims |
| Manager | expenseflow.manager@example.com | Review assigned expenses |
| Finance | expenseflow.finance@example.com | Process demo reimbursements |
| Admin | expenseflow.admin@example.com | Manage roles, managers, policies and audit logs |

Live account note (15 October 2026): `expenseflow.admin@example.com` currently has employee access. The email’s name does not grant privileges. Use an account with the authorized admin database role for administration; do not reseed or promote accounts merely to match their names.

Use your selected `DEMO_PASSWORD` for these four accounts. They are confirmed by the trusted Admin Auth API, so SMTP is not required for their login. They are illustrative accounts, not real employees. The seeder does not print passwords/tokens. Rerunning it restores the selected roles/password and skips sample expenses already present by title.

The three Bengaluru claims are **Travel ₹2,000**, **Hotel ₹1,500**, and **Food ₹500**. Receipts clearly say **SAMPLE / DEMO ONLY**. They start pending so you can perform the full approval/reimbursement flow.

For manually registered accounts, bootstrap the first admin only from the trusted Supabase SQL Editor:

```sql
update public.profiles set role = 'admin' where email = 'YOUR_ADMIN_EMAIL';
```

There is no browser-accessible bootstrap endpoint. Use the Admin UI for subsequent role changes and manager assignments.

## 9. Workflow and verification

- Draft → Pending Manager Approval / Flagged for Review → Approved / Rejected → Processing Reimbursement → Reimbursed.
- Required fields, positive amount, valid dates and a purchase receipt are enforced by the backend. A missing manager does not block submission; only an assigned authorized manager can review it.
- Admin-adjustable limits, inactive categories and merchant/category mismatch heuristics determine policy warnings.
- Exact receipt hashes across submitted claims are flagged as possible duplicates; employee/vendor/date/amount and vendor/invoice comparisons flag similar claims.
- Warnings do not expose another employee’s private details or automatically declare fraud.
- Assigned managers may approve flagged claims with a documented 8+ character reason. Rejection always requires a reason. Current policies are checked again at review time.
- Managers cannot approve their own claims. SQL row locks, single approval/reimbursement records and unique payment references prevent duplicate processing.
- Manager approval creates a bank-details ticket and an in-app notification. The employee provides account holder name, bank name, matching account numbers and IFSC.
- Finance can start processing only after those details are submitted. Bank details are locked once processing starts; payment completion closes the ticket. No bank transfer is integrated.
- Full account numbers live in the unexposed `expense_private` schema, are masked in summaries, and can be revealed only by finance through an audited RPC. They never appear in CSV exports or notifications.
- Submit proof of purchase plus the payment method, payment date and a transaction/UTR reference for non-cash purchases. Optional payment-proof uploads are checked, hashed and stored privately on the server.
- Audit and notification records are committed with each workflow operation.

## 10. OCR

Click **Extract receipt details** after uploading an image. Tesseract.js runs in the browser and attempts to infer merchant, date and total. Blank merchant/amount fields are prefilled; detected dates populate the date field. Review and correct every result. PDF uploads and OCR failures use manual entry. OCR does not guarantee receipt authenticity.

## 11. Checks and remaining integration testing

For the latest landing, dashboard, security and reporting changes and the actual tests run on 14 October 2026, see [WORKSPACE-UPDATE.md](docs/WORKSPACE-UPDATE.md). Historical tests below are dated and are not claims of a new browser or upload test.

Use Node.js 24 for the local test suite (the site itself remains buildless).

```bash
npm test
npm run check
```

Local tests cover server validation, invalid dates/amounts, file signatures, UUIDs, secret-key rejection, HTML escaping, expense filters/sorting, CSV safety and OCR parsing. The project checker validates JavaScript syntax, module imports and all 16 HTML entry points.

`tests/database-regression.sql` tests RLS and status rules with temporary fixtures and rolls them back. After applying the migration, run against your **development** Supabase database:

```bash
psql "YOUR_DEVELOPMENT_DATABASE_CONNECTION_STRING" -v ON_ERROR_STOP=1 -f tests/database-regression.sql
```

This SQL suite uses Storage metadata fixtures to test database rules, not actual upload transport. It passed against the live college-demo database on 11 October 2026; temporary test accounts and claims were rolled back. Separate live HTTP tests passed for email/password sign-in and profile reads in all four roles, three genuine receipt uploads, server-computed hashes, private signed receipt downloads, manager approval, finance processing, simulated reimbursement and the employee notification. The deployed function also passed origin/preflight and invalid-session checks. The three clearly labeled sample claims remain for demonstration. Google login is blocked by the configured Google OAuth client; visual browser QA was not executed.

## 12. Hosting and troubleshooting

Deploy only `dist/` to an HTTPS static host. Database/functions stay in Supabase. Add the hosted origin to `ALLOWED_ORIGINS` and the Auth redirect allowlist, update public `config.js`, and configure Google for that origin. Never publish `.env` or server-only credentials.

| Issue | Resolution |
| --- | --- |
| Sign-in disabled | Configure valid public URL/key |
| Database not initialized | Run the complete migration |
| Origin not permitted | Update Edge `ALLOWED_ORIGINS` |
| Expense function 404 | Deploy `save-expense` |
| Employee cannot submit | Check required fields, receipt, authenticated employee role and the deployed save-expense function. No assigned manager is required. |
| Google login error | Check provider credentials, test users, callback and redirects |
| Registration asks for setup | Turn Confirm email OFF in the Supabase Email provider; see `docs/AUTHENTICATION.md` |
| Existing account not confirmed | Administrator activates that specific Auth account |
| Password-reset email not received | Check SMTP settings, rate limits and spam |
| No live notifications | Check Realtime; Refresh still loads database rows |
| OCR/chart CDN failure | Allow network access; manual entry/tables remain usable |

See `docs/SECURITY.md` for trust boundaries. Enterprise production requires operational monitoring, retention, backups, rate limits and independent review beyond this college model. Actual bank payments are deliberately out of scope.
