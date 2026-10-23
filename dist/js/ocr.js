export function parseReceiptText(text) {
  const lines=text.split(/\r?\n/).map(s=>s.trim()).filter(Boolean);
  const merchant=lines.find(s=>/[a-z]{3}/i.test(s)&&!/(receipt|invoice|tax|gst|sample|demo|date|bill no)/i.test(s)&&s.length<120)||'';
  const totalLine=[...lines].reverse().find(s=>/\b(grand total|total paid|amount paid|net amount|total)\b/i.test(s));
  const amounts=totalLine?.match(/\d[\d,]*(?:\.\d{1,2})?/g)||[];const amount=amounts.length?Number(amounts[amounts.length-1].replace(/,/g,'')):null;
  const iso=text.match(/\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b/);const local=text.match(/\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b/);
  let date='';if(iso)date=`${iso[1]}-${iso[2].padStart(2,'0')}-${iso[3].padStart(2,'0')}`;else if(local)date=`${local[3]}-${local[2].padStart(2,'0')}-${local[1].padStart(2,'0')}`;
  if(date&&(!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date))date='';
  return {merchant,amount:Number.isFinite(amount)&&amount>0?amount:null,date};
}
let loader;
export async function extractReceipt(file,onProgress) {
  if(!file.type.startsWith('image/'))throw new Error('Image OCR is available for JPG and PNG. Enter PDF details manually.');
  if(!window.Tesseract){if(!loader)loader=new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';script.onload=resolve;script.onerror=()=>{loader=null;script.remove();reject(new Error('OCR could not load. Enter receipt details manually.'));};document.head.appendChild(script);});await loader;}
  let worker;try{worker=await window.Tesseract.createWorker('eng',1,{logger:m=>{if(m.status==='recognizing text')onProgress(Math.round(m.progress*100));}});const {data}=await worker.recognize(file);return {...parseReceiptText(data.text),text:data.text};}finally{await worker?.terminate();}
}
