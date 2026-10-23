import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {validatePayload,sniffMime,validUuid,MAX_FILE_BYTES} from '../supabase/functions/save-expense/validation.mjs';
import {busy} from '../dist/js/ui.js';

const actor='10000000-0000-4000-8000-000000000001',id='20000000-0000-4000-8000-000000000001';
const source=stripTypeScriptTypes(readFileSync(new URL('../supabase/functions/save-expense/index.ts',import.meta.url),'utf8').replace(/^import .*;\n/gm,''));
function handler({old=null,rpcError=null,throwRpc=false}={}) {
 const seen={uploads:[],removed:[],rpc:[]};let serve;
 const client={auth:{getUser:async()=>({data:{user:{id:actor}}})},from:table=>({select:()=>({eq:()=>({single:async()=>({data:{id:actor,role:'employee'}}),maybeSingle:async()=>({data:old})})})}),
  storage:{from:()=>({upload:async path=>{seen.uploads.push(path);return {};},remove:async paths=>{seen.removed.push(...paths);return {};}})},
  rpc:async(name,args)=>{seen.rpc.push(args);if(throwRpc)throw new Error('Network response lost');return {data:id,error:rpcError};}};
 new Function('createClient','validatePayload','sniffMime','validUuid','MAX_FILE_BYTES','Deno',source)(()=>client,validatePayload,sniffMime,validUuid,MAX_FILE_BYTES,{env:{get:()=>''},serve:fn=>serve=fn});
 return {serve,seen};
}
function request(auth=true) {
 const data=new FormData();data.set('expense_id',id);data.set('action','submit');
 data.set('payload',JSON.stringify({title:'Test',merchant:'Test vendor',category:'Travel',amount:0.1,expense_date:'2020-01-01',purpose:'Official test purpose',payment_method:'Cash',transaction_date:'2020-01-01'}));
 data.set('receipt',new File([new Uint8Array([137,80,78,71,13,10,26,10])],'test.png',{type:'image/png'}));
 return new Request('https://example.invalid/save',{method:'POST',headers:auth?{Authorization:'Bearer test-session'}:{},body:data});
}
test('Server submission retries verify content without uploading a second receipt',async()=>{
 const {serve,seen}=handler({old:{id,employee_id:actor,status:'pending',receipt_path:actor+'/'+id+'/saved.png'}});
 assert.equal((await serve(request())).status,200);assert.equal(seen.uploads.length,0);
 assert.equal(seen.rpc[0].p_id,id);assert.equal(seen.rpc[0].p_actor,actor);assert.match(seen.rpc[0].p_receipt_hash,/^[a-f0-9]{64}$/);
});
test('Ambiguous database responses never delete possibly committed receipt evidence',async()=>{
 for(const options of [{throwRpc:true},{rpcError:{message:'Network response lost',code:''}}]){
  const {serve,seen}=handler(options);assert.equal((await serve(request())).status,400);
  assert.equal(seen.uploads.length,1);assert.equal(seen.removed.length,0);
 }
 const {serve,seen}=handler({rpcError:{message:'Validation rejected',code:'P0001'}});
 assert.equal((await serve(request())).status,400);assert.equal(seen.removed.length,1);
});
test('Anonymous submissions do not reach the database or storage',async()=>{
 const {serve,seen}=handler();assert.equal((await serve(request(false))).status,401);
 assert.equal(seen.rpc.length,0);assert.equal(seen.uploads.length,0);
});
test('Repeat action clicks are ignored while the first operation is in flight',async()=>{
 const button={dataset:{},innerHTML:'Save',isConnected:false};let resolve,calls=0;
 const gate=new Promise(r=>resolve=r);
 const first=busy(button,async()=>{calls++;await gate;});await busy(button,async()=>calls++);
 assert.equal(calls,1);resolve();await first;assert.equal(button.dataset.busy,undefined);
});
