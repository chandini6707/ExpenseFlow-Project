import {test} from 'node:test';
import assert from 'node:assert/strict';
import {escapeHTML,filterExpenses,sortExpenses,buildCSV,safePublicConfig,resolvePublicConfig} from '../dist/js/utils.js';
import {parseReceiptText} from '../dist/js/ocr.js';
test('User input is HTML escaped',()=>assert.equal(escapeHTML('<img src=x onerror="alert(1)">'), '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;'));
test('Search, category, status and date filters compose',()=>{const rows=[{title:'Bengaluru',merchant:'Hotel',employee_name:'Rithvik',id:'1',status:'pending',category:'Accommodation',expense_date:'2026-10-01',amount:1500},{title:'Lunch',merchant:'Cafe',employee_name:'Rithvik',id:'2',status:'paid',category:'Food',expense_date:'2026-09-01',amount:500}];assert.equal(filterExpenses(rows,{query:'beng',status:'pending',category:'Accommodation',from:'2026-10-01',to:'2026-10-10'}).length,1);assert.equal(filterExpenses(rows,{from:'2026-11-01'}).length,0);assert.equal(sortExpenses(rows,'amount','asc')[0].id,'2');assert.equal(rows[0].id,'1');});
test('CSV escapes quotes and neutralizes spreadsheet formulas',()=>{const csv=buildCSV(['Title'],[['=HYPERLINK("x")'],['Hello, "World"']]);assert.ok(csv.includes("\"'=HYPERLINK(\"\"x\"\")\""));assert.ok(csv.includes('"Hello, ""World"""'));});
test('Public configuration rejects service-role and secret keys',()=>{const make=role=>'e30.'+btoa(JSON.stringify({role}))+'.test';assert.equal(safePublicConfig({supabaseUrl:'https://project.supabase.co',supabaseKey:make('anon')}),true);assert.equal(safePublicConfig({supabaseUrl:'https://project.supabase.co',supabaseKey:make('service_role')}),false);assert.equal(safePublicConfig({supabaseUrl:'https://project.supabase.co',supabaseKey:'sb_secret_test'}),false);assert.equal(safePublicConfig({supabaseUrl:'javascript:alert(1)',supabaseKey:make('anon')}),false);});
test('OCR extracts supported totals and Indian dates with manual fallback',()=>{const parsed=parseReceiptText('INVOICE\nGreen Park Hotel\nDate: 10/10/2026\nGrand Total INR 1,500.00');assert.equal(parsed.merchant,'Green Park Hotel');assert.equal(parsed.amount,1500);assert.equal(parsed.date,'2026-10-10');assert.equal(parseReceiptText('No clear amount').amount,null);assert.equal(parseReceiptText('Date: 30/02/2026').date,'');});
test('A deployed Supabase project switch replaces stale browser settings',()=>{
 const defaults={supabaseUrl:'https://new.supabase.co',supabaseKey:'new-public-key',configVersion:2};
 assert.deepEqual(resolvePublicConfig(defaults,{supabaseUrl:'https://old.supabase.co',supabaseKey:'old-public-key'}),defaults);
 assert.deepEqual(resolvePublicConfig(defaults,{configVersion:1,supabaseUrl:'https://old.supabase.co'}),defaults);
 assert.deepEqual(resolvePublicConfig(defaults,null),defaults);
 const current={supabaseUrl:'https://current.supabase.co',supabaseKey:'current-public-key',configVersion:2};
 assert.deepEqual(resolvePublicConfig(defaults,current),current);
});
