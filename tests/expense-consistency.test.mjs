import {test} from 'node:test';
import assert from 'node:assert/strict';
import {expenseGroups,managerClaims,financeClaims,expenseTickets,validateExpenseSnapshot,awaitingManagerAssignment} from '../dist/js/expense-state.js';
import {sum,filterExpenses,buildCSV} from '../dist/js/utils.js';

const rows=['draft','pending','flagged','approved','processing','paid','rejected'].map((status,n)=>({id:String(n),status,amount:'100.10',employee_id:'employee',assigned_manager_id:'manager',expense_date:'2026-10-14',category:'Travel',ticket:['approved','processing','paid'].includes(status)?{expense_id:String(n),status:status==='paid'?'closed':'submitted'}:null}));
test('All views agree on submitted, approved, awaiting-review and unpaid amounts',()=>{
 const g=expenseGroups(rows);
 assert.equal(g.submitted.length,6);assert.equal(sum(g.submitted),600.6);
 assert.equal(g.approved.length,3);assert.equal(sum(g.approved),300.3);
 assert.equal(g.pending.length,2);assert.equal(sum(g.outstanding),200.2);
 assert.equal(sum(g.paid),100.1);assert.equal(sum(g.rejected),100.1);
 assert.equal(sum([{amount:'0.10'},{amount:'0.20'}]),0.3);
 const filtered=filterExpenses(rows,{category:'Travel',from:'2026-10-14',to:'2026-10-14'});
 assert.equal(sum(expenseGroups(filtered).approved),sum(g.approved));
 assert.equal(buildCSV(['Amount'],g.submitted.map(r=>[r.amount])).split('\r\n').length,7);
});
test('Manager and finance queues exclude historical personal claims and dormant tickets',()=>{
 const own={...rows[1],id:'own',employee_id:'manager',ticket:{status:'submitted'}};
 const other={...rows[1],id:'other',assigned_manager_id:'someone-else'};
 assert.deepEqual(managerClaims([...rows,own,other],'manager'),rows);
 assert.equal(financeClaims([...rows,own]).length,3);
 assert.equal(expenseTickets([...rows,own]).length,3);
});
test('Empty database results remain empty; invalid or duplicate data is an error rather than zero totals',()=>{
 assert.deepEqual(validateExpenseSnapshot({expenses:[]}),[]);
 assert.throws(()=>validateExpenseSnapshot(null));
 assert.throws(()=>validateExpenseSnapshot({expenses:[rows[0],rows[0]]}));
 assert.throws(()=>validateExpenseSnapshot({expenses:[{...rows[0],status:'reimbursed'}]}));
 assert.throws(()=>validateExpenseSnapshot({expenses:[{...rows[0],amount:'bad'}]}));
 assert.equal(validateExpenseSnapshot({expenses:Array.from({length:1201},(_,n)=>({...rows[0],id:String(n)}))}).length,1201);
});
test('Unassigned submissions remain pending review and never appear in a manager queue',()=>{
 for(const status of ['pending','flagged']){
  const claim={...rows[0],status,assigned_manager_id:null};
  assert.equal(awaitingManagerAssignment(claim),true);
  assert.equal(managerClaims([claim],'manager').length,0);
  assert.equal(expenseGroups([claim]).pending.length,1);
  assert.equal(financeClaims([claim]).length,0);
  assert.equal(awaitingManagerAssignment({...claim,assigned_manager_id:'manager'}),false);
 }
 assert.equal(awaitingManagerAssignment({...rows[0],assigned_manager_id:null}),false);
});
