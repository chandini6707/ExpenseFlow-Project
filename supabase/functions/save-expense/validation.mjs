export const MAX_FILE_BYTES = 5 * 1024 * 1024;
export function validatePayload(value, submit, today = new Date().toISOString().slice(0,10)) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid expense details.');
  const category = ['Travel','Accommodation','Food','Transportation','Office Supplies','Client Meetings','Other'];
  for (const [key,max] of [['title',120],['merchant',120]]) if (typeof value[key]!=='string'||!value[key].trim()||value[key].trim().length>max) throw new Error('Enter a valid title and merchant.');
  for (const [key,max] of [['purpose',1000],['description',2000],['invoice_number',80]]) if (value[key]!=null && (typeof value[key]!=='string'||value[key].length>max)) throw new Error('An expense field is too long or invalid.');
  if (!category.includes(value.category)) throw new Error('Choose an allowed expense category.');
  const amount=Number(value.amount);
  if(!Number.isFinite(amount)||amount<=0||amount>10000000||Math.abs(amount*100-Math.round(amount*100))>0.000001)throw new Error('Enter an amount greater than zero with up to two decimal places.');
  const date=value.expense_date;
  if(typeof date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date||date>today)throw new Error('Choose a valid date on or before today.');
  if(submit&&(!value.purpose||value.purpose.trim().length<8))throw new Error('Enter a business purpose of at least 8 characters.');
  const methods=['UPI','Debit Card','Credit Card','Bank Transfer','Cash','Other'];
  if(value.payment_method!=null&&typeof value.payment_method!=='string')throw new Error('Choose a valid payment method.');
  const method=value.payment_method?.trim()||null;
  if(method&&!methods.includes(method))throw new Error('Choose a valid payment method.');
  const transactionDate=value.transaction_date||null;
  if(transactionDate&&(typeof transactionDate!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(transactionDate)||!Number.isFinite(Date.parse(transactionDate))||new Date(transactionDate).toISOString().slice(0,10)!==transactionDate||transactionDate>today))throw new Error('Choose a valid purchase payment date on or before today.');
  if(value.purchase_reference!=null&&typeof value.purchase_reference!=='string')throw new Error('Enter a valid transaction reference.');
  const reference=value.purchase_reference?.trim()||'';
  if(reference.length>120)throw new Error('The transaction reference must be at most 120 characters.');
  if(submit&&(!method||!transactionDate||(method!=='Cash'&&reference.length<3)))throw new Error('Enter a payment method, payment date and a transaction reference for non-cash purchases.');
  return {...value,title:value.title.trim(),merchant:value.merchant.trim(),amount,payment_method:method,transaction_date:transactionDate,purchase_reference:reference};
}
export function sniffMime(bytes) {
  if(bytes.length>=8&&[137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v))return {type:'image/png',ext:'png'};
  if(bytes.length>=3&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return {type:'image/jpeg',ext:'jpg'};
  if(bytes.length>=5&&new TextDecoder().decode(bytes.slice(0,5))==='%PDF-')return {type:'application/pdf',ext:'pdf'};
  throw new Error('Receipt contents must be a JPG, PNG or PDF file.');
}
export function validUuid(value) {return typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value);}
