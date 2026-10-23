import { $, i, icons, busy, toast, empty } from './ui.js';
import { notifications, rpc, db, currentProfile, listProfiles } from './api.js';
import { ticketRows, ticketNotice } from './tickets.js';
import { signOut } from './session.js';
import { roleNames } from './access.js';
import { escapeHTML as h, timeLabel, initials } from './utils.js';
export async function notificationPage(profile) {
  const [rows,tickets]=await Promise.all([notifications(profile.id),profile.role==='employee'?ticketRows():Promise.resolve([])]);
  $('#page-content').innerHTML=`${ticketNotice(tickets)}<section class="panel"><div class="panel-header"><div><h2>Your notifications</h2><p>${rows.filter(n=>!n.is_read).length} unread updates</p></div><button class="button secondary" id="mark-all-read">${i('check-check')}Mark all read</button></div><div class="notifications-list">${rows.map(n=>`<article class="notification-card ${n.is_read?'':'unread'}"><span class="activity-dot">${i('bell')}</span><div><p>${h(n.message)}</p><small>${timeLabel(n.created_at)}</small>${n.expense_id?`<a class="text-button" href="expense-details.html?id=${encodeURIComponent(n.expense_id)}">View claim ${i('arrow-right')}</a>`:''}</div>${!n.is_read?`<button class="button secondary read-notification" data-id="${n.id}">Mark read</button>`:''}</article>`).join('')||empty('No notifications yet','Status updates will appear here when you submit or review a claim.')}</div></section>`;
  $('#mark-all-read').disabled=!rows.some(n=>!n.is_read);$('#mark-all-read').onclick=e=>busy(e.currentTarget,async()=>{await rpc('mark_notifications_read',{});await notificationPage(profile);document.dispatchEvent(new Event('refresh-notifications'));toast('Notifications marked as read.');});document.querySelectorAll('.read-notification').forEach(b=>b.onclick=e=>busy(e.currentTarget,async()=>{await rpc('mark_notifications_read',{p_id:b.dataset.id});await notificationPage(profile);document.dispatchEvent(new Event('refresh-notifications'));}));icons();
}
export function roleRequestNotice(profile) {
  if(profile.role_request_status==='pending')return `<div class="notice role-request-banner">${i('shield-check')}<div><strong>${h(roleNames[profile.requested_role])} access requested</strong><br>Your administrator must authorize this role. Your current access remains ${h(roleNames[profile.role])}.</div></div>`;
  if(profile.role_request_status==='rejected')return `<div class="notice role-request-banner">${i('info')}<div><strong>Role request declined</strong><br>${h(profile.role_review_comment||'Contact your administrator for more information.')}</div></div>`;
  return '';
}
function profileField(id,label,value='',extra='') {return `<div class="field"><label for="${id}">${label}</label><input id="${id}" value="${h(value||'')}" ${extra}></div>`;}
export async function profilePage(profile,user) {
  const directory=await listProfiles();
  const manager=directory.find(p=>p.id===profile.manager_id);
  const team=directory.filter(p=>p.manager_id===profile.id);
  const role=profile.role;
  let file=null,removePicture=false,previewURL=null,selectionVersion=0,decoding=false;
  const currentPicture=profile.avatar_url;
  $('#page-content').innerHTML=`<div class="profile-layout"><section class="panel profile-summary"><div class="large-avatar" id="profile-summary-avatar"></div><h2 id="profile-display-name">${h(profile.full_name)}</h2><p>${h(user.email)}</p><span class="category-pill">${h(roleNames[role])}</span><small>${h(profile.department)}</small><p class="private-profile-note">Contact details and your uploaded photo are private to your account.</p><button type="button" class="button secondary" id="profile-signout">${i('log-out')}Sign out</button></section><section class="panel"><div class="panel-header"><div><h2>Profile settings</h2><p>Your details, saved securely to your company account</p></div></div><form id="profile-form"><div class="avatar-editor"><div class="avatar-preview" id="avatar-preview" aria-label="Profile picture preview"></div><div class="avatar-editor-controls"><div class="avatar-actions"><label class="button secondary avatar-upload">${i('image-plus')}Upload photo<input type="file" id="avatar-file" accept="image/jpeg,image/png" aria-label="Upload profile picture"></label><button type="button" class="button secondary" id="avatar-remove">${i('trash-2')}Remove</button></div><small>JPG or PNG, up to 2 MB. Changes apply when you save.</small><small id="avatar-message" role="status">${profile.avatar_load_failed?'Your picture could not load. Refresh or upload it again.':''}</small></div></div><div class="modal-body form-grid">${profileField('profile-name-input','Full name',profile.full_name,'required maxlength="100" autocomplete="name"')}${profileField('profile-email','Email address',user.email,'readonly type="email" autocomplete="email"')}${profileField('profile-phone','Phone number',profile.phone,'type="tel" maxlength="30" minlength="7" autocomplete="tel"')}${profileField('profile-department',role==='finance'?'Finance department':'Department',profile.department,'required maxlength="100" autocomplete="organization"')}${profileField('profile-job-title','Job title / designation',profile.job_title,'maxlength="100" autocomplete="organization-title"')}${role==='employee'?`${profileField('profile-id','Employee ID',profile.employee_code,'readonly')}${profileField('profile-manager','Reporting manager',manager?.full_name||'Not assigned — contact an administrator','readonly')}${profileField('profile-cost-centre','Cost centre',profile.cost_centre,'maxlength="80"')}`:''}${role==='manager'?`${profileField('profile-managed-team','Department / team managed',profile.managed_team,'maxlength="120"')}<div class="field full"><label>Assigned team (${team.length})</label>${team.length?`<ul class="profile-team">${team.map(p=>`<li>${h(p.full_name)} · ${h(p.employee_code)} · ${h(p.department)}</li>`).join('')}</ul>`:'<p class="muted-note">No employees assigned yet. An administrator manages team assignments.</p>'}</div>`:''}${role==='finance'?`<div class="field full"><label for="profile-finance-responsibilities">Finance approval responsibilities</label><textarea id="profile-finance-responsibilities" rows="3" maxlength="500">${h(profile.finance_responsibilities)}</textarea><small>A description of your responsibilities; this does not grant additional permissions.</small></div>`:''}<div class="field full"><small>Email is managed by your sign-in provider. Roles, employee IDs and reporting-manager assignments are controlled by administrators.</small></div></div><div class="form-feedback profile-feedback" id="profile-message" role="status" hidden></div><div class="modal-footer"><button class="button primary" type="submit">${i('save')}Save changes</button></div></form></section></div>`;
  const drawPicture=(url)=>{
    for(const selector of ['#avatar-preview','#profile-summary-avatar']){
      renderProfilePicture($(selector),url,profile.full_name,selector==='#avatar-preview'?86:75);
    }
    $('#avatar-remove').disabled=!url&&!profile.avatar_path&&!profile.avatar_url;
  };
  drawPicture(currentPicture);
  $('#profile-signout').onclick=e=>busy(e.currentTarget,signOut);
  $('#avatar-file').onchange=async e=>{
    const selected=e.target.files[0];if(!selected)return;
    const version=++selectionVersion;const save=$('#profile-form button[type="submit"]');
    let candidate=null;decoding=true;save.disabled=true;$('#avatar-remove').disabled=false;$('#avatar-message').textContent='Checking image…';
    try{
      validateProfilePhoto(selected);
      candidate=URL.createObjectURL(selected);const img=new Image();img.src=candidate;
      try{await img.decode();if(img.naturalWidth>12000||img.naturalHeight>12000)throw new Error();}catch{throw new Error('This image could not be opened. Choose a valid JPG or PNG picture.');}
      if(version!==selectionVersion||!$('#avatar-preview')?.isConnected)return;
      if(previewURL)URL.revokeObjectURL(previewURL);previewURL=candidate;candidate=null;file=selected;removePicture=false;drawPicture(previewURL);$('#avatar-message').textContent=selected.name+' · Ready to save';$('#profile-form').dataset.dirty='true';
    }catch(error){if(version===selectionVersion){toast(error.message,'error');$('#avatar-message').textContent=error.message;e.target.value='';drawPicture(removePicture?null:previewURL||currentPicture);$('#avatar-remove').disabled=removePicture||!(previewURL||currentPicture||profile.avatar_path);}}
    finally{if(candidate)URL.revokeObjectURL(candidate);if(version===selectionVersion){decoding=false;save.disabled=false;}}
  };
  $('#avatar-remove').onclick=()=>{selectionVersion++;decoding=false;$('#profile-form button[type="submit"]').disabled=false;if(previewURL)URL.revokeObjectURL(previewURL);previewURL=null;file=null;removePicture=true;$('#avatar-file').value='';drawPicture(null);$('#avatar-remove').disabled=true;$('#avatar-message').textContent='Picture will be removed when you save.';$('#profile-form').dataset.dirty='true';};
  $('#profile-form').onsubmit=e=>{e.preventDefault();if(decoding){toast('Wait for the image check to finish.','error');return;}busy(e.submitter,async()=>{
    const feedback=$('#profile-message');feedback.hidden=true;
    const fields={full_name:$('#profile-name-input').value.trim(),department:$('#profile-department').value.trim(),phone:$('#profile-phone').value.trim(),job_title:$('#profile-job-title').value.trim()};
    if(role==='employee')fields.cost_centre=$('#profile-cost-centre').value.trim();
    if(role==='manager')fields.managed_team=$('#profile-managed-team').value.trim();
    if(role==='finance')fields.finance_responsibilities=$('#profile-finance-responsibilities').value.trim();
    let uploaded=null,saved=false;
    const controls=[...$('#profile-form').querySelectorAll('input,textarea,button')].filter(el=>el!==e.submitter).map(el=>({el,disabled:el.disabled}));controls.forEach(({el})=>el.disabled=true);
    try{
      if(file){uploaded=`${user.id}/${crypto.randomUUID()}.${file.type==='image/png'?'png':'jpg'}`;const result=await db().storage.from('profile-avatars').upload(uploaded,file,{contentType:file.type,upsert:false,cacheControl:'3600'});if(result.error)throw new Error('Picture upload failed: '+result.error.message);fields.avatar_path=uploaded;}
      else if(removePicture)fields.avatar_path=null;
      await rpc('save_my_profile',{p_fields:fields});saved=true;$('#profile-form').dataset.dirty='false';
      let cleanupFailed=false;
      if(profile.avatar_path&&(file||removePicture)){const result=await db().storage.from('profile-avatars').remove([profile.avatar_path]);cleanupFailed=!!result.error;}
      const latest=await currentProfile(user.id);if(previewURL)URL.revokeObjectURL(previewURL);
      document.dispatchEvent(new CustomEvent('expenseflow:profile-updated',{detail:latest}));
      await profilePage(latest,user);toast(cleanupFailed?'Profile saved. The previous private image could not be deleted.':'Your profile has been saved.');
    }catch(error){
      // On an uncertain network response, never delete an image that may have been saved.
      if(uploaded&&!saved){try{const actual=await currentProfile(user.id);if(actual.avatar_path!==uploaded)await db().storage.from('profile-avatars').remove([uploaded]);}catch{/* Leave private upload intact for safe retry. */}}
      feedback.hidden=false;feedback.classList.remove('success');feedback.setAttribute('role','alert');feedback.textContent=saved?'Your changes were saved, but the refreshed profile could not load. Refresh this page.':error.message||'Your profile could not be saved. Try again.';
    }finally{controls.forEach(({el,disabled})=>{if(el.isConnected)el.disabled=disabled;});}
  });};icons();
}

export function validateProfilePhoto(file) {
  if(!file||!['image/jpeg','image/png'].includes(file.type)||!Number.isFinite(file.size)||file.size<=0||file.size>2097152)throw new Error('Choose a JPG or PNG image up to 2 MB.');
}
export function renderProfilePicture(target,url,name,size) {
  target.replaceChildren();
  if(!url){target.textContent=initials(name);return;}
  const image=new Image(size,size);image.className='profile-photo';image.alt='Your profile picture';image.referrerPolicy='no-referrer';
  image.onerror=()=>{if(image.parentElement===target)target.textContent=initials(name);};
  target.append(image);image.src=url;
}
