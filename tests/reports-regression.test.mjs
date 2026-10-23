import {test} from 'node:test';
import assert from 'node:assert/strict';
import {reportDateError,spendingSeries} from '../dist/js/report-data.js';
import {expenseCSV,csvCell,sum} from '../dist/js/utils.js';

const claim=(date,status,amount)=>({expense_date:date,status,amount});
test('Historical report ranges show their selected claims, not the current six months',()=>{
 const rows=[claim('2024-02-10','paid',10.1),claim('2024-02-11','approved',20.2),claim('2024-03-10','pending',8),claim('2024-02-10','draft',999),claim('2026-10-10','paid',900)];
 const report=spendingSeries(rows,{from:'2024-02-01',to:'2024-03-31',now:'2026-10-14'});
 assert.deepEqual(report.claimed,[30.3,8]);assert.deepEqual(report.reimbursed,[10.1,0]);assert.deepEqual(report.labels,['Feb 24','Mar 24']);
 const earlier=spendingSeries(rows,{to:'2024-03-31',now:'2026-10-14'});assert.equal(earlier.labels.length,6);assert.equal(earlier.claimed.reduce((a,b)=>a+b,0),38.3);
});
test('Default trends cross year boundaries and group reimbursed amounts by expense date',()=>{
 const result=spendingSeries([{...claim('2025-12-31','paid',123.45),reimbursements:[{payment_date:'2026-02-01'}]},claim('2025-07-01','pending',50)],{now:'2026-02-28'});
 assert.deepEqual(result.labels,['Sept 25','Oct 25','Nov 25','Dec 25','Jan 26','Feb 26']);assert.equal(result.reimbursed[3],123.45);assert.equal(result.reimbursed[5],0);
 assert.equal(result.claimed.reduce((a,b)=>a+b,0),123.45);
});
test('Long date ranges preserve totals and use annual buckets',()=>{
 const rows=[claim('2023-12-31','rejected',8.8),claim('2024-02-29','paid',10.1),claim('2025-01-01','processing',5.3)];
 const r=spendingSeries(rows,{from:'2023-01-01',to:'2025-12-31'});assert.equal(r.yearly,true);assert.deepEqual(r.labels,['2023','2024','2025']);assert.deepEqual(r.claimed,[8.8,10.1,5.3]);assert.deepEqual(r.reimbursed,[0,10.1,0]);
 assert.equal(sum(r.claimed.map(amount=>({amount}))),sum(rows));
});
test('Invalid and reversed report dates fail clearly; leap day and empty periods remain valid',()=>{
 assert.ok(reportDateError('2026-12-01','2026-01-01'));assert.ok(reportDateError('2026-02-30'));assert.ok(reportDateError('bad'));assert.equal(reportDateError('2024-02-29','2024-02-29'),'');
 assert.throws(()=>spendingSeries([],{from:'2026-12-01',to:'2026-01-01'}),/From date/);
 assert.deepEqual(spendingSeries([],{from:'2024-02-29',to:'2024-02-29'}).claimed,[0]);
});
test('CSV neutralizes whitespace-prefixed formulas while preserving quotes and multiline text',()=>{
 for(const s of ['=1+1','  =HYPERLINK("x")','\u0001@SUM(1)','\t=1','\r=1','\n=1',' -2+3','\u00a0+1'])assert.ok(csvCell(s).startsWith('"\''));
 assert.equal(csvCell('A, "B"\nC'),'"A, ""B""\nC"');assert.equal(csvCell('100.10'),'"100.10"');
});
test('Expense CSV carries real decisions/payment references and never bank secrets or receipt URLs',()=>{
 const csv=expenseCSV([{id:'expense-1',title:'Business lunch',status:'paid',amount:500,expense_date:'2026-10-01',payment_method:'Cash',approvals:[{decision:'approved',decision_date:'2026-10-02'}],reimbursements:[{status:'paid',transaction_reference:'DEMO-TEST-001',payment_date:'2026-10-03'}],receipt_path:'secret/receipt.png',ticket:{account_number:'123456789012',account_last4:'9012'}}]);
 assert.ok(csv.startsWith('\uFEFF'));assert.ok(csv.includes('"Reimbursed"'));assert.ok(csv.includes('"DEMO-TEST-001"'));assert.ok(csv.includes('"2026-10-03"'));assert.ok(csv.includes('"approved"'));
 assert.equal(csv.includes('123456789012'),false);assert.equal(csv.includes('secret/receipt.png'),false);assert.equal(csv.includes('9012'),false);
});
