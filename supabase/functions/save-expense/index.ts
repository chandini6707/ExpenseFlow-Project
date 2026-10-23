import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { validatePayload, sniffMime, validUuid, MAX_FILE_BYTES } from './validation.mjs';

// Service credentials exist only in the Edge environment, never in the browser.
const url = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// These are public origins for this demo. A configured value replaces the defaults.
const demoOrigins = 'https://expenseflow-enterprise-demo.foggyflute64.chatgpt.site,http://localhost:5500,http://127.0.0.1:5500';
const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? demoOrigins).split(',').map(x=>x.trim()).filter(Boolean);
const admin = createClient(url, serviceKey, {auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(async req => {
  const origin=req.headers.get('origin') || '';
  const allowed=!origin || allowedOrigins.includes(origin);
  const headers:Record<string,string>={'Content-Type':'application/json','Vary':'Origin','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
  if(origin&&allowed)headers['Access-Control-Allow-Origin']=origin;
  const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
  if(!allowed)return reply({error:'This site origin is not permitted. Configure ALLOWED_ORIGINS.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return reply({error:'POST required.'},405);
  const token=req.headers.get('Authorization')?.match(/^Bearer (.+)$/i)?.[1];
  if(!token)return reply({error:'Sign in required.'},401);
  const {data:{user},error:authError}=await admin.auth.getUser(token);
  if(authError||!user)return reply({error:'Your session expired. Sign in again.'},401);
  const uploadedPaths:string[]=[];let databaseAttempted=false;
  try {
    if(Number(req.headers.get('content-length')||0)>MAX_FILE_BYTES*2+65536)return reply({error:'Request is too large.'},413);
    // Bound streamed bodies as well: Content-Length may be absent or untrusted.
    const reader=req.body?.getReader();if(!reader)throw new Error('Request body required.');
    const chunks:Uint8Array[]=[];let total=0;
    while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>MAX_FILE_BYTES*2+65536){await reader.cancel();return reply({error:'Request is too large.'},413);}chunks.push(value);}
    const body=new Uint8Array(total);let offset=0;for(const chunk of chunks){body.set(chunk,offset);offset+=chunk.length;}
    const form=await new Response(body,{headers:{'Content-Type':req.headers.get('Content-Type')||''}}).formData();
    const action=form.get('action');if(!['draft','submit'].includes(String(action)))throw new Error('Invalid expense action.');
    const payload=validatePayload(JSON.parse(String(form.get('payload')||'{}')),action==='submit');
    const suppliedId=form.get('expense_id');const id=suppliedId?String(suppliedId):crypto.randomUUID();
    if(!validUuid(id))throw new Error('Invalid expense identifier.');
    const {data:profile,error:profileError}=await admin.from('profiles').select('id,role').eq('id',user.id).single();
    if(profileError||profile?.role!=='employee')return reply({error:'Only employee accounts can create expenses.'},403);
    const {data:old,error:oldError}=await admin.from('expenses').select('*').eq('id',id).maybeSingle();
    if(oldError)throw new Error('Could not load this draft.');
    if(old&&old.employee_id!==user.id)return reply({error:'Only your own expenses can be saved.'},403);
    const retry=old&&old.status!=='draft';
    async function attachment(field:string,prefix:string) {
      const file=form.get(field);
      let path=old?.[prefix+'_path']||null,hash=old?.[prefix+'_hash']||null,name=old?.[prefix+'_name']||null,type=old?.[prefix+'_type']||null;
      const label=field==='receipt'?'Purchase proof':'Payment proof';
      if(file instanceof File&&file.size>0){
        if(file.size>MAX_FILE_BYTES)throw new Error(label+' must be smaller than 5 MB.');
        const bytes=new Uint8Array(await file.arrayBuffer()),mime=sniffMime(bytes);
        if(file.type&&file.type!==mime.type)throw new Error(label+' file type does not match its contents.');
        hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(b=>b.toString(16).padStart(2,'0')).join('');
        type=mime.type;name=file.name.slice(0,180);
        if(retry)return {path,hash,name,type}; // Compare verified content in SQL without another upload.
        path=`${user.id}/${id}/${crypto.randomUUID()}.${mime.ext}`;
        const {error}=await admin.storage.from('receipts').upload(path,bytes,{contentType:type,upsert:false});
        if(error)throw new Error(label+' upload failed. Try again.');
        uploadedPaths.push(path);
      }else if(path){
        const {data:blob,error}=await admin.storage.from('receipts').download(path);
        if(error||!blob)throw new Error('Existing '+label.toLowerCase()+' could not be read. Upload it again.');
        const bytes=new Uint8Array(await blob.arrayBuffer());
        if(bytes.length>MAX_FILE_BYTES)throw new Error(label+' must be smaller than 5 MB.');
        type=sniffMime(bytes).type;
        hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(b=>b.toString(16).padStart(2,'0')).join('');
      }
      return {path,hash,name,type};
    }
    const {path,hash,name,type}=await attachment('receipt','receipt');
    const proof=await attachment('payment_proof','payment_proof');
    // Never accept browser-supplied attachment metadata or a browser-calculated checksum.
    Object.assign(payload,{payment_proof_path:proof.path,payment_proof_hash:proof.hash,payment_proof_name:proof.name,payment_proof_type:proof.type});
    if(action==='submit'&&!path)throw new Error('Attach a receipt before submitting.');
    databaseAttempted=true;
    const {data,error}=await admin.rpc('save_expense_verified',{p_actor:user.id,p_id:id,p_payload:payload,p_submit:action==='submit',p_receipt_path:path,p_receipt_hash:hash,p_receipt_name:name,p_receipt_type:type});
    if(error){
      // A SQL error means rollback. A transport error may mean a committed write with a lost response.
      // Never delete evidence after an ambiguous result; retry with the same expense ID.
      if(/^(P0001|22...|23...)$/.test(error.code||'')&&uploadedPaths.length)await admin.storage.from('receipts').remove(uploadedPaths);
      return reply({error:error.message},400);
    }
    // Replaced private objects are retained: another in-flight draft save may still reference them.
    // They are inaccessible through receipt RLS once no expense references their path.
    return reply({expense_id:data});
  } catch(err) {
    if(!databaseAttempted&&uploadedPaths.length)await admin.storage.from('receipts').remove(uploadedPaths);
    return reply({error:err instanceof Error?err.message:'The expense could not be saved.'},400);
  }
});
