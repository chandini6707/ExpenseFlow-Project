# Database consistency update — 14 October 2026

The existing pages, branding, styles, authentication settings and role permissions are preserved. Expenses remain in the existing Supabase tables. No mock records or local expense database were introduced.

## Changes

- `dist/js/expense-state.js`, `utils.js`, `dashboard.js`, `reports.js`, `charts.js`, `admin.js`: shared status groups and sums calculated in integer paise. Approved totals include approved, processing and reimbursed claims. Drafts do not contribute to submitted amounts. Manager metrics exclude personal claims; finance metrics include only approved/processing/paid claims.
- `api.js`, `tickets.js`, `expenses.js`: one RLS-protected `expense_workspace` database snapshot supplies claims, approvals, payments and tickets together. Detail reads include the audit trail and authorized, masked bank summary. Reports are not truncated at the REST 1,000-row limit.
- `expenses.js`, `ui.js`, `main.js`: stable submission IDs survive refresh; duplicate action clicks are suppressed; serialized refreshes avoid competing page loads. Reports and tickets refresh on database events and when the window regains focus. Database failures display retry/error states instead of zero totals. Editing pages retain explicit refresh to avoid discarding unsaved inputs.
- `supabase/functions/save-expense/index.ts`: repeat submissions acknowledge the same saved claim only when the verified content matches. Ambiguous network errors do not delete receipts that may have committed. Replaced, unreferenced receipt objects stay private; remove them only through a separate maintenance process after excluding in-flight writes.
- `supabase/migrations/20261014122754_expense_workflow_consistency.sql`: transactional, retry-safe manager/finance operations; deferred consistency constraints; shared read RPC; audited data repair. No new tables. System audit entries can have a null actor, displayed as System.

## Submission before manager assignment

The blocking database check, mandatory-manager check and null-recipient notification were fixed in `supabase/migrations/20261014165032_allow_unassigned_employee_submissions.sql`. Ordinary employees can submit valid details and receipts without administrator authorization or a reporting manager. A policy-compliant claim is saved as `pending`; policy/duplicate warnings still produce `flagged`. Both await manager review.

The existing form, dashboard and details page show an assignment warning without disabling submission. Administrators use **Organization settings → People & permissions → Manage** to select a manager. This updates the employee profile and routes all pending/flagged claims in one transaction, with assignment audit entries. Approved/rejected/processing/paid claims retain their original reviewer. RLS and the review RPC deny managers access to unassigned or other managers' claims; employees cannot assign their own manager or approve claims.

`tests/unassigned-submission.sql` passed the complete unassigned submission → administrator assignment → manager approval/rejection → bank-details ticket → finance processing → paid workflow. It also verifies private receipt access, no self-assignment/escalation, unrelated-manager denial, repeat assignment, reassignment of open claims and preservation of completed decisions. All fixtures are rolled back.

## Status definitions

| Metric | Database statuses |
| --- | --- |
| Submitted | pending, flagged, approved, rejected, processing, paid |
| Awaiting approval | pending, flagged |
| Approved | approved, processing, paid |
| Pending reimbursement | approved, processing |
| Reimbursed | paid |
| Ready for finance | approved with a submitted bank-details ticket |

Charts group claims by **expense date**, including the reimbursed subset. CSV exports include the filtered records and their actual status; drafts are explicitly excluded from financial summary cards.

Three existing unpaid claims had an approved status without an approval record or a manager-approval audit event. The migration returned them to **Flagged for Review**, retaining their evidence and any existing bank details. It records the repair without inventing a manager decision. These claims require a fresh, documented manager decision. A legacy paid claim's missing closed ticket was restored from its real approval/payment records; no bank details or payments were invented.

## Supabase setup

The connected project already has both update migrations and `save-expense` version 3 deployed. No authentication, environment-variable or Storage bucket configuration changes are required. For another installation, apply migrations in filename order, then deploy the updated `save-expense` function. Do not rerun earlier migrations in the existing project.

## Test it in the application

1. As an ordinary employee, including one with no assigned manager, save a new expense draft and refresh. Confirm its amount, receipt and draft status remain.
2. Submit that draft. Refresh My Expenses and Reports. It must appear once, move to pending/flagged review, and contribute once to submitted totals. If a response fails, retry the same form URL; do not open a new submission to retry it.
3. For an unassigned claim, check the saved-warning message. As admin, assign its employee a manager in People & permissions → Manage. As the assigned manager, approve it with a comment. Refresh as the employee: the claim must be approved, with one reimbursement ticket. Separately reject another claim with a reason and check that rejection persists without a finance request.
4. As the employee, provide sample bank details through the approved claim's ticket. As finance, mark it processing, then reimbursed using a unique **demo** reference. Refresh after each transition.
5. Verify the expense and payment both say Reimbursed and the ticket says Completed. Check the same amount in the dashboard, ledger and analytics using matching dates/categories. Sign out and back in to verify persistence.
6. Repeat a click during saving or retry an identical request: there must be no extra claim, decision, ticket or payment. A separate new claim with the same receipt is flagged for human review, not automatically rejected.

## Verification

- `npm run check`: validates all frontend modules and 16 HTML entry points.
- `npm test`: includes status/totals, duplicate-click suppression, submission retry transport, receipt preservation on ambiguous errors, and existing authentication/profile tests.
- `tests/database-regression.sql`: real PostgreSQL submission, duplicate detection, approval/rejection, bank-ticket, processing and paid transitions; identical retries; unique payment protection; cross-role RLS; forbidden direct writes; forced consistency constraints; a snapshot larger than 1,000 rows. Every test fixture is rolled back.
- Read-only checks compare the deployed snapshot API with persisted table records for authorized roles.
- Visual browser QA was unavailable. Automatic approval review blocked a permanent live-write workflow test because of audit/data pollution risk; rollback SQL tests and read-only API checks are used instead. No claims were created by the blocked test.

The SQL suite should normally run on a development project using `psql ... -v ON_ERROR_STOP=1 -f tests/database-regression.sql`. It uses Storage metadata fixtures to check database rules, not actual file transport. The subsequent workspace audit hardens the remaining public helpers; see `WORKSPACE-UPDATE.md` for current advisor results.
