import { test } from 'node:test';
import assert from 'node:assert/strict';
import { homeFor, mayOpen, requestedRole } from '../dist/js/access.js';
import { isSessionKey } from '../dist/js/session.js';
import { chartColors } from '../dist/js/charts.js';
import { registerWithoutConfirmation } from '../dist/js/auth-flow.js';

test('Protected routes route only by an authorized role', () => {
  for (const role of ['employee','manager','finance','admin']) {
    assert.equal(mayOpen(homeFor(role).replace('.html',''),role),true);
    assert.equal(mayOpen('submit-expense',role),role==='employee');
    assert.equal(mayOpen('admin',role),role==='admin');
  }
  assert.equal(mayOpen('profile',null),false);
  assert.equal(homeFor('pending-manager'),'login.html');
});
test('Session cleanup preserves theme, connection settings and other apps', () => {
  const auth='sb-project-auth-token';
  for(const key of [auth,auth+'-code-verifier','expenseflow-demo-session','expenseflow-session','expenseflow-oauth-role','demoSession'])assert.equal(isSessionKey(key,auth),true);
  for(const key of ['expenseflow-theme','expenseflow-public-config','other-app-session','sb-other-auth-token'])assert.equal(isSessionKey(key,auth),false);
});
test('Registration sends requested role metadata without assigning a privileged role', async () => {
  let sent;
  const client={auth:{signUp:async payload=>{sent=payload;return {data:{session:{},user:{id:'test'}}};}}};
  const settings=async()=>({ok:true,json:async()=>({external:{email:true},mailer_autoconfirm:true})});
  for(const role of ['manager','finance','admin']) {
    await registerWithoutConfirmation(client,{supabaseUrl:'https://example.supabase.co',supabaseKey:'public'},{email:'test@example.com',password:'example-password',fullName:'Test',requestedRole:role,role:'admin'},settings);
    assert.equal(sent.options.data.requested_role,requestedRole(role));
    assert.equal('role' in sent.options.data,false);
  }
});
test('Chart text and tooltip colors remain readable in both themes', () => {
  const luminance=hex=>{const c=hex.match(/\w\w/g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return c[0]*.2126+c[1]*.7152+c[2]*.0722;};
  for(const dark of [true,false]){const c=chartColors(dark);for(const text of [c.text,c.ink]){const a=luminance(text),b=luminance(c.surface);assert.ok((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=4.5);}}
});
