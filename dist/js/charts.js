import { INR, categories, sum } from './utils.js';
import { expenseGroups } from './expense-state.js';
import { spendingSeries } from './report-data.js';
const palette=['#7b72d8','#7ebda8','#d6ae6b','#90acd0','#c393a7','#aaaed4','#c2d5cd'];
const instances=[];
export function destroyCharts() {while(instances.length)instances.pop().destroy();}
function chartNote(canvas,message) {canvas.hidden=true;let note=canvas.parentElement.querySelector('.chart-empty');if(!note){note=document.createElement('p');note.className='muted-note chart-empty';note.setAttribute('role','status');canvas.parentElement.append(note);}note.textContent=message;}
function chart(id,type,data,options={}) {const canvas=document.getElementById(id);if(!canvas)return;if(!window.Chart){chartNote(canvas,'Chart.js could not load. Expense totals remain available in the tables.');return;}canvas.hidden=false;canvas.parentElement.querySelector('.chart-empty')?.remove();const instance=new Chart(canvas,{type,data,options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{position:'bottom',labels:{color:'#91a0ad',font:{size:12},boxWidth:10}},tooltip:{callbacks:{label:c=>`${c.dataset.label||c.label}: ${INR(c.raw)}`}}},...options}});instances.push(instance);applyChartTheme(instance);}
export function renderSpendingCharts(rows,range={}) {
  destroyCharts();const series=spendingSeries(rows,range);
  const {submitted}=expenseGroups(rows);
  chart('monthly-chart','bar',{labels:series.labels,datasets:[{label:'Claimed amount',data:series.claimed,backgroundColor:'#8f84d5',borderRadius:5},{label:'Reimbursed portion',data:series.reimbursed,backgroundColor:'#a7d7c3',borderRadius:5}]},{scales:{x:{grid:{display:false},ticks:{color:'#9ba7b5',font:{size:11}}},y:{beginAtZero:true,grid:{color:'#a0aabd15'},ticks:{color:'#9ba7b5',font:{size:11},callback:v=>'₹'+v.toLocaleString('en-IN')}}}});
  const totals=categories.map(c=>sum(submitted.filter(r=>r.category===c)));if(totals.every(n=>n===0)){const el=document.getElementById('category-chart');if(el)chartNote(el,'No submitted expenses in this selection. Change the filters or submit a claim.');}else chart('category-chart','doughnut',{labels:categories,datasets:[{label:'Spending',data:totals,backgroundColor:palette,borderWidth:0}]},{cutout:'72%'});
}
export function renderDepartmentChart(rows) {
  const submitted=expenseGroups(rows).submitted,names=[...new Set(submitted.map(r=>r.department))];chart('department-chart','bar',{labels:names,datasets:[{label:'Department expenses',data:names.map(d=>sum(submitted.filter(r=>r.department===d))),backgroundColor:'#a7b0dc',borderRadius:5}]},{indexAxis:'y',scales:{x:{beginAtZero:true,grid:{color:'#a0aabd15'},ticks:{color:'#9ba7b5'}},y:{grid:{display:false},ticks:{color:'#9ba7b5'}}}});
}

export function chartColors(dark) {return dark?{text:'#bec8da',grid:'#354158',surface:'#202a3b',ink:'#edf2ff'}:{text:'#59687d',grid:'#e8ecf2',surface:'#ffffff',ink:'#202c3b'};}
function applyChartTheme(instance) {
 const c=chartColors(document.documentElement.dataset.theme==='dark');
 instance.options.color=c.text;
 if(instance.options.plugins.legend)instance.options.plugins.legend.labels.color=c.text;
 Object.assign(instance.options.plugins.tooltip,{backgroundColor:c.surface,titleColor:c.ink,bodyColor:c.ink,borderColor:c.grid,borderWidth:1});
 for(const scale of Object.values(instance.options.scales||{})){if(scale.ticks)scale.ticks.color=c.text;if(scale.grid)scale.grid.color=c.grid;if(scale.border)scale.border.color=c.grid;}
 instance.update('none');
}
if(typeof document!=='undefined')document.addEventListener('expenseflow:theme',()=>instances.forEach(applyChartTheme));
