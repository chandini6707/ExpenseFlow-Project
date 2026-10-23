# Fix ExpenseFlow sign-in

The live project was checked on 11 October 2026:

- Google provider: enabled (`external.google: true`), but Google rejects the configured client with `Error 401: invalid_client — The OAuth client was not found.`
- Email confirmation: disabled (`mailer_autoconfirm: true`).
- Email/password sign-in and registration: enabled.

The missing database and receipt service were installed and database workflow tests passed. The remaining sign-in failure is the Google OAuth client configuration. Replace the Client ID and matching secret in Supabase using an active **Web application** client from Google Cloud. Copy the entire ID ending in `.apps.googleusercontent.com`; the Supabase publishable key and Google project ID do not go in that field. If your earlier client is absent, create a new Web client using the URLs below. A secret is shown when created; save it securely then. No frontend redeployment is needed after correcting provider credentials.

## 1. Remove registration email confirmation

This is already complete in the live project. These steps are for another installation:

1. Open https://supabase.com/dashboard/project/tzgbroijqcmsomgpvmhp/auth/providers.
2. Select **Email** under **Sign In / Providers**.
3. Keep email sign-in enabled. Switch **Confirm email OFF** and **Save**.
4. Return to ExpenseFlow, create an employee account, and check that it signs in immediately.

This setting is intentional for the requested college demonstration: email ownership is not verified during registration. Passwords, authenticated sessions and database role permissions are still required. Forgot password remains a separate user-requested email flow.

If an account created earlier still reports `Email not confirmed`, its existing Auth record needs activation. A project administrator can run `supabase.auth.admin.updateUserById(userID, { email_confirm: true })` in a trusted server/local script for that specific known account. Read the account ID from Supabase Authentication → Users. Do not put an admin client or secret key in the website. Do not delete users or bulk-confirm unrelated accounts to resolve this.

## 2. Correct the Google OAuth client

1. In https://console.cloud.google.com/auth/clients, create or select a **Web application** OAuth client for your project.
2. Configure the Google consent screen and add your demo Google accounts as test users if the application is in testing mode.
3. Set the authorized JavaScript origin to:

   ```text
   https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site
   ```

4. Set the Google authorized redirect URI to exactly:

   ```text
   https://tzgbroijqcmsomgpvmhp.supabase.co/auth/v1/callback
   ```

5. In Supabase **Authentication → Sign In / Providers → Google**, keep Google enabled, replace the Client IDs field with this active Web client's complete **Client ID**, and paste the **Client secret from the same client**. Remove stale IDs and accidental quotes/spaces. Save. The secret belongs in Supabase only.
6. In Supabase **Authentication → URL Configuration**, set Site URL to the website origin above and add this allowed redirect:

   ```text
   https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site/login.html
   ```

7. Open the hosted login page directly in a browser tab. Click **Continue with Google**, complete Google's sign-in, and return to the same tab/browser for the PKCE callback.

The Google callback is the Supabase URL, while the Supabase allowed redirect is the ExpenseFlow login URL. They serve different parts of the flow. Preserve existing localhost and reset-password redirects.

## 3. Initialize the workspace database

The workspace database is now installed in this project, and the account that existed before installation received an employee profile. Do not rerun the initial migration here. For a fresh project, use `supabase/migrations/20261011043101_expenseflow_initial_schema.sql` once as described in `START-HERE.md`.

## Verification

- New registration: creates an Auth account, returns a session, and opens the employee dashboard without an email confirmation.
- Sign out and email/password sign-in: returns to the same employee workspace.
- Google: account selection returns to ExpenseFlow with a real authenticated session.
- Cancel Google: a readable inline message appears; no false successful sign-in.
- A missing provider or required confirmation setting is reported without navigating to a raw Supabase error page or pretending to authenticate.

Local regression tests cover disabled providers, confirmation gating, returned sessions, callback errors (including invalid_client) and redirects. Live database tests passed for RLS, duplicate detection, approvals and finance transitions with temporary fixtures rolled back. Separate live HTTP tests successfully signed in all four demo roles with email/password, read their profiles, uploaded the three sample receipts, downloaded private signed receipts and completed one manager-to-finance reimbursement workflow. Successful Google sign-in remains unverified until the Google client credentials are corrected.

Official references:

- https://supabase.com/docs/guides/auth/general-configuration
- https://supabase.com/docs/guides/auth/social-login/auth-google
- https://supabase.com/docs/reference/javascript/auth-signup
- https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid
