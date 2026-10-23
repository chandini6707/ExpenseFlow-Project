import { $, i, icons, busy, toast, empty } from './ui.js';
import { expenses, rpc } from './api.js';
import { escapeHTML as h, INR, shortID, timeLabel } from './utils.js';

export const ticketLabels = {awaiting_details:'Bank details required',submitted:'Details received',closed:'Completed'};
import { expenseTickets } from './expense-state.js';
export async function ticketRows() {return expenseTickets(await expenses());}
export function ticketNotice(tickets) {
  const pending=tickets.filter(t=>t.status==='awaiting_details');
  return pending.length?`<div class="notice ticket-notice">${i('landmark')}<div><strong>${pending.length} approved ${pending.length===1?'purchase needs':'purchases need'} bank details.</strong><p>Open your reimbursement ticket to provide the account holder name, account number and IFSC.</p><a class="text-button" href="reimbursement-tickets.html">Open reimbursement tickets ${i('arrow-right')}</a></div></div>`:'';
}
export async function ticketsPage(profile) {
  const claims=await expenses(),tickets=expenseTickets(claims);
  const byID=new Map(claims.map(e=>[e.id,e]));
  $('#page-content').innerHTML=`<section class="panel"><div class="panel-header"><div><h2>Reimbursement tickets</h2><p>A ticket is created when a manager approves a purchase.</p></div><span class="subtle-pill">${tickets.filter(t=>t.status==='awaiting_details').length} awaiting details</span></div><div class="ticket-list">${tickets.map(t=>{const e=byID.get(t.expense_id);return `<article class="ticket-card"><span class="stat-icon ${t.status==='awaiting_details'?'amber':'green'}">${i(t.status==='awaiting_details'?'landmark':'badge-check')}</span><div><span class="eyebrow">TICKET ${shortID(t.id)}</span><h3>${h(e?.title||'Approved expense')}</h3><p>${profile.role==='employee'?'':h(e?.employee_name||'Employee')+' · '}${e?INR(e.amount):''} · ${h(ticketLabels[t.status])}</p><small>Created ${timeLabel(t.created_at)}</small></div><a class="button ${t.status==='awaiting_details'&&profile.role==='employee'?'primary':'secondary'}" href="expense-details.html?id=${encodeURIComponent(t.expense_id)}#bank-ticket">${t.status==='awaiting_details'&&profile.role==='employee'?'Provide bank details':'View ticket'} ${i('arrow-right')}</a></article>`;}).join('')||empty('No reimbursement tickets yet','Once your manager approves an expense, its bank-details ticket will appear here.')}</div></section>`;
  icons();
}
export function ticketPanel(t,profile,e) {
  if(!t||!['employee','finance','admin'].includes(profile.role))return '';
  const owner=profile.id===e.employee_id;
  const canEdit=owner&&(e.status==='approved'||(e.status==='processing'&&t.status==='awaiting_details'));
  return `<section class="panel review-box bank-ticket" id="bank-ticket"><div class="ticket-title">${i('landmark')}<div><span class="eyebrow">TICKET ${shortID(t.id)}</span><h3>Reimbursement details</h3></div></div><span class="subtle-pill">${h(ticketLabels[t.status])}</span><p class="muted-note">${t.status==='awaiting_details'?(owner?'Your purchase is approved. Provide your bank details below so finance can continue.':'Waiting for the employee to provide bank details.'):t.status==='closed'?'This reimbursement ticket is complete.':'Bank details have been received. Finance can continue with reimbursement.'}</p>${t.account_last4?`<div class="bank-summary"><small>Account holder</small><strong>${h(t.account_holder)}</strong><small>Bank account</small><strong>${h(t.bank_name)} · •••• ${h(t.account_last4)}</strong><small>IFSC</small><strong>${h(t.ifsc)}</strong></div>`:''}${canEdit&&t.status==='submitted'?'<button class="button secondary" id="edit-bank-details">Update bank details</button>':''}${canEdit?`<form id="bank-details-form" autocomplete="off" ${t.status==='submitted'?'hidden':''}><div class="field"><label for="bank-holder">Account holder name *</label><input id="bank-holder" required minlength="2" maxlength="120" value="${h(t.account_holder||profile.full_name)}" autocomplete="off"></div><div class="field"><label for="bank-name">Bank name *</label><input id="bank-name" required minlength="2" maxlength="100" value="${h(t.bank_name||'')}" placeholder="Your bank name" autocomplete="off"></div><div class="field"><label for="bank-account">Bank account number *</label><input id="bank-account" type="password" inputmode="numeric" required pattern="[0-9]{6,18}" minlength="6" maxlength="18" autocomplete="new-password" placeholder="6–18 digits"><small>Enter the full account number, including leading zeros.</small></div><div class="field"><label for="bank-account-confirm">Confirm account number *</label><input id="bank-account-confirm" type="password" inputmode="numeric" required pattern="[0-9]{6,18}" minlength="6" maxlength="18" autocomplete="new-password"></div><div class="field"><label for="bank-ifsc">IFSC code *</label><input id="bank-ifsc" required pattern="[A-Z]{4}0[A-Z0-9]{6}" maxlength="11" value="${h(t.ifsc||'')}" placeholder="11-character IFSC" autocapitalize="characters" autocomplete="off"><small>Four letters, zero, then six letters or digits.</small></div><label class="bank-consent"><input id="bank-confirm" type="checkbox" required><span>I have checked these details and authorize finance to use them for this reimbursement.</span></label><div id="bank-feedback" class="form-feedback" hidden role="status"></div><button class="button primary detail-action" type="submit">${i('lock-keyhole')}Submit bank details</button><p class="muted-note">Only finance can reveal the saved account number. This college demo records reimbursement status; no money is transferred. Use sample bank details for demonstrations.</p></form>`:''}${profile.role==='finance'&&t.account_last4?'<button class="button secondary" id="reveal-bank-details">View full account details</button><div id="bank-private-details" hidden></div><p class="muted-note">Viewing full bank details is recorded in the audit trail.</p>':''}</section>`;
}
export function bindTicketPanel(t,profile,e,onSave) {
  if(!t)return;
  const form=$('#bank-details-form');
  if($('#edit-bank-details'))$('#edit-bank-details').onclick=()=>{form.hidden=false;$('#edit-bank-details').hidden=true;$('#bank-holder').focus();};
  if(form){
    $('#bank-ifsc').oninput=evt=>{evt.target.value=evt.target.value.toUpperCase().replace(/\s/g,'');};
    form.onsubmit=evt=>{evt.preventDefault();const account=$('#bank-account').value,confirm=$('#bank-account-confirm').value;
      const feedback=$('#bank-feedback');feedback.hidden=true;
      if(account!==confirm){feedback.textContent='The account numbers do not match. Please enter them again.';feedback.hidden=false;$('#bank-account-confirm').focus();return;}
      busy(evt.submitter,async()=>{await rpc('submit_bank_details',{p_expense_id:e.id,p_account_holder:$('#bank-holder').value.trim(),p_bank_name:$('#bank-name').value.trim(),p_account_number:account,p_account_number_confirm:confirm,p_ifsc:$('#bank-ifsc').value.trim().toUpperCase()});form.reset();form.dataset.dirty='false';await onSave();});
    };
  }
  const reveal=$('#reveal-bank-details');
  if(reveal)reveal.onclick=evt=>busy(evt.currentTarget,async()=>{
    const box=$('#bank-private-details');
    if(!box.hidden){box.replaceChildren();box.hidden=true;return;}
    const bank=await rpc('get_bank_details',{p_expense_id:e.id});
    const label=document.createElement('p');label.className='bank-account-reveal';label.textContent=bank.account_holder+' · '+bank.bank_name+'\nAccount: '+bank.account_number+'\nIFSC: '+bank.ifsc;
    box.replaceChildren(label);box.hidden=false;
    const hide=document.createElement('button');hide.type='button';hide.className='text-button';hide.textContent='Hide account details';hide.onclick=()=>{box.replaceChildren();box.hidden=true;};box.appendChild(hide);
  });
  window.addEventListener('pagehide',()=>{$('#bank-private-details')?.replaceChildren();form?.reset();},{once:true});
}
