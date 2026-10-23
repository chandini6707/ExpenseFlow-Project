-- Additive upgrade: existing claims remain intact; future submissions include payment details.
begin;
alter table public.expenses
 add column payment_method text check (payment_method in ('UPI','Debit Card','Credit Card','Bank Transfer','Cash','Other')),
 add column transaction_date date,
 add column purchase_reference text not null default '' check (length(purchase_reference)<=120),
 add column payment_proof_path text,
 add column payment_proof_hash text check (payment_proof_hash is null or payment_proof_hash ~ '^[a-f0-9]{64}$'),
 add column payment_proof_name text,
 add column payment_proof_type text;
create index expense_payment_proof_hash on public.expenses(payment_proof_hash) where payment_proof_hash is not null;

create table public.reimbursement_tickets (
 id uuid primary key default gen_random_uuid(),
 expense_id uuid not null unique references public.expenses(id),
 employee_id uuid not null references public.profiles(id),
 status text not null default 'awaiting_details' check (status in ('awaiting_details','submitted','closed')),
 created_at timestamptz not null default now(), submitted_at timestamptz, updated_at timestamptz not null default now()
);
create index ticket_employee_status on public.reimbursement_tickets(employee_id,status);
alter table public.reimbursement_tickets enable row level security;
revoke all on public.reimbursement_tickets from public,anon,authenticated;
grant select on public.reimbursement_tickets to authenticated;
grant all on public.reimbursement_tickets to service_role;
create policy tickets_read on public.reimbursement_tickets for select to authenticated
 using (expense_private.can_read_expense(expense_id));

