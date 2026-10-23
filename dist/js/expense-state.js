// One vocabulary for persisted PostgreSQL expense_status values, shared by every view.
export const statuses = Object.freeze({draft:'Draft',pending:'Pending Manager Approval',flagged:'Flagged for Review',approved:'Approved',rejected:'Rejected',processing:'Processing Reimbursement',paid:'Reimbursed'});
export const statusGroups = Object.freeze({
  submitted:['pending','flagged','approved','rejected','processing','paid'],
  pending:['pending','flagged'], approved:['approved','processing','paid'],
  rejected:['rejected'], outstanding:['approved','processing'], paid:['paid']
});
export function expenseGroups(rows) {
  return Object.fromEntries(Object.entries(statusGroups).map(([name,states])=>[name,rows.filter(r=>states.includes(r.status))]));
}
export function managerClaims(rows,userID) {return rows.filter(r=>r.assigned_manager_id===userID&&r.employee_id!==userID);}
export function financeClaims(rows) {return rows.filter(r=>statusGroups.approved.includes(r.status));}
export function expenseTickets(rows) {return financeClaims(rows).flatMap(r=>r.ticket?[r.ticket]:[]);}
export function awaitingManagerAssignment(row) {return statusGroups.pending.includes(row.status)&&!row.assigned_manager_id;}
export function validateExpenseSnapshot(data) {
  if(!data||!Array.isArray(data.expenses))throw new Error('Expense data could not be loaded. Please refresh.');
  const seen=new Set();
  for(const row of data.expenses){
    if(!row.id||seen.has(row.id)||!Object.hasOwn(statuses,row.status)||!Number.isFinite(Number(row.amount))||Number(row.amount)<=0)
      throw new Error('Expense data is inconsistent. Refresh or contact your administrator.');
    seen.add(row.id);
  }
  return data.expenses;
}
