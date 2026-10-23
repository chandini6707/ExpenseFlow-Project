import {test} from 'node:test';
import assert from 'node:assert/strict';
import {renderSpendingCharts,destroyCharts} from '../dist/js/charts.js';

test('Charts recover after an empty filter or failed Chart.js load without losing their canvas',()=>{
 const saved={document:global.document,window:global.window,Chart:global.Chart};const drawn=[];
 const canvas=()=>{const parent={note:null,querySelector(){return this.note;},append(note){this.note=note;note.remove=()=>{this.note=null;};}};return {hidden:false,parentElement:parent};};
 const nodes={'monthly-chart':canvas(),'category-chart':canvas()};
 class FakeChart{constructor(target,config){this.options=config.options;this.target=target;this.config=config;drawn.push(this);}update(){}destroy(){this.destroyed=true;}}
 global.document={getElementById:id=>nodes[id],documentElement:{dataset:{theme:'dark'}},createElement:()=>({setAttribute(){}})};global.window={Chart:FakeChart};global.Chart=FakeChart;
 try{
  renderSpendingCharts([],{from:'2024-02-01',to:'2024-02-29'});
  assert.equal(nodes['category-chart'].hidden,true);assert.match(nodes['category-chart'].parentElement.note.textContent,/No submitted expenses/);
  const row={amount:500,status:'paid',category:'Food',expense_date:'2024-02-10'};
  renderSpendingCharts([row],{from:'2024-02-01',to:'2024-02-29'});
  assert.equal(nodes['category-chart'].hidden,false);assert.equal(nodes['category-chart'].parentElement.note,null);assert.equal(drawn.at(-1).config.type,'doughnut');assert.equal(drawn.at(-1).config.data.datasets[0].data[2],500);
  global.window.Chart=null;renderSpendingCharts([row]);assert.equal(nodes['monthly-chart'].hidden,true);assert.match(nodes['monthly-chart'].parentElement.note.textContent,/could not load/);
  global.window.Chart=FakeChart;renderSpendingCharts([row]);assert.equal(nodes['monthly-chart'].hidden,false);assert.equal(nodes['monthly-chart'].parentElement.note,null);
 }finally{destroyCharts();global.document=saved.document;global.window=saved.window;global.Chart=saved.Chart;}
});
