export const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const INR = value => '₹'+Number(value||0).toLocaleString('en-IN',{maximumFractionDigits:2});
// Database numeric(12,2) amounts are summed as integer paise, not floating point rupees.
export const sum = rows => rows.reduce((n,r)=>n+Math.round(Number(r.amount)*100),0)/100;
export const today = () => {const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};
export const dateLabel = value => value ? new Date(value.length===10?value+'T12:00:00':value).toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'}) : '—';
export const timeLabel = value => new Date(value).toLocaleString('en-IN',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});
export const initials = name => name.split(/\s+/).filter(Boolean).slice(0,2).map(s=>s[0]).join('').toUpperCase();
import { statuses } from './expense-state.js';
export { statuses };
export const categories = ['Travel','Accommodation','Food','Transportation','Office Supplies','Client Meetings','Other'];
export const categoryIcons = {Travel:'plane',Accommodation:'hotel',Food:'utensils',Transportation:'car','Office Supplies':'briefcase','Client Meetings':'users',Other:'receipt'};
export function csvCell(value) {let s=String(value??'');if(/^[\s\u0000-\u001f]*[=+\-@]|^[\t\r\n]/u.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';}
export function buildCSV(headers,rows) {return '\uFEFF'+[headers,...rows].map(row=>row.map(csvCell).join(',')).join('\r\n');}
export function expenseCSV(rows) {
  return buildCSV(['ID','Employee','Department','Title','Category','Amount INR','Expense date','Merchant','Status','Verification','Purchase payment method','Purchase reference','Approval decision','Decision date','Reimbursement status','Demo payment reference','Recorded payment date'],rows.map(r=>{
    const approval=r.approvals?.[0],payment=r.reimbursements?.[0];
    return [r.id,r.employee_name,r.department,r.title,r.category,r.amount,r.expense_date,r.merchant,statuses[r.status],r.verification_status,r.payment_method,r.purchase_reference,approval?.decision,approval?.decision_date,payment?.status,payment?.transaction_reference,payment?.payment_date];
  }));
}
export function exportCSV(rows,filename='expenseflow-report.csv') {
  const csv=expenseCSV(rows);
  const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8;'}));const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
export function filterExpenses(rows,{query='',status='',category='',from='',to=''}={}) {
  return rows.filter(r=>(!query||`${r.title} ${r.merchant} ${r.employee_name} ${r.id}`.toLowerCase().includes(query.toLowerCase()))&&(!status||r.status===status)&&(!category||r.category===category)&&(!from||r.expense_date>=from)&&(!to||r.expense_date<=to));
}
export function sortExpenses(rows,key='created_at',direction='desc') {
  const multiplier=direction==='asc'?1:-1;return [...rows].sort((a,b)=>multiplier*(key==='amount'?Number(a[key])-Number(b[key]):String(a[key]||'').localeCompare(String(b[key]||''))));
}
export function safePublicConfig(config) {
  if(!config||!/^https:\/\/[a-z0-9.-]+(?::\d+)?\/?$/i.test(config.supabaseUrl||''))return false;
  const key=config.supabaseKey||'';if(key.startsWith('sb_secret_'))return false;if(key.startsWith('sb_publishable_')&&key.length>25)return true;
  try {const payload=JSON.parse(atob(key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));return payload.role==='anon';}catch{return false;}
}
export function resolvePublicConfig(defaults={},saved={}) {
  // A newly deployed project must replace browser overrides from the old project.
  if(!saved||typeof saved!=='object'||saved.configVersion!==defaults.configVersion)return {...defaults};
  return {...defaults,...saved};
}
export function shortID(id) {return 'EXP-'+id.slice(0,8).toUpperCase();}
export function friendlyError(error) {
  const text=error?.message||String(error||'Something went wrong.');
  if(/Failed to fetch|NetworkError|Load failed/i.test(text))return 'Could not reach Supabase. Check your network and project configuration.';
  if(/Invalid login credentials/i.test(text))return 'The email or password is incorrect.';
  if(/Email not confirmed/i.test(text))return 'This existing account still needs administrator activation. Ask your workspace administrator to confirm the account in Supabase and turn off Confirm email for new registrations.';
  if(/duplicate key.*unique_payment_reference/i.test(text))return 'That payment reference is already used. Enter a unique demo reference.';
  if(/relation .* does not exist|Could not find the table/i.test(text))return 'The database is not initialized. Run the supplied SQL migration.';
  return text.slice(0,500);
}
