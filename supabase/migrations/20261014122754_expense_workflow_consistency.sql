-- Existing tables remain the source of truth. All repairs and transitions are transactional.
begin;

-- System repairs have no human actor; never attribute an unrecorded approval to a manager.
alter table public.audit_logs alter column actor_id drop not null;
do $$ declare e public.expenses; begin
 for e in select * from public.expenses x where x.status='approved'
   and not exists(select 1 from public.approvals a where a.expense_id=x.id)
   and not exists(select 1 from public.reimbursements r where r.expense_id=x.id) for update
 loop
   update public.expenses set status='flagged',updated_at=now(),verification_status='Requires Manual Review',
     verification_details=verification_details||jsonb_build_array(jsonb_build_object('code','consistency','label','Requires Manual Review',
     'reason','This claim had an approved status without a recorded manager decision. A manager must review it before reimbursement.')) where id=e.id;
   perform expense_private.event(null,e.id,'Inconsistent approval returned for manager review',jsonb_build_object('source','consistency migration','previous_status',e.status,'status','flagged'));
 end loop;
end; $$;

-- Complete ticket history only from actual approvals and recorded reimbursements.
-- A legacy paid claim does not imply that bank details were collected.
with repaired as (
 insert into public.reimbursement_tickets(expense_id,employee_id,status)
 select e.id,e.employee_id,case when e.status='paid' then 'closed' else 'awaiting_details' end
 from public.expenses e join public.approvals a on a.expense_id=e.id and a.decision='approved'
 where e.status in ('approved','paid') and (e.status='approved' or exists(select 1 from public.reimbursements r where r.expense_id=e.id and r.status='paid' and r.amount=e.amount))
 on conflict(expense_id) do nothing returning expense_id,status
)
insert into public.audit_logs(actor_id,expense_id,action,metadata)
select null,expense_id,'Missing reimbursement ticket restored',jsonb_build_object('source','consistency migration','ticket_status',status) from repaired;

-- Dormant legacy tickets are retained, but become actionable only after a real approval.
drop policy tickets_read on public.reimbursement_tickets;
create policy tickets_read on public.reimbursement_tickets for select to authenticated using
 (expense_private.can_read_expense(expense_id) and exists(select 1 from public.expenses e where e.id=expense_id and e.status in ('approved','processing','paid')));

-- A stable invoker RPC reads one MVCC snapshot, honors RLS, and avoids REST's 1,000-row
-- limit / offset pagination drift. No bank account number is included in this result.
create function public.expense_workspace(p_id uuid default null) returns jsonb
language sql stable security invoker set search_path='' as $$
 with directory as materialized (select x from jsonb_array_elements(public.profile_directory()) x),
 records as (
   select e.created_at,e.id,to_jsonb(e)||jsonb_build_object(
     'employee_name',coalesce(d.x->>'full_name','Employee'),'department',coalesce(d.x->>'department','General'),
     'approvals',coalesce((select jsonb_agg(to_jsonb(a)) from public.approvals a where a.expense_id=e.id),'[]'::jsonb),
     'reimbursements',coalesce((select jsonb_agg(to_jsonb(r)) from public.reimbursements r where r.expense_id=e.id),'[]'::jsonb),
     'ticket',case when e.status not in ('approved','processing','paid') then null
       when p_id is not null then public.get_reimbursement_ticket(e.id)
       else (select to_jsonb(t) from public.reimbursement_tickets t where t.expense_id=e.id) end,
     'logs',case when p_id is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at,l.id) from public.audit_logs l where l.expense_id=e.id),'[]'::jsonb) end
   ) as record
   from public.expenses e left join directory d on d.x->>'id'=e.employee_id::text
   where p_id is null or e.id=p_id
 ) select jsonb_build_object('expenses',coalesce(jsonb_agg(record order by created_at desc,id),'[]'::jsonb),'read_at',statement_timestamp()) from records;
$$;
revoke all on function public.expense_workspace(uuid) from public,anon;
grant execute on function public.expense_workspace(uuid) to authenticated;

