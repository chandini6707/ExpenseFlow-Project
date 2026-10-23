# College demonstration guide

The hosted project has its database, receipt function and sample accounts installed. Find the generated password in `DEMO-ACCOUNTS.txt` inside the downloaded ZIP. Use separate browser profiles/private windows or log out between roles. These are real authenticated accounts, not a role-switch simulation. For a new project, complete the README setup and seed script first.

## Five-minute presentation

The travel claim is already reimbursed in the simulation after the live integration test. The hotel and food claims are still pending, so use those to demonstrate approvals and finance processing.

1. **Employee:** sign in as `expenseflow.employee@example.com`. Show the dashboard and three Bengaluru claims. Open a private sample receipt and explain its SAMPLE / DEMO ONLY label.
2. **Manager:** sign in as `expenseflow.manager@example.com`. Review each assigned receipt and policy summary; approve the claims and show approval history.
3. **Finance:** sign in as `expenseflow.finance@example.com`. Open an approved claim, click **Start processing**, enter a unique `DEMO-` reference and today’s date, then confirm **Mark reimbursed (demo)**. Explain that this records a simulation and transfers no money.
4. **Employee:** return to show the completed status timeline, notification and reimbursement total.
5. **Admin:** show role/manager assignments, editable limits, organization analytics and immutable audit entries.

## Manual verification

| Test | Action | Expected |
| --- | --- | --- |
| No manager assigned | Submit a valid claim as an employee with no manager | Saved as pending/flagged review with an assignment warning; no role upgrade needed |
| Assign later | Admin → People & permissions → Manage → select manager | Pending/flagged claims route to that manager; other managers cannot review them |
| Draft | Save an incomplete-purpose draft, then edit it | Actual database draft; add receipt/purpose before submission |
| Policy limit | Submit Food ₹1,200 | Flagged against the ₹1,000 Food limit |
| Exact duplicate | Upload a previously submitted file again | Server hash produces Possible Duplicate warning |
| Similar claim | Different file, same employee/vendor/date/amount | Similarity reason is displayed |
| Rejection reason | Reject without a comment, then with an 8+ character reason | Missing reason blocked; valid rejection recorded |
| Flagged approval | Approve flagged claim without/with documented reason | Undocumented exception blocked; manual decision allowed |
| Payment repetition | Try paying an already-paid claim or reusing a reference | Identical retries create no extra payment; conflicting payments/reused references are rejected |
| Admin limits | Set Food to ₹700; submit ₹900 | New server check uses the updated policy |
| Role escalation | Register with modified role metadata | Database creates employee only |
| Manager isolation | Create another manager/employee assignment | Managers see only their assigned requests |
| Private receipts | Request Storage path without authentication | No public access; signed URLs expire after 120 seconds |
| Admin protection | Employee opens admin page/calls admin RPC | UI redirects; backend rejects privileged call |
| File spoofing | Rename text/SVG to .png | Server signature validation rejects it |
| Reports | Filter dates/category; sort and paginate; export | Report reflects actual authorized database data |
| UI | Resize, open mobile navigation, toggle dark theme | Responsive controls; theme preference persists |

## Faculty explanation

“ExpenseFlow digitizes employee expense submission, policy verification, manager approval and reimbursement tracking. Employees upload private receipts, and server-side rules identify policy issues and potential duplicates. Assigned managers record their decisions. Finance records simulated reimbursements, and employees track the status. Supabase enforces role permissions and workflow transitions, with notifications and audit logs.”

OCR is a convenience, not authenticity verification. One Supabase project represents one organization. Payments are simulated. Google login requires correcting the configured OAuth client. Core login, upload and reimbursement API flows passed live tests on 11 October 2026; rehearse the browser interactions before presenting.

## Purchase evidence and bank-details workflow

Follow `BANK-TICKETS.md` for the updated live demonstration. After manager approval, sign back in as the employee and complete the bank-details ticket before finance starts processing. Use fictitious account details from that guide.
