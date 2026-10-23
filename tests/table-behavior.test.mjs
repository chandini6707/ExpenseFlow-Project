import {test} from 'node:test';
import assert from 'node:assert/strict';
import {expenseTable} from '../dist/js/ui.js';

// Small DOM adapter exercises the actual handlers without pretending to be browser QA.
function container(id){return {id,nodes:{},set innerHTML(value){this.html=value;this.nodes=Object.fromEntries([...value.matchAll(/data-table="([^"]+)"/g)].map(m=>[m[1],{value:'',disabled:false,textContent:'',innerHTML:''}]));},querySelector(selector){return this.nodes[selector.match(/"([^"]+)"/)[1]];}};}
test('Table filters/sorting persist across fresh snapshots, stay separate and export all filtered rows in display order',async()=>{
 const saved={window:global.window,document:global.document,location:global.location,create:URL.createObjectURL,revoke:URL.revokeObjectURL};let exported;
 global.window={};global.document={documentElement:{dataset:{theme:'light'}},querySelectorAll:()=>[],createElement:()=>({click(){}})};global.location={search:'?status=draft'};URL.createObjectURL=blob=>{exported=blob;return 'blob:test';};URL.revokeObjectURL=()=>{};
 try{
  const rows=Array.from({length:12},(_,n)=>({id:'claim-'+n,title:'Travel '+n,category:'Travel',status:'pending',amount:100+n,expense_date:'2026-10-01',created_at:'2026-10-01',merchant:'Vendor'}));
  const queue=container('manager-queue'),history=container('manager-history');
  expenseTable(queue,rows);expenseTable(history,[{...rows[0],title:'Hotel history',status:'paid',category:'Accommodation'}]);
  assert.equal(queue.html.includes('id="table-query"'),false);
  queue.nodes.query.value='Travel';queue.nodes.query.oninput({target:queue.nodes.query});queue.nodes.sort.value='amount-asc';queue.nodes.sort.onchange({target:queue.nodes.sort});queue.nodes.next.onclick();
  assert.match(queue.nodes.summary.textContent,/Page 2 of 2/);assert.equal(history.nodes.query.value,'');
  expenseTable(queue,[...rows,{...rows[0],id:'new',title:'Travel new',amount:999}]);
  assert.equal(queue.nodes.query.value,'Travel');assert.equal(queue.nodes.sort.value,'amount-asc');assert.match(queue.nodes.summary.textContent,/13 claims · Page 2 of 2/);
  queue.nodes.export.onclick();const csv=await exported.text();assert.equal(csv.split('\r\n').length,14);assert.ok(csv.indexOf('"claim-0"')<csv.indexOf('"claim-11"'));assert.ok(csv.indexOf('"claim-11"')<csv.indexOf('"new"'));
  queue.nodes.category.value='Food';queue.nodes.category.onchange({target:queue.nodes.category});assert.equal(queue.nodes.export.disabled,true);assert.match(queue.nodes.summary.textContent,/0 claims/);
  const own=container('expense-table');expenseTable(own,[...rows,{...rows[0],id:'draft-id',status:'draft'}]);assert.equal(own.nodes.status.value,'draft');assert.match(own.nodes.summary.textContent,/1 claims/);
 }finally{global.window=saved.window;global.document=saved.document;global.location=saved.location;URL.createObjectURL=saved.create;URL.revokeObjectURL=saved.revoke;}
});
