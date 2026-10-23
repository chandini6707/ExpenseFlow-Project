import { safePublicConfig, resolvePublicConfig } from './utils.js';
import { validateExpenseSnapshot } from './expense-state.js';
let client=null;
export function getConfig() {try{return resolvePublicConfig(window.EXPENSEFLOW_CONFIG,JSON.parse(localStorage.getItem('expenseflow-public-config')||'{}'));}catch{return window.EXPENSEFLOW_CONFIG||{};}}
export function configured() {return safePublicConfig(getConfig());}
export function db() {
  if(client)return client;if(!configured())throw new Error('Connect your Supabase project to continue.');
  if(!window.supabase)throw new Error('Supabase library did not load. Check your internet connection and reload.');
  const c=getConfig();client=window.supabase.createClient(c.supabaseUrl,c.supabaseKey,{auth:{flowType:'pkce',persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});return client;
}
function unwrap(result) {if(result.error)throw result.error;return result.data;}
export async function session() {return unwrap(await db().auth.getSession()).session;}
export async function currentProfile(id) {
  const profile=unwrap(await db().from('profiles').select('*').eq('id',id).single());
  if(profile.avatar_path){const result=await db().storage.from('profile-avatars').createSignedUrl(profile.avatar_path,3600);profile.avatar_url=result.error?null:result.data.signedUrl;profile.avatar_load_failed=!!result.error;}
  return profile;
}
export async function listProfiles() {return rpc('profile_directory',{});}
export async function listPolicies() {return unwrap(await db().from('expense_policies').select('*').order('category'));}
export async function allRows(table,queryFactory=x=>x) {const all=[];let start=0;while(true){const rows=unwrap(await queryFactory(db().from(table).select('*')).range(start,start+499));all.push(...rows);if(rows.length<500)return all;start+=500;}}
export async function expenses() {
  return validateExpenseSnapshot(await rpc('expense_workspace',{}));
}
export async function expenseDetails(id,{optional=false}={}) {
  const row=validateExpenseSnapshot(await rpc('expense_workspace',{p_id:id}))[0];
  if(!row&&!optional)throw new Error('This expense was not found or you do not have access.');
  return row||null;
}
export async function receiptURL(path) {return unwrap(await db().storage.from('receipts').createSignedUrl(path,120)).signedUrl;}
export async function rpc(name,payload) {return unwrap(await db().rpc(name,payload));}
export async function saveExpense(payload,file,action,id,paymentProof=null) {
  const s=await session();if(!s)throw new Error('Sign in again to save your expense.');const cfg=getConfig();const form=new FormData();form.set('payload',JSON.stringify(payload));form.set('action',action);form.set('expense_id',id);if(file)form.set('receipt',file);if(paymentProof)form.set('payment_proof',paymentProof);
  const response=await fetch(cfg.supabaseUrl.replace(/\/$/,'')+'/functions/v1/save-expense',{method:'POST',headers:{apikey:cfg.supabaseKey,Authorization:'Bearer '+s.access_token},body:form});
  let result;try{result=await response.json();}catch{throw new Error('The save-expense function returned an invalid response. Check that it is deployed.');}
  if(!response.ok||result.error)throw new Error(result.error||'Expense could not be saved.');return result.expense_id;
}
export async function notifications(userID) {return allRows('notifications',q=>q.eq('user_id',userID).order('created_at',{ascending:false}).order('id'));}
export async function audits() {return allRows('audit_logs',q=>q.order('created_at',{ascending:false}).order('id'));}
