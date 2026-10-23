# Account, profile and theme update

This update extends the existing application and the existing `profiles` table. It preserves the Supabase project, Auth providers, receipts, expense workflow and purple branding.

## Database and Storage

Apply `supabase/migrations/20261014045843_profile_roles_and_private_avatars.sql` once after the previous two migrations. It is already applied to the connected project. No environment-variable or OAuth configuration changes are needed.

- Adds contact/job details, role-specific descriptions, a generated employee ID, avatar path and role-request review fields to `profiles`.
- Full profile rows are owner-only under RLS. The `profile_directory` RPC returns only permitted company identities to the existing expense, manager and admin pages. It never returns phone numbers, private avatar paths or cost centres.
- `save_my_profile` validates the caller and allowed fields; IDs, role, email and reporting manager cannot be self-edited. Role-specific descriptions do not grant permissions.
- Creates the **private** `profile-avatars` bucket (JPG/PNG, maximum 2 MB). Authenticated users may insert/read/delete only files under their own UUID folder. No public or cross-user policies are required. Profile saves confirm the stored object, MIME, size and ownership. Pictures are displayed using expiring signed URLs, never stored public links. Receipt bucket policies remain unchanged.
- Public signup always creates an employee. `requested_role` is intent only. The administrator reviews pending requests in Organization settings, using an identity-checked, row-locked RPC. Approval is audited, notifies the user and assigns the effective database role. Repeat/stale reviews fail. Google registration stores a short-lived role intent in session storage and saves it after successful Supabase authentication.
- Employees may continue using their authorized employee dashboard while a higher role is pending. After authorization, refreshing or focusing the tab routes them to the correct dashboard. Role changes take effect immediately in database permissions.

## Interface changes

`enterprise.css`, `ui.js`, `charts.js` and the shared `theme-init.js` provide dark surfaces, form/table/status colors and live chart recoloring. Every HTML entry loads theme initialization before styles. Theme choice persists between pages and across sign-in; restricted browser storage falls back to in-memory selection.

`session.js` centralizes current-device Supabase sign-out, cleanup of app/demo session keys and cookies, and unsaved-form confirmation. It preserves the theme and public project settings. Existing demo accounts use real Supabase Auth; there is no separate insecure demo authentication system. Sign-out is in the top account menu, sidebar and profile page. Protected entry points validate the current user through Auth; database RLS remains the data-access boundary. Back-cache restoration reloads the session gate before rendering protected content.

`account.js` adds picture preview/remove/upload and role-relevant fields; `api.js` uses the safe directory; `auth.js` / `auth-flow.js` add role cards without changing email/password or Google OAuth; `admin.js` adds the request queue. The avatar stays private; profile name, department and authorized role remain visible where the expense workflow requires them.

## Verification

- `npm run check`: syntax, module imports and local references across 17 modules / 16 HTML pages.
- `npm test`: 30 automated checks, including role routing, registration metadata, session cleanup selection, chart text contrast, existing auth/error handling, amounts/dates and expense-proof validation.
- `tests/profile-security.sql`: real PostgreSQL checks for request persistence without escalation, owner-only profile reads, safe directory, protected fields, role-specific edits, avatar isolation, admin approvals/rejections, duplicate review prevention and notifications. Temporary fixtures roll back.
- `tests/database-regression.sql`: existing expense, receipt, manager, finance and bank-ticket security/workflow regression checks; temporary fixtures roll back.
- Live HTTPS tests passed for all four demo roles: sign-in and authorized expense/directory reads; avatar upload and signed download; private/public and cross-user access denial; MIME/2 MB restrictions; role tampering denial; persistence after sign-out/sign-in; refresh-token revocation and avatar removal. The test profile was restored, the uploaded test image removed and the successful test sessions signed out.
- Manual browser QA checklist: toggle both themes on login, signup, all four dashboards, profile, reports and an expense detail modal; resize to mobile; upload/save/remove an avatar; sign out and use Back/direct dashboard URL; verify a pending role request using two accounts. Browser automation is unavailable in this session, so these visual interactions have not been browser-tested.

Existing Google provider credentials and organization restrictions are unchanged. A full Google OAuth round trip requires the user's Google account and remains unverified. Email addresses are displayed read-only; changing sign-in identity is intentionally outside profile editing.

## Profile photo sizing follow-up

The profile editor now uses explicit 86 px previews and 75 px summary photos, with fixed width/height, circular clipping, `object-fit: cover`, and bounded image dimensions. The upload/remove controls use a two-column grid that stacks on narrow mobile screens. Account details, filenames and form fields wrap within their panels in both themes. A selection counter prevents late image decoding from restoring a removed photo, and saving waits for validation to finish. JPG/PNG and the 2 MB limit remain unchanged. No SQL, bucket, authentication or role-permission changes are required.

Changed files: `dist/enterprise.css`, `dist/js/account.js`, `tests/profile-avatar.test.mjs`, and this note. The automated suite includes image validation, fixed image attributes, removal fallbacks and stale image-error handling. Browser visual QA remains unavailable.

The focused live Supabase check passed with a 2400 × 1600 PNG: upload, save, a fresh profile read and signed download, followed by removal and another fresh profile read showing both avatar fields empty. The test account was restored and the temporary object removed.
