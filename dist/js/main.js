import { $, i, icons, setupUIEvents, reportError, empty, toggleTheme, avatarHTML, busy, toast } from './ui.js';
import { db, configured, session, currentProfile, notifications, getConfig } from './api.js';
import { landing, authPage, homeFor } from './auth.js';
import { employeeDashboard, myExpenses, managerDashboard, financeDashboard } from './dashboard.js';
import { submitExpense, detailsPage } from './expenses.js';
import { analyticsPage } from './reports.js';
import { notificationPage, profilePage, roleRequestNotice } from './account.js';
import { adminPage } from './admin.js';
import { ticketsPage } from './tickets.js';
import { escapeHTML as h, exportCSV } from './utils.js';
import { expenses } from './api.js';
import { signOut, authenticatedUser, clearApplicationSession } from './session.js';
import { mayOpen, roleNames } from './access.js';

const route=document.body.dataset.page||'index';
setupUIEvents();
const authRoutes=['login','register','forgot-password','reset-password'];
const headings={
 'employee-dashboard':['YOUR EXPENSE WORKSPACE','Overview','A clear view of your expenses, from submission to reimbursement.'],
 'my-expenses':['EXPENSE WORKSPACE','Expenses','Search, review and track the claims you are authorized to access.'],
 'submit-expense':['EMPLOYEE WORKSPACE','Submit expense','Add your official expense and attach the receipt.'],
 'expense-details':['CLAIM WORKSPACE','Expense details','Every detail, verification result and recorded decision in one place.'],
 'manager-dashboard':['MANAGER WORKSPACE','Manager approvals','Review your assigned requests and document each decision.'],
 'finance-dashboard':['FINANCE WORKSPACE','Reimbursements','Track approved claims through processing and reimbursement.'],
 analytics:['ORGANIZATION INSIGHTS','Reports & analytics','Explore spending trends based on your authorized expense records.'],
 'reimbursement-tickets':['REIMBURSEMENT SUPPORT','Reimbursement tickets','Provide and track bank details for approved purchases.'],
 notifications:['WORKSPACE UPDATES','Notifications','Keep up with submissions, reviews and reimbursement updates.'],
 profile:['YOUR ACCOUNT','User profile','Manage your profile, photo and workspace details.'],
 admin:['ADMINISTRATION','Organization settings','Manage people, policies and the complete expense audit trail.']
};
let profile,user,channel,renderTimer;
function navLink(file,label,icon,count='') {return `<a class="nav-item ${route===file?'active':''}" href="${file}.html" ${route===file?'aria-current="page"':''}>${i(icon)}${label}${count?`<span class="nav-count" id="${count}">0</span>`:''}</a>`;}
function appShell() {
 const [eyebrow,title,description]=headings[route]||headings['my-expenses'];
 const overview=profile.role==='employee'?'employee-dashboard':profile.role==='manager'?'manager-dashboard':profile.role==='finance'?'finance-dashboard':'admin';
 $('#app').innerHTML=`<aside class="sidebar" id="sidebar"><a class="brand" href="${overview}.html"><span class="brand-mark">ef</span><span>Expense<span class="brand-light">Flow</span></span></a><div class="workspace"><span class="workspace-logo">N</span><div><strong>${h(getConfig().organization||'Northstar Technologies')}</strong><small>Enterprise workspace <span class="tiny-dot"></span></small></div></div><div class="nav-label">WORKSPACE</div><nav aria-label="Main navigation">${navLink(overview,profile.role==='employee'?'Overview':profile.role==='manager'?'Approval dashboard':profile.role==='finance'?'Finance dashboard':'Administration','layout-dashboard')}${navLink('my-expenses',profile.role==='employee'?'My expenses':'Expenses','receipt')}${profile.role==='employee'?navLink('submit-expense','Submit expense','circle-plus'):''}${['employee','finance','admin'].includes(profile.role)?navLink('reimbursement-tickets','Reimbursement tickets','landmark'):''}${navLink('analytics','Reports & analytics','chart-no-axes-combined')}${navLink('notifications','Notifications','bell','nav-notification-count')}${navLink('profile','User profile','user-round')}</nav><div class="sidebar-bottom"><div class="demo-card"><span class="demo-dot"></span><strong>Database-connected workspace</strong><p>Server-verified claims. Clear approvals. Traceable reimbursements.</p><a class="text-button" href="index.html">About ExpenseFlow ${i('arrow-up-right')}</a></div><button class="reset-button" id="logout-button">${i('log-out')}Sign out</button><div class="sidebar-footer">ExpenseFlow <span>v2.0</span></div></div></aside><div class="app-shell"><header class="topbar"><div class="breadcrumb"><button class="icon-button mobile-only" id="menu-button" aria-label="Toggle navigation" aria-expanded="false" aria-controls="sidebar">${i('menu')}</button><span class="breadcrumb-home">${i('house')}</span><span class="breadcrumb-divider">/</span><span>${title}</span></div><div class="top-actions"><span class="demo-label">COLLEGE DEMO</span><button class="icon-button" id="theme-button" aria-label="Toggle theme">${i('moon')}</button><a class="icon-button" href="notifications.html" aria-label="Open notifications">${i('bell')}<span id="top-notification-count" class="notification-count" hidden></span></a><div class="top-divider"></div><div class="profile-menu-wrap"><button class="profile-link profile-menu-toggle" id="profile-menu-toggle" type="button" aria-expanded="false" aria-controls="profile-menu" aria-label="Open account menu">${avatarHTML(profile)}<div class="profile-text"><strong>${h(profile.full_name)}</strong><span>${h(roleNames[profile.role])}</span></div>${i('chevron-down')}</button><div class="profile-menu" id="profile-menu" hidden><a href="profile.html">${i('user-round')}Edit profile</a><button type="button" id="menu-signout">${i('log-out')}Sign out</button></div></div></div></header><main><div class="page-heading"><div><div class="eyebrow">${eyebrow}</div><h1>${title}</h1><p>${description}</p></div><div class="heading-actions">${!['submit-expense','profile','notifications'].includes(route)?`<button class="button secondary" id="refresh-page">${i('refresh-cw')}Refresh</button>`:''}${profile.role==='employee'&&route!=='submit-expense'?`<a class="button primary" href="submit-expense.html">${i('plus')}Submit New Expense</a>`:''}</div></div><div class="workspace-status"><span><span class="footer-dot"></span>Supabase-connected · ${h(profile.department)}</span><span>Signed in as ${h(profile.role)} · Secure role permissions</span></div>${roleRequestNotice(profile)}<div id="page-content"><div class="loading-state"><span class="spinner"></span>Loading your workspace…</div></div><footer class="main-footer"><span>ExpenseFlow · Role-based access enforced by Supabase</span><span>Demo reimbursements · No real bank transfers</span></footer></main></div>`;
 $('#menu-button').onclick=()=>{const open=$('#sidebar').classList.toggle('open');$('#menu-button').setAttribute('aria-expanded',String(open));};document.addEventListener('keydown',e=>{if(e.key==='Escape'&&$('#sidebar').classList.contains('open')){$('#sidebar').classList.remove('open');$('#menu-button').setAttribute('aria-expanded','false');$('#menu-button').focus();}});document.addEventListener('click',e=>{if(!e.target.closest('#sidebar,#menu-button')){$('#sidebar').classList.remove('open');$('#menu-button').setAttribute('aria-expanded','false');}});$('#theme-button').onclick=toggleTheme;$('#logout-button').onclick=e=>busy(e.currentTarget,signOut);setupProfileMenu();if($('#refresh-page'))$('#refresh-page').onclick=e=>busy(e.currentTarget,renderRoute);icons();
}
async function updateNotificationCount() {try{const list=await notifications(profile.id),count=list.filter(n=>!n.is_read).length;const el=$('#top-notification-count');if(el){el.textContent=String(count);el.hidden=!count;}if($('#nav-notification-count'))$('#nav-notification-count').textContent=String(count);}catch(e){console.warn('Notification refresh failed');}}
async function refreshRoleAccess() {
 const latest=await currentProfile(user.id);
 if(latest.role!==profile.role||!mayOpen(route,latest.role)){
   location.replace(homeFor(latest.role));return false;
 }
 profile=latest;return true;
}
let renderRunning=null,renderAgain=false;
function renderRoute() {
 if(renderRunning){renderAgain=true;return renderRunning;}
 renderRunning=(async()=>{do{renderAgain=false;$('#page-content')?.setAttribute('aria-busy','true');await renderRouteOnce();}while(renderAgain);})().finally(()=>{renderRunning=null;$('#page-content')?.setAttribute('aria-busy','false');});
 return renderRunning;
}
function scheduleDataRefresh(){
 if(['employee-dashboard','my-expenses','manager-dashboard','finance-dashboard','analytics','reimbursement-tickets','notifications'].includes(route)){clearTimeout(renderTimer);renderTimer=setTimeout(renderRoute,350);}
}
async function renderRouteOnce() {
 const renderers={'employee-dashboard':()=>employeeDashboard(profile),'my-expenses':()=>myExpenses(profile),'submit-expense':()=>submitExpense(profile),'expense-details':()=>detailsPage(profile),'manager-dashboard':()=>managerDashboard(profile),'finance-dashboard':financeDashboard,analytics:analyticsPage,notifications:()=>notificationPage(profile),profile:()=>profilePage(profile,user),admin:adminPage,'reimbursement-tickets':()=>ticketsPage(profile)};
 try{if(!await refreshRoleAccess())return;await (renderers[route]||renderers['my-expenses'])();await updateNotificationCount();}catch(e){$('#page-content').innerHTML=empty('This page could not load','Check your project setup, account permissions and network connection.','<button class="button primary" id="retry-page">Try again</button>');$('#retry-page').onclick=renderRoute;icons();reportError(e);}
}
async function start() {
 if(route==='index'){landing();return;}
 if(authRoutes.includes(route)){await authPage(route);return;}
 if(!configured()){location.replace('login.html');return;}
 user=await authenticatedUser();if(!user){clearApplicationSession();location.replace('login.html');return;}profile=await currentProfile(user.id);
 if(!mayOpen(route,profile.role)){location.replace(homeFor(profile.role));return;}
 appShell();await renderRoute();
 window.addEventListener('focus',async()=>{try{const active=await authenticatedUser();if(!active){clearApplicationSession();$('#app').replaceChildren();location.replace('login.html');return;}if(await refreshRoleAccess())scheduleDataRefresh();}catch(error){reportError(error);}});
 document.addEventListener('refresh-notifications',updateNotificationCount);
 channel=db().channel('expenseflow-'+user.id).on('postgres_changes',{event:'*',schema:'public',table:'notifications',filter:'user_id=eq.'+user.id},()=>{updateNotificationCount();if(route==='notifications')scheduleDataRefresh();}).on('postgres_changes',{event:'*',schema:'public',table:'reimbursement_tickets'},scheduleDataRefresh).on('postgres_changes',{event:'*',schema:'public',table:'expenses'},scheduleDataRefresh).subscribe(status=>{if(status==='SUBSCRIBED')scheduleDataRefresh();});
 db().auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){clearApplicationSession();$('#app').replaceChildren();location.replace('login.html');}if(event==='PASSWORD_RECOVERY')location.replace('reset-password.html');});
 window.addEventListener('pagehide',e=>{if(e.persisted)$('#app').hidden=true;if(channel)db().removeChannel(channel);});
 window.addEventListener('pageshow',e=>{if(e.persisted){$('#app').hidden=true;location.reload();}});
 document.addEventListener('expenseflow:profile-updated',e=>{profile=e.detail;const button=$('#profile-menu-toggle');button.innerHTML=`${avatarHTML(profile)}<div class="profile-text"><strong>${h(profile.full_name)}</strong><span>${h(roleNames[profile.role])}</span></div>${i('chevron-down')}`;icons();});
}
start().catch(error=>{$('#app').innerHTML=`<div class="startup-error"><h1>Let’s finish your workspace setup.</h1><p>${h(error.message||'The application could not start.')}</p><a class="button primary" href="login.html">Return to sign in</a><a class="button secondary" href="index.html">Go to home</a></div>`;reportError(error);});

function setupProfileMenu(){
 const toggle=$('#profile-menu-toggle'),menu=$('#profile-menu');
 const setOpen=open=>{menu.hidden=!open;toggle.setAttribute('aria-expanded',String(open));if(open)menu.querySelector('a').focus();};
 toggle.onclick=()=>setOpen(menu.hidden);
 document.addEventListener('click',e=>{if(!e.target.closest('.profile-menu-wrap'))setOpen(false);});
 document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!menu.hidden){setOpen(false);toggle.focus();}});
 $('#menu-signout').onclick=e=>busy(e.currentTarget,signOut);
}