create function expense_private.review_expense(p_id uuid,p_decision text,p_comments text default '') returns void
language plpgsql security definer set search_path='' as $$
declare e public.expenses; a public.approvals; pol public.expense_policies; f record;
begin
 if auth.uid() is null or expense_private.role_of(auth.uid()) is distinct from 'manager' then raise exception 'Manager access required.'; end if;
 p_comments:=trim(coalesce(p_comments,''));
 if p_decision is null or p_decision not in ('approved','rejected') or length(p_comments)>1000 then raise exception 'Invalid review decision.'; end if;
 select * into e from public.expenses where id=p_id for update;
 if not found or e.assigned_manager_id is distinct from auth.uid() or e.employee_id=auth.uid() then raise exception 'This expense is not assigned to you.'; end if;
 select * into a from public.approvals where expense_id=p_id;
 if found then
   if a.manager_id=auth.uid() and a.decision=p_decision and a.comments=p_comments then return; end if;
   raise exception 'This expense already has a recorded decision. Refresh to view it.';
 end if;
 if e.status not in ('pending','flagged') then raise exception 'This expense is not awaiting review.'; end if;
 select * into pol from public.expense_policies where category=e.category;
 if (p_decision='rejected' or e.status='flagged' or not pol.active or e.amount>pol.maximum_amount) and length(p_comments)<8 then
   raise exception 'Provide a reason of at least 8 characters for rejection or a flagged/policy-exception approval.';
 end if;
 insert into public.approvals(expense_id,manager_id,decision,comments) values(p_id,auth.uid(),p_decision,p_comments);
 update public.expenses set status=p_decision::public.expense_status,updated_at=now() where id=p_id;
 perform expense_private.event(auth.uid(),p_id,'Manager '||p_decision,jsonb_build_object('comments',p_comments,'status',p_decision));
 perform expense_private.notify(e.employee_id,p_id,'Your expense was '||p_decision||case when p_comments<>'' then ': '||p_comments else '.' end);
 if p_decision='approved' then
   insert into public.reimbursement_tickets(expense_id,employee_id) values(p_id,e.employee_id) on conflict(expense_id) do nothing;
   perform expense_private.event(auth.uid(),p_id,'Bank-details ticket opened');
   perform expense_private.notify(e.employee_id,p_id,'Your purchase is approved. Open your reimbursement ticket to provide or review your bank details.');
   for f in select id from public.profiles where role='finance' loop
     perform expense_private.notify(f.id,p_id,'Approved purchase: '||e.title||'. Check the bank-details ticket before processing.');
   end loop;
 end if;
end; $$;
create or replace function public.review_expense(p_id uuid,p_decision text,p_comments text default '') returns void
language sql security invoker set search_path='' as $$ select expense_private.review_expense(p_id,p_decision,p_comments); $$;

create function expense_private.process_reimbursement(p_id uuid,p_action text,p_reference text default '',p_payment_date date default null) returns void
language plpgsql security definer set search_path='' as $$
declare e public.expenses; r public.reimbursements;
begin
 if auth.uid() is null or expense_private.role_of(auth.uid()) is distinct from 'finance' then raise exception 'Finance access required.'; end if;
 if p_action is null or p_action not in ('processing','paid') then raise exception 'Invalid reimbursement action.'; end if;
 p_reference:=trim(coalesce(p_reference,''));
 select * into e from public.expenses where id=p_id for update;
 if not found then raise exception 'Expense not found.'; end if;
 if not exists(select 1 from public.approvals a where a.expense_id=p_id and a.decision='approved' and a.manager_id=e.assigned_manager_id and a.manager_id<>e.employee_id) then
   raise exception 'A recorded manager approval is required before reimbursement.';
 end if;
 select * into r from public.reimbursements where expense_id=p_id;
 -- Retry acknowledgements never insert another payment, notification or audit event.
 if p_action='processing' and e.status in ('processing','paid') and r.status=e.status::text and r.amount=e.amount then return; end if;
 if p_action='paid' and e.status='paid' and r.status='paid' and r.amount=e.amount and r.transaction_reference=p_reference and r.payment_date=p_payment_date then return; end if;
 if not exists(select 1 from public.reimbursement_tickets t join expense_private.bank_details b on b.ticket_id=t.id where t.expense_id=p_id and t.employee_id=e.employee_id and t.status='submitted') then
   raise exception 'The employee must submit bank details through their reimbursement ticket before finance can continue.';
 end if;
 if p_action='processing' and e.status='approved' then
   insert into public.reimbursements(expense_id,amount,status,processed_by) values(p_id,e.amount,'processing',auth.uid());
 elsif p_action='paid' and e.status='processing' then
   if length(p_reference) not between 3 and 120 or p_payment_date is null or p_payment_date>current_date or p_payment_date<e.expense_date then raise exception 'Enter a unique demo reference and a valid payment date on or after the expense date.'; end if;
   update public.reimbursements set status='paid',transaction_reference=p_reference,payment_date=p_payment_date,processed_by=auth.uid(),updated_at=now() where expense_id=p_id and status='processing' and amount=e.amount;
   if not found then raise exception 'Reimbursement record does not match this expense.'; end if;
 else raise exception 'Invalid transition or a different reimbursement was already recorded. Refresh to view it.'; end if;
 update public.expenses set status=p_action::public.expense_status,updated_at=now() where id=p_id;
 if p_action='paid' then update public.reimbursement_tickets set status='closed',updated_at=now() where expense_id=p_id; end if;
 perform expense_private.event(auth.uid(),p_id,case when p_action='paid' then 'Demo reimbursement completed' else 'Reimbursement processing started' end,jsonb_build_object('status',p_action,'reference',p_reference,'simulated',true));
 perform expense_private.notify(e.employee_id,p_id,case when p_action='paid' then 'Your reimbursement was marked completed in the demo. Reference: '||p_reference||'. No money was transferred.' else 'Finance started processing your reimbursement.' end);