-- Full bank details are kept outside the exposed API schema, with no direct client grants.
create table expense_private.bank_details (
 ticket_id uuid primary key references public.reimbursement_tickets(id),
 account_holder text not null check (length(trim(account_holder)) between 2 and 120),
 bank_name text not null check (length(trim(bank_name)) between 2 and 100),
 account_number text not null check (account_number ~ '^[0-9]{6,18}$'),
 ifsc text not null check (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
 updated_at timestamptz not null default now()
);
alter table expense_private.bank_details enable row level security;
revoke all on expense_private.bank_details from public,anon,authenticated;

create function expense_private.ticket_summary(p_expense_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t public.reimbursement_tickets; e public.expenses; b expense_private.bank_details; result jsonb;
begin
 if auth.uid() is null or not expense_private.can_read_expense(p_expense_id) then raise exception 'You cannot access this reimbursement ticket.'; end if;
 select * into t from public.reimbursement_tickets where expense_id=p_expense_id;
 if not found then return null; end if;
 result:=to_jsonb(t);
 select * into e from public.expenses where id=p_expense_id;
 if e.employee_id=auth.uid() or expense_private.role_of(auth.uid())='finance' then
   select * into b from expense_private.bank_details where ticket_id=t.id;
   if found then result:=result||jsonb_build_object('account_holder',b.account_holder,'bank_name',b.bank_name,'account_last4',right(b.account_number,4),'ifsc',b.ifsc); end if;
 end if;
 return result;
end; $$;
create function public.get_reimbursement_ticket(p_expense_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select expense_private.ticket_summary(p_expense_id); $$;

create function expense_private.submit_bank_details(p_expense_id uuid,p_account_holder text,p_bank_name text,p_account_number text,p_account_number_confirm text,p_ifsc text)
returns void language plpgsql security definer set search_path='' as $$
declare e public.expenses; t public.reimbursement_tickets; old expense_private.bank_details; f record;
begin
 if auth.uid() is null then raise exception 'Sign in to submit your bank details.'; end if;
 select * into e from public.expenses where id=p_expense_id for update;
 if not found or e.employee_id<>auth.uid() then raise exception 'This is not your reimbursement request.'; end if;
 select * into t from public.reimbursement_tickets where expense_id=p_expense_id for update;
 if not found or t.employee_id<>auth.uid() or not (e.status='approved' or (e.status='processing' and t.status='awaiting_details')) then
   raise exception 'Bank details can be entered only after approval and cannot change once finance starts processing.';
 end if;
 p_account_holder:=trim(p_account_holder);p_bank_name:=trim(p_bank_name);p_ifsc:=upper(trim(p_ifsc));
 if p_account_holder is null or length(p_account_holder) not between 2 and 120 or p_bank_name is null or length(p_bank_name) not between 2 and 100
 or p_account_number is null or p_account_number !~ '^[0-9]{6,18}$'
 or p_account_number_confirm is distinct from p_account_number or p_ifsc is null or p_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' then
   raise exception 'Enter an account holder, bank name, matching 6–18 digit account numbers and a valid 11-character IFSC.';
 end if;
 select * into old from expense_private.bank_details where ticket_id=t.id;
 if found and t.status='submitted' and old.account_holder=p_account_holder and old.bank_name=p_bank_name and old.account_number=p_account_number and old.ifsc=p_ifsc then return; end if;
 insert into expense_private.bank_details(ticket_id,account_holder,bank_name,account_number,ifsc)
 values(t.id,p_account_holder,p_bank_name,p_account_number,p_ifsc)
 on conflict(ticket_id) do update set account_holder=excluded.account_holder,bank_name=excluded.bank_name,account_number=excluded.account_number,ifsc=excluded.ifsc,updated_at=now();
 update public.reimbursement_tickets set status='submitted',submitted_at=now(),updated_at=now() where id=t.id;
 perform expense_private.event(auth.uid(),e.id,'Reimbursement bank details submitted',jsonb_build_object('ticket_id',t.id));
 perform expense_private.notify(auth.uid(),e.id,'Your bank details were received securely. Finance can now continue with reimbursement.');
 for f in select id from public.profiles where role='finance' loop
   perform expense_private.notify(f.id,e.id,'Bank details received for '||e.title||'. Ready for reimbursement processing.');
 end loop;
end; $$;
create function public.submit_bank_details(p_expense_id uuid,p_account_holder text,p_bank_name text,p_account_number text,p_account_number_confirm text,p_ifsc text)
returns void language sql security invoker set search_path='' as $$
 select expense_private.submit_bank_details(p_expense_id,p_account_holder,p_bank_name,p_account_number,p_account_number_confirm,p_ifsc);
$$;

create function expense_private.reveal_bank_details(p_expense_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b expense_private.bank_details;
begin
 if auth.uid() is null or expense_private.role_of(auth.uid()) is distinct from 'finance' then raise exception 'Only finance can reveal full bank details.'; end if;
 select bnk.* into b from expense_private.bank_details bnk
 join public.reimbursement_tickets t on t.id=bnk.ticket_id join public.expenses e on e.id=t.expense_id
 where e.id=p_expense_id and e.status in ('approved','processing','paid') and t.status in ('submitted','closed');
 if not found then raise exception 'Bank details are not available for this reimbursement.'; end if;
 perform expense_private.event(auth.uid(),p_expense_id,'Bank details viewed by finance');
 return jsonb_build_object('account_holder',b.account_holder,'bank_name',b.bank_name,'account_number',b.account_number,'ifsc',b.ifsc);
end; $$;
create function public.get_bank_details(p_expense_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select expense_private.reveal_bank_details(p_expense_id); $$;

revoke all on function expense_private.ticket_summary(uuid),expense_private.submit_bank_details(uuid,text,text,text,text,text),expense_private.reveal_bank_details(uuid),
 public.get_reimbursement_ticket(uuid),public.submit_bank_details(uuid,text,text,text,text,text),public.get_bank_details(uuid) from public,anon,authenticated;
grant execute on function expense_private.ticket_summary(uuid),expense_private.submit_bank_details(uuid,text,text,text,text,text),expense_private.reveal_bank_details(uuid),
 public.get_reimbursement_ticket(uuid),public.submit_bank_details(uuid,text,text,text,text,text),public.get_bank_details(uuid) to authenticated;

-- Both evidence files inherit the same claim-specific access policy.
drop policy expenseflow_receipt_read on storage.objects;
create policy expenseflow_receipt_read on storage.objects for select to authenticated using
 (bucket_id='receipts' and exists(select 1 from public.expenses e where (e.receipt_path=name or e.payment_proof_path=name) and expense_private.can_read_expense(e.id)));

-- Existing approved/unpaid purchases also receive a ticket; paid history is untouched.
with inserted as (
 insert into public.reimbursement_tickets(expense_id,employee_id)
 select id,employee_id from public.expenses where status in ('approved','processing')
 on conflict(expense_id) do nothing returning expense_id,employee_id
)
insert into public.notifications(user_id,expense_id,message)
select employee_id,expense_id,'Your purchase is approved. Open your reimbursement ticket to provide the account holder name, bank account number and IFSC.' from inserted;
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='reimbursement_tickets') then
   alter publication supabase_realtime add table public.reimbursement_tickets;
 end if;
end; $$;

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
 v_status public.expense_status; v_summary text; matches integer;
begin
 -- Lock the profile to serialize simultaneous same-employee duplicate checks.
 select * into person from public.profiles where id=p_actor for update;
 if not found or person.role <> 'employee' then raise exception 'Only employee accounts can submit expenses.'; end if;
 select * into old from public.expenses where id=p_id for update;
 if found and (old.employee_id <> p_actor or old.status <> 'draft') then raise exception 'Only your own drafts can be edited.'; end if;
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
   if person.manager_id is null or person.manager_id=p_actor or expense_private.role_of(person.manager_id)<>'manager' then raise exception 'An administrator must assign a manager before submission. You can save a draft.'; end if;
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
 perform expense_private.event(p_actor,p_id,case when p_submit then 'Expense submitted' else 'Draft saved' end,jsonb_build_object('status',v_status,'verification',v_summary));
 if p_submit then
   perform expense_private.notify(p_actor,p_id,case when v_status='flagged' then 'Your claim was submitted and flagged for review.' else 'Your claim was submitted for manager approval.' end);
   perform expense_private.notify(person.manager_id,p_id,'New expense from '||person.full_name||': '||v_title);
 end if;
 return p_id;
end; $$;

create or replace function public.review_expense(p_id uuid,p_decision text,p_comments text default '') returns void language plpgsql security definer set search_path = '' as $$
declare e public.expenses; pol public.expense_policies; f record;
begin
 if expense_private.role_of(auth.uid()) is distinct from 'manager' then raise exception 'Manager access required.'; end if;
 select * into e from public.expenses where id=p_id for update;
 if not found or e.assigned_manager_id<>auth.uid() or e.employee_id=auth.uid() or e.status not in ('pending','flagged') then raise exception 'This expense is not assigned to you or was already reviewed.'; end if;
 if p_decision not in ('approved','rejected') or p_decision is null or length(p_comments)>1000 then raise exception 'Invalid review decision.'; end if;
 -- Policy may have changed since submission: require a documented manual decision.
 select * into pol from public.expense_policies where category=e.category;
 if p_decision='rejected' or (p_decision='approved' and (e.status='flagged' or not pol.active or e.amount>pol.maximum_amount)) then
   if length(trim(p_comments))<8 then raise exception 'Provide a reason of at least 8 characters for rejection or a flagged/policy-exception approval.'; end if;
 end if;
 update public.expenses set status=p_decision::public.expense_status,updated_at=now() where id=p_id;
 insert into public.approvals(expense_id,manager_id,decision,comments) values(p_id,auth.uid(),p_decision,trim(p_comments));
 perform expense_private.event(auth.uid(),p_id,'Manager '||p_decision,jsonb_build_object('comments',trim(p_comments),'status',p_decision));
 perform expense_private.notify(e.employee_id,p_id,'Your expense was '||p_decision||case when trim(p_comments)<>'' then ': '||trim(p_comments) else '.' end);
 if p_decision='approved' then
   insert into public.reimbursement_tickets(expense_id,employee_id) values(p_id,e.employee_id);
   perform expense_private.event(auth.uid(),p_id,'Bank-details ticket opened');
   perform expense_private.notify(e.employee_id,p_id,'Your purchase is approved. Open your reimbursement ticket to provide the account holder name, bank account number and IFSC.');
   for f in select id from public.profiles where role='finance' loop
   perform expense_private.notify(f.id,p_id,'Approved purchase; waiting for employee bank details: '||e.title);
 end loop; end if;
end; $$;

create or replace function public.process_reimbursement(p_id uuid,p_action text,p_reference text default '',p_payment_date date default null) returns void language plpgsql security definer set search_path = '' as $$
declare e public.expenses;
begin
 if expense_private.role_of(auth.uid()) is distinct from 'finance' then raise exception 'Finance access required.'; end if;
 select * into e from public.expenses where id=p_id for update;
 if not found then raise exception 'Expense not found.'; end if;
 if not exists(select 1 from public.reimbursement_tickets t join expense_private.bank_details b on b.ticket_id=t.id where t.expense_id=p_id and t.status='submitted') then
   raise exception 'The employee must submit bank details through their reimbursement ticket before finance can continue.';
 end if;
 if p_action='processing' and e.status='approved' then
   insert into public.reimbursements(expense_id,amount,status,processed_by) values(p_id,e.amount,'processing',auth.uid());
 elsif p_action='paid' and e.status='processing' then
   if p_reference is null or length(trim(p_reference)) not between 3 and 120 or p_payment_date is null or p_payment_date>current_date or p_payment_date<e.expense_date then raise exception 'Enter a unique demo reference and a valid payment date on or after the expense date.'; end if;
   update public.reimbursements set status='paid',transaction_reference=trim(p_reference),payment_date=p_payment_date,processed_by=auth.uid(),updated_at=now() where expense_id=p_id and status='processing';
   if not found then raise exception 'Reimbursement record is not processing.'; end if;
 else raise exception 'Invalid transition or reimbursement already processed.'; end if;
 update public.expenses set status=p_action::public.expense_status,updated_at=now() where id=p_id;
 if p_action='paid' then update public.reimbursement_tickets set status='closed',updated_at=now() where expense_id=p_id; end if;
 perform expense_private.event(auth.uid(),p_id,case when p_action='paid' then 'Demo reimbursement completed' else 'Reimbursement processing started' end,jsonb_build_object('status',p_action,'reference',trim(p_reference),'simulated',true));
 perform expense_private.notify(e.employee_id,p_id,case when p_action='paid' then 'Your reimbursement was marked completed in the demo. Reference: '||trim(p_reference)||'. No money was transferred.' else 'Finance started processing your reimbursement.' end);
end; $$;

commit;
