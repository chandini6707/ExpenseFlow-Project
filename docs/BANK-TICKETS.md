# Purchase evidence and reimbursement tickets

1. Sign in as an employee. In **Submit expense**, enter the purchase amount, merchant and business purpose.
2. Add the **payment method**, **payment date** and **transaction / UTR reference**. Cash payments do not need a transaction reference.
3. Upload **Proof of purchase** (receipt/invoice). Optionally attach **Payment proof**, such as a cropped UPI receipt or transaction screenshot. Each file accepts JPG, PNG or PDF up to 5 MB.
4. Submit. The manager can view both documents and the purchase transaction details, then approve or reject the claim.
5. Approval automatically opens a **Reimbursement ticket** and sends an **in-app notification** to the employee. No email is sent for this step.
6. The employee opens **Reimbursement tickets → Provide bank details**, or opens the notification's claim link. Enter account holder name, bank name, account number twice and IFSC. Confirm the details and submit.
7. Finance receives an in-app notification. Open the claim to see the masked account; use **View full account details** only when needed. This action is audited.
8. Finance starts processing and records a simulated reference/date. Bank details can no longer be changed. Marking the claim reimbursed closes its ticket. No money is transferred.

## College demonstration

Use the four real demo accounts in `DEMO-ACCOUNTS.txt` (included only in the private project ZIP). Keep this credential file outside the website and Git.

For bank form testing use clearly fictitious data: account holder **Demo Employee**, bank **Demo Bank**, account **000000123456**, IFSC **TEST0000001**. The IFSC is a format-valid test string, not a verified bank branch. Use sample details for the demonstration, not a real account.

The administrator account `25r21a0556@mlrit.ac.in` can manage people, managers and policies. New expense submissions use an employee-role account. Historical expenses remain visible after a role change, and an owner can still complete their existing bank-details ticket.

## Installation / upgrade

For a new project apply the initial schema followed by `20261011133337_purchase_proof_and_bank_tickets.sql`. For an already initialized project apply only that second migration, then redeploy `save-expense` and the `dist/` website together. The currently hosted demo already has this upgrade. Keep `expense_private` unexposed. Run `npm test`, `npm run check` and the rollback SQL regression suite to verify installation.
