import { test } from 'node:test';
import assert from 'node:assert/strict';
import { signOut, authenticatedUser } from '../dist/js/session.js';

test('Shared logout confirms unsaved changes, calls local Supabase signout and protects session entry', async () => {
  let dirty=true,consent=false,fail=false,calls=0,verified=0,redirect=null,cleared=false,local=true,remoteUser={id:'employee-id'};
  const authKey='sb-test-auth-token';
  const storage=()=>{const values={};Object.defineProperties(values,{getItem:{value:k=>values[k]??null},setItem:{value:(k,v)=>values[k]=v},removeItem:{value:k=>delete values[k]}});return values;};
  global.localStorage=storage();global.sessionStorage=storage();
  localStorage[authKey]='example-token';localStorage['expenseflow-theme']='dark';sessionStorage['expenseflow-demo-session']='demo';
  global.location={hostname:'example.test',pathname:'/profile.html',replace:path=>redirect=path};
  global.document={cookie:'expenseflow-demo-session=demo',querySelector:selector=>selector.startsWith('form[')?(dirty?{}:null):{replaceChildren:()=>cleared=true}};
  global.window={localStorage,sessionStorage,confirm:()=>consent,EXPENSEFLOW_CONFIG:{configVersion:2,supabaseUrl:'https://test.supabase.co',supabaseKey:'sb_publishable_example_public_key_only'},supabase:{createClient:()=>({auth:{
    signOut:async options=>{assert.equal(options.scope,'local');calls++;return {error:fail?new Error('Network failure'):null};},
    getSession:async()=>({data:{session:local?{user:{id:'cached-user'}}:null},error:null}),
    getUser:async()=>{verified++;return {data:{user:remoteUser},error:null};}
  }})}};
  assert.equal(await signOut(),false);assert.equal(calls,0);assert.equal(redirect,null);
  consent=true;fail=true;await assert.rejects(signOut(),/Could not sign out securely/);assert.equal(redirect,null);assert.equal(localStorage[authKey],'example-token');
  fail=false;assert.equal(await signOut(),true);assert.equal(redirect,'login.html');assert.equal(cleared,true);assert.equal(localStorage[authKey],undefined);assert.equal(sessionStorage['expenseflow-demo-session'],undefined);assert.equal(localStorage['expenseflow-theme'],'dark');
  local=false;assert.equal(await authenticatedUser(),null);assert.equal(verified,0);
  local=true;assert.deepEqual(await authenticatedUser(),remoteUser);assert.equal(verified,1);
  for(const key of ['window','document','location','localStorage','sessionStorage'])delete global[key];
});
