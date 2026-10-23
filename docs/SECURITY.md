# Permissions and trust boundaries

| Record | Employee | Manager | Finance | Admin |
| --- | --- | --- | --- | --- |
| Expenses | Own rows | Assigned non-drafts / historical own rows | Approved/processing/paid / historical own rows | All |
| Private profiles | Own only | Own only | Own only | Own only |
| Company directory | Own / reporting manager / authorized identities | Assigned employees / authorized identities | Authorized claim identities | Organization identities and role requests |
| Receipts | Attached to own claims | Attached to assigned requests | Attached to authorized finance claims | All |
| Notifications | Own only | Own only | Own only | Own only |
| Audit | Own claim events | Assigned claim events | Authorized finance claim events | All |
| Policies | Read | Read | Read | Configure |

Every business table enables RLS. Authenticated clients have SELECT grants, not direct mutation grants. Secure functions control all writes. Client-side role checks improve navigation but never determine permission.

- **Registration trigger:** constant employee role; user-editable metadata cannot grant privileges.
- **Expense Edge Function:** verifies the Bearer token through Auth, derives the actor, enforces the employee role, owns drafts, limits streamed request sizes, checks file signatures and hashes actual receipt bytes. The gateway check is disabled only because this verification is explicit inside the handler.
- **Expense writer:** only service_role may execute; SQL repeats validation, employee ownership, limits and duplicates. Missing managers are allowed at submission; manager assignment is required for a review decision. It is inaccessible to authenticated browser clients. File hashing is serialized by advisory locks; employee row locks serialize similarity checks.
- **Manager review:** assigned manager role only, no self-approval, valid pending/flagged transitions and documented reasons for rejection/policy exceptions. Current limits are rechecked.
- **Finance:** finance role only, row-locked approved → processing → paid transitions, one reimbursement per expense, unique reference and valid payment date. No bank API exists.
- **Admin:** admin role only, serialized role changes, last-admin protection, and manager reassignment/pending-review checks.
- **Audit/notifications:** written in the workflow transaction; no client audit mutation. Notifications are marked read only for the caller.

Security-definer functions use empty search_path and qualified tables. Internal helpers are not in the exposed public API schema. Receipt storage is private and client writes to receipts are disallowed; signed receipt URLs expire in 120 seconds. A file fingerprint identifies bytes, not a legitimate purchase. Signature checks are not antivirus scanning. SVG uploads are disallowed.

User text is escaped; CSV formulas are neutralized. Frontend configuration rejects secret/service-role keys. Auth tokens are managed by the Supabase client. Pinned CDN dependencies require internet access.

This is a single-organization college application, not a tenant-isolated multi-company service. Submitted claims retain their assigned-manager snapshot for accountability. On 11 October 2026 the live database passed the rollback regression suite, including role/RLS isolation, role-escalation rejection, duplicate flags, assigned-manager approval, finance state transitions and duplicate-processing rejection. The upload endpoint passed origin/preflight and invalid-session checks. Google OAuth still requires correction of the active client credentials. Visual browser QA was not performed.

The Supabase security advisor flags the authenticated security-definer workflow RPCs. These are intentional: they enforce identity, role, record assignment and transition checks before privileged writes. They grant no anonymous execution. Review guidance: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable. The project also contains Supabase's existing `rls_auto_enable` event-trigger function; its return type is `event_trigger`, so it is a maintenance hook rather than an application RPC. Leaked-password protection remains disabled in the project; deployment guidance: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

Production additionally needs retention/account-deletion procedures, monitoring, rate limits, backups, malware scanning, hardened asset delivery, organization eligibility controls and independent review. No server-only credentials are shipped to the frontend.

The live HTTP integration test also authenticated all four demo roles, uploaded and hashed three original sample receipt files, verified signed private downloads and completed a manager-approved simulated reimbursement visible to the employee. All test sessions were signed out afterward. Demo credentials are included only in the private project download, outside `dist/` and Git.

## Purchase proof and bank-details tickets

`20261011133337_purchase_proof_and_bank_tickets.sql` adds a public ticket table containing only workflow metadata and a separate `expense_private.bank_details` table. The private schema must stay outside Data API exposed schemas. Bank details have RLS enabled and no client grants or policies: the security advisor's “RLS Enabled No Policy” informational notice is intentional deny-all access (https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). Public bank RPCs use SECURITY INVOKER wrappers around internal, identity-checked functions.

Only the claim owner can submit bank details after approval, including owners whose role was later changed. Summaries expose only the last four account digits to the owner and finance; managers and other administrators receive ticket status only. Full numbers require the finance role and an explicit reveal operation, which creates an audit event. Numbers are not persisted in browser storage, URL parameters, audit metadata, notifications or CSV reports. Database administrators can access stored bank data through their privileged database access; this is access control, not application-level field encryption. IFSC validation checks format only, not bank ownership or a live bank directory.

The same expense-row lock serializes bank changes and finance processing. Bank details cannot be edited after processing starts. Duplicate identical submissions are idempotent. Existing approved/unpaid claims receive one ticket during upgrade; already-paid records remain intact. A processing claim imported by the upgrade may supply its missing bank details once, then those details are locked.

Purchase and payment proof each have a 5 MB limit and signature checks. The total multipart body is bounded, both SHA-256 hashes are computed from stored/received bytes, and client-supplied attachment paths are overwritten. Both evidence files use the private receipt bucket and claim-specific signed access.

Expense filing is employee-only: administrators, managers and finance users cannot submit claims or save/edit drafts. The Edge Function and database writer enforce the role independently of the browser. Admin views omit the draft-edit action, and the frontend refreshes the current database role before rendering and when a tab regains focus. Administrative expense monitoring remains available.

The October 14 account update uses owner-only full-profile RLS and a safe directory RPC. Private avatar Storage has owner-folder read/insert/delete policies and server-enforced size/MIME limits. Role requests never determine authorization. See [PROFILE-AND-THEME.md](PROFILE-AND-THEME.md) for implementation and test details. The advisor still reports existing identity-checked public workflow functions, the platform `rls_auto_enable` event-trigger helper, intentional deny-all bank storage and disabled leaked-password protection; no new profile or avatar security warning was introduced.


## Workspace audit — 14 October 2026

`20261014174834_harden_workspace_helpers.sql` preserves the existing policy, notification and compatibility-profile RPC names while removing their public SECURITY DEFINER implementations. Private implementations check `auth.uid()` and the authorized database role, use an empty search path and retain explicit authenticated-only execution grants. The legacy profile endpoint delegates to the current profile validator. API execution of the platform RLS DDL-trigger helper is revoked without disabling that trigger. No tables, roles, claims, Auth settings or Storage buckets were replaced.

Post-migration advisors show no publicly exposed privileged-function warnings. Two existing notices remain: the private bank table deliberately has deny-all RLS (no client policy), and leaked-password protection is disabled in Auth. The latter is a deployment setting, not a permission bypass; enable it if supported by your Supabase plan at [password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). See [database linter guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) for the intentional private-table notice.

See `WORKSPACE-UPDATE.md` for current verification evidence and remaining browser/Google-OAuth limits.
