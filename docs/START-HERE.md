# ExpenseFlow setup and live project status

The frontend already contains your public Supabase URL and publishable key.

Historical checks on 11 October 2026 for `tzgbroijqcmsomgpvmhp`:

| Component | Result |
| --- | --- |
| Project URL and public key | Accepted by Supabase Auth |
| Email authentication | Enabled |
| Email confirmation | Disabled; new accounts receive a session immediately |
| ExpenseFlow database | Installed: seven tables, category limits, RLS and workflow functions |
| Receipt upload function | `save-expense` v1 deployed; website preflight passes and invalid sessions are rejected |
| Private receipts bucket | Installed with 5 MB JPG/PNG/PDF limits |
| Google authentication | Enabled, but Google returns `401 invalid_client`: OAuth client not found |

**The database and upload service are already installed in this project. Do not run the initial migration again.** The remaining Google fix is to replace the configured Client ID with an active Google Web OAuth client and its matching secret; see `AUTHENTICATION.md`. The initial migration is registered as `20261011043101_expenseflow_initial_schema`.

## Step 1 — Create the database (fresh projects only)

1. Open https://supabase.com/dashboard/project/tzgbroijqcmsomgpvmhp.
2. Select **SQL Editor → New query**.
3. Open `supabase/migrations/20261011043101_expenseflow_initial_schema.sql` from the extracted project.
4. Copy the entire file into the SQL Editor and click **Run**.

This creates the database, secure policies and private receipts bucket. Existing registered accounts receive employee profiles too. Run this migration once in your fresh project.

## Step 2 — Install the upload function (fresh projects or future updates)

Open a terminal inside the extracted **ExpenseFlow** folder. With Node.js installed, run:

```bash
npx supabase login
npx supabase link --project-ref tzgbroijqcmsomgpvmhp
npx supabase secrets set ALLOWED_ORIGINS=https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site,http://localhost:5500,http://127.0.0.1:5500
npx supabase functions deploy save-expense --no-verify-jwt
```

Complete the CLI's normal browser login and database-password prompts locally. The function independently verifies every user's token with Supabase Auth before uploads or database writes; keep that verification in place. Its built-in default origins are the hosted website, `http://localhost:5500` and `http://127.0.0.1:5500`. Setting `ALLOWED_ORIGINS` replaces those defaults.

## Step 3 — Enable immediate registration and Google sign-in

**Already done in the live project:** Email sign-in is enabled and Confirm email is OFF. Preserve those settings for this demonstration. New employees receive an authenticated session immediately. Full instructions for another project: `docs/AUTHENTICATION.md`.

Under **Authentication → URL Configuration**, use the hosted URL as Site URL:

```text
https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site
```

Add these allowed redirect URLs:

```text
https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site/login.html
https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site/reset-password.html
http://localhost:5500/login.html
http://localhost:5500/reset-password.html
```

For Google sign-in, follow README section 6. Your Google authorized callback URI is:

```text
https://tzgbroijqcmsomgpvmhp.supabase.co/auth/v1/callback
```

Enable Google and enter Google credentials in Supabase's Google provider settings. The app checks that the provider is enabled before redirecting. Email/password login can be used independently after database setup.

## Step 4 — Create the demonstration accounts

The live project already has four real demo accounts: `expenseflow.employee@example.com`, `expenseflow.manager@example.com`, `expenseflow.finance@example.com`, and `expenseflow.admin@example.com`. Their generated password is provided in `DEMO-ACCOUNTS.txt` inside the downloaded ZIP, outside the published website and source repository. Your earlier account retains employee access and is assigned to the demo manager. New employees can be assigned a manager through the demo admin account.

For a fresh project, follow README section 8 to seed real accounts. The server-only key is used locally by the seed script, never in webpage configuration. Alternatively register accounts, promote your own account to the first admin in SQL Editor as documented, then manage roles and assign managers through the app.

Finally, follow `docs/DEMO_GUIDE.md` to test the Bengaluru expense workflow. The three claims are ₹2,000 travel, ₹1,500 accommodation and ₹500 food.


For the current landing page, simplified dashboard, six-migration setup and latest test evidence, follow `../README.md` and `WORKSPACE-UPDATE.md`. New employees can submit before an administrator assigns a manager.
