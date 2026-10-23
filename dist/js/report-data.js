import { today, sum } from './utils.js';
import { expenseGroups } from './expense-state.js';

export function reportDateError(from='',to='') {
  for(const value of [from,to])if(value&&(!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value+'T12:00:00Z'))||new Date(value+'T12:00:00Z').toISOString().slice(0,10)!==value))return 'Choose valid report dates.';
  return from&&to&&from>to?'From date must be on or before To date.':'';
}

// Both series describe the same claims, grouped by expense date (not payment date).
export function spendingSeries(rows,{from='',to='',now=today()}={}) {
  const error=reportDateError(from,to);if(error)throw new Error(error);
  const end=to||now,ending=new Date(end+'T12:00:00Z');
  const first=new Date(ending);first.setUTCDate(1);first.setUTCMonth(first.getUTCMonth()-5);
  const start=from||first.toISOString().slice(0,10),starting=new Date(start+'T12:00:00Z');
  const monthCount=(ending.getUTCFullYear()-starting.getUTCFullYear())*12+ending.getUTCMonth()-starting.getUTCMonth()+1;
  const yearly=monthCount>12,periods=[];
  if(start<=end){
    if(yearly){for(let year=starting.getUTCFullYear();year<=ending.getUTCFullYear();year++)periods.push({key:String(year),name:String(year)});}
    else{for(let n=0;n<monthCount;n++){const d=new Date(starting);d.setUTCDate(1);d.setUTCMonth(starting.getUTCMonth()+n);periods.push({key:d.toISOString().slice(0,7),name:d.toLocaleDateString('en-IN',{month:'short',year:'2-digit',timeZone:'UTC'})});}}
  }
  const filtered=rows.filter(r=>r.expense_date>=start&&r.expense_date<=end),{submitted,paid}=expenseGroups(filtered);
  return {labels:periods.map(p=>p.name),claimed:periods.map(p=>sum(submitted.filter(r=>r.expense_date.startsWith(p.key)))),reimbursed:periods.map(p=>sum(paid.filter(r=>r.expense_date.startsWith(p.key)))),yearly};
}
