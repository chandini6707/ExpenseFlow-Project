import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validatePayload,sniffMime,validUuid,MAX_FILE_BYTES} from '../supabase/functions/save-expense/validation.mjs';
const good={title:'Bengaluru meeting',merchant:'IndiGo',category:'Travel',amount:'2000.00',expense_date:'2026-10-10',purpose:'Travel for official client meeting',payment_method:'UPI',transaction_date:'2026-10-10',purchase_reference:'DEMO-PURCHASE-001'};
test('Valid amounts and dates normalize on the server',()=>{assert.equal(validatePayload(good,true,'2026-10-10').amount,2000);assert.equal(validatePayload({...good,title:' Trip '},true,'2026-10-10').title,'Trip');});
test('Missing information, invalid input types and impossible dates are rejected',()=>{for(const changes of [{title:''},{merchant:' '},{category:'Forged'},{amount:0},{amount:-1},{amount:Infinity},{amount:'NaN'},{amount:200.001},{expense_date:'2026-10-11'},{expense_date:'2026-02-30'},{expense_date:'garbage'},{purpose:'short'},{description:{}},{title:'x'.repeat(121)}])assert.throws(()=>validatePayload({...good,...changes},true,'2026-10-10'));});
test('Drafts allow an incomplete purpose but keep valid core details',()=>{assert.doesNotThrow(()=>validatePayload({...good,purpose:''},false,'2026-10-10'));assert.throws(()=>validatePayload({...good,amount:0},false,'2026-10-10'));});
test('File types are checked from bytes rather than trusting the browser',()=>{assert.equal(sniffMime(new Uint8Array([137,80,78,71,13,10,26,10])).type,'image/png');assert.equal(sniffMime(new Uint8Array([255,216,255])).type,'image/jpeg');assert.equal(sniffMime(new TextEncoder().encode('%PDF-1.7')).type,'application/pdf');assert.throws(()=>sniffMime(new TextEncoder().encode('<svg onload="alert(1)">')));assert.throws(()=>sniffMime(new Uint8Array([])));assert.equal(MAX_FILE_BYTES,5242880);});
test('Malformed draft identifiers are rejected',()=>{assert.equal(validUuid('18fc7812-4fa7-4d58-a77f-edc4e70f5822'),true);assert.equal(validUuid('../../someone-else'),false);assert.equal(validUuid(''),false);});

test('Purchase transactions require a method, valid date and a non-cash reference',()=>{
 for(const changes of [{payment_method:''},{payment_method:'Forged'},{payment_method:{}},{transaction_date:''},{transaction_date:'2026-02-30'},{transaction_date:'2026-10-11'},{purchase_reference:''},{purchase_reference:{}},{purchase_reference:'x'.repeat(121)}])assert.throws(()=>validatePayload({...good,...changes},true,'2026-10-10'));
 assert.doesNotThrow(()=>validatePayload({...good,payment_method:'Cash',purchase_reference:''},true,'2026-10-10'));
 assert.doesNotThrow(()=>validatePayload({...good,payment_method:'',transaction_date:'',purchase_reference:''},false,'2026-10-10'));
 assert.equal(validatePayload({...good,purchase_reference:'  UPI-123  '},true,'2026-10-10').purchase_reference,'UPI-123');
});