end; $$;
create or replace function public.process_reimbursement(p_id uuid,p_action text,p_reference text default '',p_payment_date date default null) returns void
language sql security invoker set search_path='' as $$ select expense_private.process_reimbursement(p_id,p_action,p_reference,p_payment_date); $$;
revoke all on function expense_private.review_expense(uuid,text,text),expense_private.process_reimbursement(uuid,text,text,date),public.review_expense(uuid,text,text),public.process_reimbursement(uuid,text,text,date) from public,anon,authenticated;
grant execute on function expense_private.review_expense(uuid,text,text),expense_private.process_reimbursement(uuid,text,text,date),public.review_expense(uuid,text,text),public.process_reimbursement(uuid,text,text,date) to authenticated;

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


create or replace function expense_private.ticket_summary(p_expense_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t public.reimbursement_tickets; e public.expenses; b expense_private.bank_details; result jsonb;
begin
 if auth.uid() is null or not expense_private.can_read_expense(p_expense_id) then raise exception 'You cannot access this reimbursement ticket.'; end if;
 if not exists(select 1 from public.expenses where id=p_expense_id and status in ('approved','processing','paid')) then return null; end if;
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

-- Deferred validation permits the RPCs to update several related rows atomically,
-- but rejects a transaction that leaves a status, decision, ticket or payment inconsistent.
create function expense_private.check_expense_consistency(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare e public.expenses; a public.approvals; r public.reimbursements; t public.reimbursement_tickets;
begin
 select * into e from public.expenses where id=p_id for update;
 if not found then return; end if;
 select * into a from public.approvals where expense_id=p_id;
 select * into r from public.reimbursements where expense_id=p_id;
 select * into t from public.reimbursement_tickets where expense_id=p_id;
 if e.status in ('approved','processing','paid','rejected') then
   if a.id is null or a.manager_id is distinct from e.assigned_manager_id or a.manager_id=e.employee_id
     or a.decision<>(case when e.status='rejected' then 'rejected' else 'approved' end) then
     raise exception 'Expense status requires a matching manager decision.' using errcode='23514';
   end if;
 elsif a.id is not null then raise exception 'An undecided expense cannot have a manager decision.' using errcode='23514'; end if;
 if t.id is not null and t.employee_id<>e.employee_id then raise exception 'Ticket owner must match the expense owner.' using errcode='23514'; end if;
 if e.status in ('approved','processing','paid') then
   if t.id is null or (e.status='paid' and t.status<>'closed') or (e.status='processing' and t.status<>'submitted')
     or (e.status='approved' and t.status not in ('awaiting_details','submitted')) then
     raise exception 'Reimbursement ticket does not match the expense status.' using errcode='23514';
   end if;
   if t.status='submitted' and not exists(select 1 from expense_private.bank_details b where b.ticket_id=t.id) then
     raise exception 'Submitted ticket requires saved bank details.' using errcode='23514';
   end if;
 end if;
 if e.status in ('processing','paid') then
   if r.id is null or r.status<>e.status::text or r.amount<>e.amount then raise exception 'Reimbursement amount and status must match the expense.' using errcode='23514'; end if;
 elsif r.id is not null then raise exception 'This expense cannot have a reimbursement yet.' using errcode='23514'; end if;
end; $$;
create function expense_private.expense_consistency_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_id uuid; new_id uuid;
begin
 if tg_op<>'INSERT' then old_id:=(to_jsonb(old)->>case when tg_table_name='expenses' then 'id' else 'expense_id' end)::uuid; end if;
 if tg_op<>'DELETE' then new_id:=(to_jsonb(new)->>case when tg_table_name='expenses' then 'id' else 'expense_id' end)::uuid; end if;
 if old_id is not null then perform expense_private.check_expense_consistency(old_id); end if;
 if new_id is not null and new_id is distinct from old_id then perform expense_private.check_expense_consistency(new_id); end if;
 return null;
end; $$;
revoke all on function expense_private.check_expense_consistency(uuid),expense_private.expense_consistency_trigger() from public,anon,authenticated;
create constraint trigger expense_consistency after insert or update or delete on public.expenses deferrable initially deferred for each row execute function expense_private.expense_consistency_trigger();
create constraint trigger approval_consistency after insert or update or delete on public.approvals deferrable initially deferred for each row execute function expense_private.expense_consistency_trigger();
create constraint trigger reimbursement_consistency after insert or update or delete on public.reimbursements deferrable initially deferred for each row execute function expense_private.expense_consistency_trigger();
create constraint trigger ticket_consistency after insert or update or delete on public.reimbursement_tickets deferrable initially deferred for each row execute function expense_private.expense_consistency_trigger();

-- Fail this migration rather than silently accepting unknown historical corruption.
do $$ declare x record; begin
 for x in select id from public.expenses loop perform expense_private.check_expense_consistency(x.id); end loop;
end; $$;

commit;
