import { escapeHTML as h, statuses, INR, dateLabel, categoryIcons, shortID, exportCSV, filterExpenses, sortExpenses, friendlyError, initials, categories } from './utils.js';
export const $=s=>document.querySelector(s);
export const i=name=>`<i data-lucide="${name}" aria-hidden="true"></i>`;
export function icons() {window.lucide?.createIcons();syncThemeButtons();}
let toastTimer,modalFocus;
export function toast(message,type='success') {clearTimeout(toastTimer);const el=$('#toast');el.textContent=message;el.className='toast '+type;el.hidden=false;toastTimer=setTimeout(()=>el.hidden=true,6500);}
export function reportError(error) {toast(friendlyError(error),'error');}
export async function busy(button,fn) {if(!button||button.dataset.busy==='true')return;const before=button.innerHTML;button.dataset.busy='true';button.disabled=true;button.innerHTML='<span class="spinner"></span> Please wait…';try{return await fn();}catch(e){reportError(e);}finally{delete button.dataset.busy;if(button.isConnected){button.disabled=false;button.innerHTML=before;icons();}}}
export function badge(status) {return `<span class="status ${status}">${statuses[status]||h(status)}</span>`;}
export function empty(title,body,action='') {return `<div class="empty-state">${i('receipt')}<strong>${h(title)}</strong><p>${h(body)}</p>${action}</div>`;}
export function modal(title,body,footer='') {
  modalFocus=document.activeElement;$('#modal').innerHTML=`<div class="modal-header"><div><h2 id="modal-title">${h(title)}</h2></div><button class="icon-button" data-modal-close aria-label="Close dialog">${i('x')}</button></div><div class="modal-body">${body}</div>${footer?`<div class="modal-footer">${footer}</div>`:''}`;$('#modal-backdrop').hidden=false;document.body.style.overflow='hidden';$('#modal').focus();$('#modal').querySelectorAll('[data-modal-close]').forEach(b=>b.onclick=closeModal);icons();
}
export function closeModal() {$('#modal-backdrop').hidden=true;document.body.style.overflow='';if(modalFocus?.isConnected)modalFocus.focus();}
export function setupUIEvents() {
  $('#modal-backdrop').onclick=e=>{if(e.target===$('#modal-backdrop'))closeModal();};
  document.addEventListener('keydown',e=>{if($('#modal-backdrop').hidden)return;if(e.key==='Escape')closeModal();if(e.key==='Tab'){const nodes=[...$('#modal').querySelectorAll('button:not(:disabled),input,select,textarea,a[href]')].filter(n=>n.getClientRects().length);const first=nodes[0],last=nodes[nodes.length-1];if(!first){e.preventDefault();return;}if(e.shiftKey&&(document.activeElement===first||document.activeElement===$('#modal'))){e.preventDefault();last.focus();}else if(!e.shiftKey&&(document.activeElement===last||document.activeElement===$('#modal'))){e.preventDefault();first.focus();}}});
  window.addEventListener('storage',e=>{if(e.key==='expenseflow-theme')applyTheme(e.newValue==='dark'?'dark':'light');});
  document.addEventListener('input',e=>{if(e.target.form)e.target.form.dataset.dirty='true';});
  document.addEventListener('change',e=>{if(e.target.form)e.target.form.dataset.dirty='true';});
}
export function syncThemeButtons() {
  const dark=document.documentElement.dataset.theme==='dark';
  document.querySelectorAll('#theme-button,#auth-theme,.theme-toggle').forEach(b=>{b.setAttribute('aria-label',dark?'Switch to light theme':'Switch to dark theme');b.setAttribute('aria-pressed',String(dark));b.title=dark?'Switch to light theme':'Switch to dark theme';});
}
function applyTheme(theme) {document.documentElement.dataset.theme=theme;syncThemeButtons();document.dispatchEvent(new CustomEvent('expenseflow:theme',{detail:{theme}}));}
export function toggleTheme() {const theme=document.documentElement.dataset.theme==='dark'?'light':'dark';applyTheme(theme);try{localStorage.setItem('expenseflow-theme',theme);}catch{/* In-memory theme still works. */}}
export function stat(title,value,foot,icon='wallet',color='lavender') {return `<article class="stat-card"><div class="stat-top">${h(title)}<span class="stat-icon ${color}">${i(icon)}</span></div><div class="stat-value">${value}</div><div class="stat-foot">${h(foot)}</div></article>`;}
export function tableHTML(rows,showEmployee=false) {
  if(!rows.length)return empty('No matching expenses','Your expenses will appear here. Try another filter or submit a new claim.');
  return `<div class="table-wrap"><table><thead><tr><th>EXPENSE DETAILS</th>${showEmployee?'<th>EMPLOYEE</th>':''}<th>CATEGORY</th><th>AMOUNT</th><th>DATE</th><th>STATUS</th><th>DETAILS</th></tr></thead><tbody>${rows.map(r=>`<tr><td><div class="expense-name"><span class="expense-symbol">${i(categoryIcons[r.category])}</span><div><strong>${h(r.title)}</strong><small>${shortID(r.id)} · ${h(r.merchant)}</small></div></div></td>${showEmployee?`<td>${h(r.employee_name)}</td>`:''}<td><span class="category-pill">${h(r.category)}</span></td><td class="amount">${INR(r.amount)}</td><td>${dateLabel(r.expense_date)}</td><td>${badge(r.status)}</td><td><a class="row-action" href="expense-details.html?id=${encodeURIComponent(r.id)}">View</a></td></tr>`).join('')}</tbody></table></div>`;
}
// UI preferences only; records always come from the latest authorized database snapshot.
const tableViews=new Map();
export function expenseTable(container,rows,{showEmployee=false,statusOptions=Object.keys(statuses)}={}) {
  const key=container.id,initialStatus=key==='expense-table'?new URLSearchParams(location.search).get('status')||'':'';
  const state=tableViews.get(key)||{query:'',status:statusOptions.includes(initialStatus)?initialStatus:'',category:'',sort:'created_at',page:1};
  if(!statusOptions.includes(state.status))state.status='';
  const pageSize=8;
  container.innerHTML=`<div class="table-tools controls-wrap"><label class="search-box">${i('search')}<span class="visually-hidden">Search expenses</span><input data-table="query" placeholder="Search expenses…" type="search"></label><label class="control-label">Status<select data-table="status"><option value="">All statuses</option>${statusOptions.map(s=>`<option value="${s}">${statuses[s]}</option>`).join('')}</select></label><label class="control-label">Category<select data-table="category"><option value="">All categories</option>${categories.map(c=>`<option>${c}</option>`).join('')}</select></label><label class="control-label">Sort by<select data-table="sort"><option value="created_at">Newest first</option><option value="amount-desc">Amount: high to low</option><option value="amount-asc">Amount: low to high</option><option value="title">Title: A to Z</option><option value="expense_date">Expense date</option></select></label><button data-table="export" class="button secondary">${i('download')}Export CSV</button></div><div data-table="rows"></div><div class="pagination"><span data-table="summary" aria-live="polite"></span><div><button class="button secondary" data-table="prev">Previous</button><button class="button secondary" data-table="next">Next</button></div></div>`;
  const control=name=>container.querySelector(`[data-table="${name}"]`);
  ['query','status','category','sort'].forEach(name=>control(name).value=state[name]);
  const visible=()=>{const [sort,direction]=state.sort.split('-');return sortExpenses(filterExpenses(rows,state),sort,direction||(sort==='title'?'asc':'desc'));};
  const draw=()=>{const found=visible(),totalPages=Math.max(1,Math.ceil(found.length/pageSize));state.page=Math.min(state.page,totalPages);control('rows').innerHTML=tableHTML(found.slice((state.page-1)*pageSize,state.page*pageSize),showEmployee);control('summary').textContent=`${found.length} claims · Page ${state.page} of ${totalPages}`;control('prev').disabled=state.page<=1;control('next').disabled=state.page>=totalPages;control('export').disabled=!found.length;tableViews.set(key,state);icons();};
  ['query','status','category','sort'].forEach(name=>{control(name)[name==='query'?'oninput':'onchange']=e=>{state[name]=e.target.value;state.page=1;draw();};});
  control('prev').onclick=()=>{state.page--;draw();};control('next').onclick=()=>{state.page++;draw();};control('export').onclick=()=>exportCSV(visible());draw();
}
export function avatarHTML(profile) {const url=profile.avatar_url||'';return /^https:\/\//.test(url)?`<img class="profile-avatar" src="${h(url)}" alt="" referrerpolicy="no-referrer">`:`<div class="profile-avatar">${h(initials(profile.full_name))}</div>`;}
