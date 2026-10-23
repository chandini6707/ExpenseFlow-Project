-- Employees may submit complete expenses before a manager is assigned.
-- Authentication, receipt verification, RLS and privileged review rules are unchanged.
begin;
alter table public.expenses drop constraint expenses_check1;
alter table public.expenses add constraint expenses_check1 check (
 status='draft' or (receipt_path is not null and receipt_hash is not null and length(purpose)>=8
   and (status in ('pending','flagged') or assigned_manager_id is not null))
);

create or replace function public.save_expense_verified(p_actor uuid,p_id uuid,p_payload jsonb,p_submit boolean,
  p_receipt_path text,p_receipt_hash text,p_receipt_name text,p_receipt_type text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
 old public.expenses; person public.profiles; pol public.expense_policies; flags jsonb := '[]';
 v_category text := p_payload->>'category'; v_amount numeric; v_date date; v_merchant text := trim(p_payload->>'merchant');
 v_title text := trim(p_payload->>'title'); v_purpose text := trim(coalesce(p_payload->>'purpose','')); v_invoice text := trim(coalesce(p_payload->>'invoice_number',''));
 v_method text := nullif(trim(p_payload->>'payment_method'),''); v_transaction_date date := nullif(p_payload->>'transaction_date','')::date;
 v_reference text := trim(coalesce(p_payload->>'purchase_reference',''));
 v_proof_path text := p_payload->>'payment_proof_path'; v_proof_hash text := p_payload->>'payment_proof_hash';
 v_status public.expense_status; v_summary text; matches integer; reviewer record;
begin
 -- Lock the profile to serialize simultaneous same-employee duplicate checks.
 select * into person from public.profiles where id=p_actor for update;
 if not found or person.role <> 'employee' then raise exception 'Only employee accounts can submit expenses.'; end if;
 select * into old from public.expenses where id=p_id for update;
 if found and old.employee_id<>p_actor then raise exception 'Only your own drafts can be edited.'; end if;
 if old.id is not null and old.status<>'draft' then
   if p_submit and row(old.title,old.category,old.amount,old.expense_date,old.merchant,old.purpose,old.description,
       old.invoice_number,old.payment_method,old.transaction_date,old.purchase_reference,old.receipt_hash,old.payment_proof_hash)
     is not distinct from row(v_title,v_category,(p_payload->>'amount')::numeric,(p_payload->>'expense_date')::date,v_merchant,v_purpose,
       coalesce(p_payload->>'description',''),v_invoice,v_method,v_transaction_date,v_reference,p_receipt_hash,v_proof_hash) then
     return p_id; -- Same operation, same content: acknowledge the committed result without another submission.
   end if;
   raise exception 'This claim was already submitted with different details. Refresh to view the saved expense.';
 end if;
 v_amount := (p_payload->>'amount')::numeric;
 v_date := (p_payload->>'expense_date')::date;
 if v_title is null or length(v_title) not between 1 and 120 or v_merchant is null or length(v_merchant) not between 1 and 120
 or v_amount is null or v_amount <= 0 or v_amount > 10000000 or v_amount <> round(v_amount,2)
 or v_date is null or v_date > current_date or length(v_purpose)>1000 or length(v_invoice)>80 or length(coalesce(p_payload->>'description',''))>2000 then
   raise exception 'Enter a valid title, merchant, amount and expense date.';
 end if;
 if v_method is not null and v_method not in ('UPI','Debit Card','Credit Card','Bank Transfer','Cash','Other') then raise exception 'Choose a valid purchase payment method.'; end if;
 if v_transaction_date>current_date or length(v_reference)>120 then raise exception 'Enter a valid purchase transaction date and reference.'; end if;
 if p_submit and (v_method is null or v_transaction_date is null or (v_method<>'Cash' and length(v_reference)<3)) then
   raise exception 'Provide the payment method, payment date and a transaction reference for non-cash purchases.';
 end if;
 if v_proof_path is not null and (v_proof_path not like p_actor::text || '/' || p_id::text || '/%'
 or v_proof_hash is null or v_proof_hash !~ '^[a-f0-9]{64}$'
 or (p_payload->>'payment_proof_type') is null or (p_payload->>'payment_proof_type') not in ('image/jpeg','image/png','application/pdf')
 or not exists(select 1 from storage.objects where bucket_id='receipts' and name=v_proof_path)) then raise exception 'Payment proof verification failed.'; end if;
 select * into pol from public.expense_policies where category=v_category;
 if not found then raise exception 'Choose an allowed category.'; end if;
 if p_receipt_path is not null then
   perform pg_advisory_xact_lock(hashtextextended(p_receipt_hash,0));
   if p_receipt_path not like p_actor::text || '/' || p_id::text || '/%' or p_receipt_hash is null or p_receipt_hash !~ '^[a-f0-9]{64}$'
   or p_receipt_type is null or p_receipt_type not in ('image/jpeg','image/png','application/pdf')
   or not exists(select 1 from storage.objects where bucket_id='receipts' and name=p_receipt_path) then raise exception 'Receipt verification failed.'; end if;
 end if;
 if p_submit then
   if length(v_purpose)<8 or p_receipt_path is null then raise exception 'A receipt and business purpose of at least 8 characters are required.'; end if;
   -- A manager assignment routes a claim; it is not permission for an employee to submit.
   -- Stale/invalid profile assignments are treated as unassigned, never trusted as privileges.
   if person.manager_id=p_actor or (person.manager_id is not null and expense_private.role_of(person.manager_id) is distinct from 'manager') then person.manager_id:=null; end if;
   if v_proof_hash is not null and exists(select 1 from public.expenses where id<>p_id and status<>'draft' and payment_proof_hash=v_proof_hash) then
     flags:=flags||jsonb_build_array(jsonb_build_object('code','duplicate','label','Possible Duplicate','reason','An identical payment proof was used on another submitted claim.'));
   end if;
   if v_method<>'Cash' and length(v_reference)>=3 and exists(select 1 from public.expenses where id<>p_id and status<>'draft' and employee_id=p_actor and lower(purchase_reference)=lower(v_reference) and lower(merchant)=lower(v_merchant)) then
     flags:=flags||jsonb_build_array(jsonb_build_object('code','duplicate','label','Possible Duplicate','reason','You already submitted this transaction reference for the same merchant.'));
   end if;
   if not pol.active then flags := flags || jsonb_build_array(jsonb_build_object('code','manual','label','Requires Manual Review','reason','This category is currently inactive.')); end if;
   if v_amount>pol.maximum_amount then flags := flags || jsonb_build_array(jsonb_build_object('code','limit','label','Policy Limit Exceeded','reason','Claim amount exceeds the category limit of INR '||pol.maximum_amount)); end if;
   select count(*) into matches from public.expenses e where e.id<>p_id and e.status<>'draft' and e.receipt_hash=p_receipt_hash;
   if matches>0 then flags := flags || jsonb_build_array(jsonb_build_object('code','duplicate','label','Possible Duplicate','reason','An identical receipt file was already submitted.')); end if;
   select count(*) into matches from public.expenses e where e.id<>p_id and e.employee_id=p_actor and e.status<>'draft'
     and ((lower(trim(e.merchant))=lower(v_merchant) and e.expense_date=v_date and e.amount=v_amount)
     or (v_invoice<>'' and lower(trim(e.invoice_number))=lower(v_invoice) and lower(trim(e.merchant))=lower(v_merchant)));
   if matches>0 then flags := flags || jsonb_build_array(jsonb_build_object('code','similar','label','Possible Duplicate','reason','This employee has a matching vendor/date/amount or vendor/invoice claim.')); end if;
   if (v_category<>'Accommodation' and lower(v_merchant) ~ '(hotel|resort|lodge)')
   or (v_category<>'Transportation' and lower(v_merchant) ~ '(uber|ola cabs|taxi)')
   or (v_category<>'Food' and lower(v_merchant) ~ '(restaurant|swiggy|zomato|cafe)') then
     flags := flags || jsonb_build_array(jsonb_build_object('code','category','label','Requires Manual Review','reason','The merchant name suggests a different category. Check the original bill.'));
   end if;
   v_status := case when jsonb_array_length(flags)=0 then 'pending'::public.expense_status else 'flagged'::public.expense_status end;
   v_summary := case when v_status='pending' then 'Policy Compliant' else 'Requires Manual Review' end;
 else v_status := 'draft'; v_summary := 'Draft'; end if;
 insert into public.expenses(id,employee_id,assigned_manager_id,title,category,amount,expense_date,merchant,invoice_number,purpose,description,
   receipt_path,receipt_hash,receipt_name,receipt_type,verification_status,verification_details,status,payment_method,transaction_date,purchase_reference,payment_proof_path,payment_proof_hash,payment_proof_name,payment_proof_type)
 values(p_id,p_actor,case when p_submit then person.manager_id else null end,v_title,v_category,v_amount,v_date,v_merchant,v_invoice,v_purpose,coalesce(p_payload->>'description',''),
   p_receipt_path,p_receipt_hash,p_receipt_name,p_receipt_type,v_summary,flags,v_status,v_method,v_transaction_date,v_reference,v_proof_path,v_proof_hash,p_payload->>'payment_proof_name',p_payload->>'payment_proof_type')
 on conflict(id) do update set assigned_manager_id=excluded.assigned_manager_id,title=excluded.title,category=excluded.category,amount=excluded.amount,
 expense_date=excluded.expense_date,merchant=excluded.merchant,invoice_number=excluded.invoice_number,purpose=excluded.purpose,description=excluded.description,
 receipt_path=excluded.receipt_path,receipt_hash=excluded.receipt_hash,receipt_name=excluded.receipt_name,receipt_type=excluded.receipt_type,
 payment_method=excluded.payment_method,transaction_date=excluded.transaction_date,purchase_reference=excluded.purchase_reference,payment_proof_path=excluded.payment_proof_path,payment_proof_hash=excluded.payment_proof_hash,payment_proof_name=excluded.payment_proof_name,payment_proof_type=excluded.payment_proof_type,
 verification_status=excluded.verification_status,verification_details=excluded.verification_details,status=excluded.status,updated_at=now();
 perform expense_private.event(p_actor,p_id,case when p_submit then 'Expense submitted' else 'Draft saved' end,jsonb_build_object('status',v_status,'verification',v_summary,'assigned_manager_id',person.manager_id));
 if p_submit then
   perform expense_private.notify(p_actor,p_id,
     (case when v_status='flagged' then 'Your claim was submitted and flagged for review.' else 'Your claim was submitted for manager approval.' end)
     ||case when person.manager_id is null then ' No manager is assigned yet. Your expense is saved and awaiting administrator assignment.' else '' end);
   if person.manager_id is not null then
     perform expense_private.notify(person.manager_id,p_id,'New expense from '||person.full_name||': '||v_title);
   else
     for reviewer in select id from public.profiles where role='admin' loop
       perform expense_private.notify(reviewer.id,p_id,'Manager assignment needed for a submitted expense from '||person.full_name||': '||v_title);
     end loop;
   end if;
 end if;
 return p_id;
end; $$;



create or replace function expense_private.admin_update_user(p_id uuid,p_role public.app_role,p_manager uuid,p_department text) returns void language plpgsql security definer set search_path='' as $$
declare target public.profiles; claim public.expenses;
begin
 perform pg_advisory_xact_lock(638122);
 if expense_private.role_of(auth.uid()) is distinct from 'admin' then raise exception 'Administrator access required.'; end if;
 select * into target from public.profiles where id=p_id for update;
 if not found or p_role is null or p_department is null or length(trim(p_department)) not between 1 and 100 then raise exception 'Invalid user or department.'; end if;
 if target.role='admin' and p_role<>'admin' and (select count(*) from public.profiles where role='admin')<=1 then raise exception 'The organization must retain an administrator.'; end if;
 if p_manager is not null and (p_manager=p_id or expense_private.role_of(p_manager) is distinct from 'manager') then raise exception 'Select a different user with the manager role.'; end if;
 if target.role='manager' and p_role<>'manager' and (exists(select 1 from public.profiles where manager_id=p_id) or exists(select 1 from public.expenses where assigned_manager_id=p_id and status in ('pending','flagged'))) then raise exception 'Reassign employees and complete pending reviews before changing this manager role.'; end if;
 update public.profiles set role=p_role,manager_id=case when p_role='employee' then p_manager else null end,department=trim(p_department),updated_at=now() where id=p_id;
 if target.role_request_status='pending' and target.requested_role=p_role then
   update public.profiles set role_request_status='approved',role_reviewed_at=now(),role_reviewed_by=auth.uid() where id=p_id;
 end if;
 -- Lock order matches submission (profile, then expenses). Only undecided claims move.
 -- A simultaneous manager decision either completes first or sees the new assignment.
 if p_role='employee' then
   for claim in select * from public.expenses where employee_id=p_id and status in ('pending','flagged')
     and assigned_manager_id is distinct from p_manager for update
   loop
     update public.expenses set assigned_manager_id=p_manager,updated_at=now() where id=claim.id;
     perform expense_private.event(auth.uid(),claim.id,'Expense manager assignment updated',
       jsonb_build_object('previous_manager_id',claim.assigned_manager_id,'assigned_manager_id',p_manager,'status',claim.status));
     if p_manager is not null then
       perform expense_private.notify(p_manager,claim.id,'Expense assigned for your review: '||claim.title);
       perform expense_private.notify(p_id,claim.id,'A manager has been assigned to review your expense: '||claim.title);
     else
       perform expense_private.notify(p_id,claim.id,'Your submitted expense remains saved and awaits a new manager assignment: '||claim.title);
     end if;
   end loop;
 end if;
 perform expense_private.event(auth.uid(),null,'User access updated',jsonb_build_object('user_id',p_id,'role',p_role,'manager_id',p_manager));
 perform expense_private.notify(p_id,null,'Your workspace access was updated. Authorized role: '||p_role||'. Refresh to open your dashboard.');
end; $$;


commit;
