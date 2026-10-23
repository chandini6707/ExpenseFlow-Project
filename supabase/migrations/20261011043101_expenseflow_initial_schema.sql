-- Run once in a fresh Supabase project. Privileged write functions own all mutations.
begin;
create schema if not exists expense_private;
revoke all on schema expense_private from public, anon, authenticated;
create type public.app_role as enum ('employee','manager','finance','admin');
create type public.expense_status as enum ('draft','pending','flagged','approved','rejected','processing','paid');
create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null check (length(full_name) between 1 and 100),
  email text not null, role public.app_role not null default 'employee',
  department text not null default 'General' check (length(department) <= 100),
  manager_id uuid references public.profiles(id) on delete restrict,
  avatar_url text, created_at timestamptz not null default now(),
  check (manager_id is null or manager_id <> id)
);
create table public.expense_policies (
  id uuid primary key default gen_random_uuid(), category text not null unique,
  maximum_amount numeric(12,2) not null check (maximum_amount > 0),
  active boolean not null default true, updated_at timestamptz not null default now(),
  check (category in ('Travel','Accommodation','Food','Transportation','Office Supplies','Client Meetings','Other'))
);
create table public.expenses (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.profiles(id),
  assigned_manager_id uuid references public.profiles(id),
  title text not null check (length(title) between 1 and 120),
  category text not null references public.expense_policies(category),
  amount numeric(12,2) not null check (amount > 0 and amount <= 10000000),
  expense_date date not null, merchant text not null check (length(merchant) between 1 and 120),
  invoice_number text not null default '' check (length(invoice_number) <= 80),
  purpose text not null default '' check (length(purpose) <= 1000),
  description text not null default '' check (length(description) <= 2000),
  receipt_path text, receipt_hash text check (receipt_hash is null or receipt_hash ~ '^[a-f0-9]{64}$'),
  receipt_name text, receipt_type text,
  verification_status text not null default 'Draft', verification_details jsonb not null default '[]',
  status public.expense_status not null default 'draft',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (assigned_manager_id is null or assigned_manager_id <> employee_id),
  check (status = 'draft' or (receipt_path is not null and receipt_hash is not null and assigned_manager_id is not null and length(purpose) >= 8))
);
create table public.approvals (
  id uuid primary key default gen_random_uuid(), expense_id uuid not null unique references public.expenses(id),
  manager_id uuid not null references public.profiles(id), decision text not null check (decision in ('approved','rejected')),
  comments text not null default '', decision_date timestamptz not null default now()
);
create table public.reimbursements (
  id uuid primary key default gen_random_uuid(), expense_id uuid not null unique references public.expenses(id),
  amount numeric(12,2) not null check (amount > 0), status text not null check (status in ('processing','paid')),
  transaction_reference text, payment_date date, processed_by uuid not null references public.profiles(id),
  updated_at timestamptz not null default now(),
  check (status <> 'paid' or (transaction_reference is not null and length(trim(transaction_reference)) >= 3 and payment_date is not null))
);
create unique index unique_payment_reference on public.reimbursements (lower(transaction_reference)) where transaction_reference is not null;
create table public.notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
  expense_id uuid references public.expenses(id), message text not null,
  is_read boolean not null default false, created_at timestamptz not null default now()
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
  expense_id uuid references public.expenses(id), action text not null, metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index expense_employee_date on public.expenses(employee_id, created_at desc);
create index expense_manager_status on public.expenses(assigned_manager_id, status);
create index expense_finance_status on public.expenses(status, expense_date);
create index expense_receipt_hash on public.expenses(receipt_hash) where receipt_hash is not null;
create index expense_similarity on public.expenses(employee_id, expense_date, amount, lower(merchant));
create index profiles_manager on public.profiles(manager_id);
create index notification_user_unread on public.notifications(user_id, is_read, created_at desc);
create index audit_expense_date on public.audit_logs(expense_id, created_at);

-- Never use user-editable auth metadata to assign privileged roles.
create function expense_private.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name, email, avatar_url)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1),'Employee'),100),coalesce(new.email,''),
    case when new.raw_user_meta_data->>'avatar_url' like 'https://%' then new.raw_user_meta_data->>'avatar_url' else null end);
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function expense_private.new_profile();
-- Accounts created before the schema was installed also need employee profiles.
-- Never import role or manager assignments from user-editable Auth metadata.
insert into public.profiles(id, full_name, email, avatar_url)
select u.id,
  left(coalesce(nullif(trim(u.raw_user_meta_data->>'full_name'),''),split_part(u.email,'@',1),'Employee'),100),
  coalesce(u.email,''),
  case when u.raw_user_meta_data->>'avatar_url' like 'https://%' then u.raw_user_meta_data->>'avatar_url' else null end
from auth.users u on conflict(id) do nothing;
create function expense_private.role_of(p_user uuid) returns public.app_role language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = p_user;
$$;
create function expense_private.can_read_expense(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.expenses e where e.id=p_id and (
   e.employee_id=auth.uid() or expense_private.role_of(auth.uid())='admin'
   or (expense_private.role_of(auth.uid())='manager' and e.assigned_manager_id=auth.uid() and e.status <> 'draft')
   or (expense_private.role_of(auth.uid())='finance' and e.status in ('approved','processing','paid'))
 ));
$$;
create function expense_private.event(p_actor uuid,p_expense uuid,p_action text,p_metadata jsonb default '{}') returns void language plpgsql security definer set search_path = '' as $$
begin
 insert into public.audit_logs(actor_id,expense_id,action,metadata) values(p_actor,p_expense,p_action,p_metadata);
end; $$;
create function expense_private.notify(p_user uuid,p_expense uuid,p_message text) returns void language plpgsql security definer set search_path = '' as $$
begin
 if p_user is not null then insert into public.notifications(user_id,expense_id,message) values(p_user,p_expense,p_message); end if;
end; $$;

alter table public.profiles enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_policies enable row level security;
alter table public.approvals enable row level security;
alter table public.reimbursements enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;
grant usage on schema expense_private to authenticated;
grant execute on function expense_private.role_of(uuid), expense_private.can_read_expense(uuid) to authenticated;
create policy profiles_read on public.profiles for select to authenticated using (
 id=auth.uid() or expense_private.role_of(auth.uid())='admin'
 or (expense_private.role_of(auth.uid())='manager' and manager_id=auth.uid())
 or exists(select 1 from public.expenses e where e.employee_id=profiles.id and expense_private.can_read_expense(e.id))
);
create policy expenses_read on public.expenses for select to authenticated using(expense_private.can_read_expense(id));
create policy policies_read on public.expense_policies for select to authenticated using(true);
create policy approvals_read on public.approvals for select to authenticated using(expense_private.can_read_expense(expense_id));
create policy reimbursements_read on public.reimbursements for select to authenticated using(expense_private.can_read_expense(expense_id));
create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy audits_read on public.audit_logs for select to authenticated using(expense_private.role_of(auth.uid())='admin' or (expense_id is not null and expense_private.can_read_expense(expense_id)));
revoke all on public.profiles,public.expenses,public.expense_policies,public.approvals,public.reimbursements,public.notifications,public.audit_logs from anon, authenticated;
grant select on public.profiles,public.expenses,public.expense_policies,public.approvals,public.reimbursements,public.notifications,public.audit_logs to authenticated;
grant all on public.profiles,public.expenses,public.expense_policies,public.approvals,public.reimbursements,public.notifications,public.audit_logs to service_role;

-- Only the authenticated Edge Function's service client may call this writer.
-- The Edge Function downloads or accepts the actual bytes and hashes them itself.
create function public.save_expense_verified(p_actor uuid,p_id uuid,p_payload jsonb,p_submit boolean,
  p_receipt_path text,p_receipt_hash text,p_receipt_name text,p_receipt_type text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
 old public.expenses; person public.profiles; pol public.expense_policies; flags jsonb := '[]';
 v_category text := p_payload->>'category'; v_amount numeric; v_date date; v_merchant text := trim(p_payload->>'merchant');
 v_title text := trim(p_payload->>'title'); v_purpose text := trim(coalesce(p_payload->>'purpose','')); v_invoice text := trim(coalesce(p_payload->>'invoice_number',''));
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
   receipt_path,receipt_hash,receipt_name,receipt_type,verification_status,verification_details,status)
 values(p_id,p_actor,case when p_submit then person.manager_id else null end,v_title,v_category,v_amount,v_date,v_merchant,v_invoice,v_purpose,coalesce(p_payload->>'description',''),
   p_receipt_path,p_receipt_hash,p_receipt_name,p_receipt_type,v_summary,flags,v_status)
 on conflict(id) do update set assigned_manager_id=excluded.assigned_manager_id,title=excluded.title,category=excluded.category,amount=excluded.amount,
 expense_date=excluded.expense_date,merchant=excluded.merchant,invoice_number=excluded.invoice_number,purpose=excluded.purpose,description=excluded.description,
 receipt_path=excluded.receipt_path,receipt_hash=excluded.receipt_hash,receipt_name=excluded.receipt_name,receipt_type=excluded.receipt_type,
 verification_status=excluded.verification_status,verification_details=excluded.verification_details,status=excluded.status,updated_at=now();
 perform expense_private.event(p_actor,p_id,case when p_submit then 'Expense submitted' else 'Draft saved' end,jsonb_build_object('status',v_status,'verification',v_summary));
 if p_submit then
   perform expense_private.notify(p_actor,p_id,case when v_status='flagged' then 'Your claim was submitted and flagged for review.' else 'Your claim was submitted for manager approval.' end);
   perform expense_private.notify(person.manager_id,p_id,'New expense from '||person.full_name||': '||v_title);
 end if;
 return p_id;
end; $$;
revoke all on function public.save_expense_verified(uuid,uuid,jsonb,boolean,text,text,text,text) from public,anon,authenticated;
grant execute on function public.save_expense_verified(uuid,uuid,jsonb,boolean,text,text,text,text) to service_role;

create function public.review_expense(p_id uuid,p_decision text,p_comments text default '') returns void language plpgsql security definer set search_path = '' as $$
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
 if p_decision='approved' then for f in select id from public.profiles where role='finance' loop
   perform expense_private.notify(f.id,p_id,'Approved expense ready for reimbursement: '||e.title);
 end loop; end if;
end; $$;
create function public.process_reimbursement(p_id uuid,p_action text,p_reference text default '',p_payment_date date default null) returns void language plpgsql security definer set search_path = '' as $$
declare e public.expenses;
begin
 if expense_private.role_of(auth.uid()) is distinct from 'finance' then raise exception 'Finance access required.'; end if;
 select * into e from public.expenses where id=p_id for update;
 if not found then raise exception 'Expense not found.'; end if;
 if p_action='processing' and e.status='approved' then
   insert into public.reimbursements(expense_id,amount,status,processed_by) values(p_id,e.amount,'processing',auth.uid());
 elsif p_action='paid' and e.status='processing' then
   if p_reference is null or length(trim(p_reference)) not between 3 and 120 or p_payment_date is null or p_payment_date>current_date or p_payment_date<e.expense_date then raise exception 'Enter a unique demo reference and a valid payment date on or after the expense date.'; end if;
   update public.reimbursements set status='paid',transaction_reference=trim(p_reference),payment_date=p_payment_date,processed_by=auth.uid(),updated_at=now() where expense_id=p_id and status='processing';
   if not found then raise exception 'Reimbursement record is not processing.'; end if;
 else raise exception 'Invalid transition or reimbursement already processed.'; end if;
 update public.expenses set status=p_action::public.expense_status,updated_at=now() where id=p_id;
 perform expense_private.event(auth.uid(),p_id,case when p_action='paid' then 'Demo reimbursement completed' else 'Reimbursement processing started' end,jsonb_build_object('status',p_action,'reference',trim(p_reference),'simulated',true));
 perform expense_private.notify(e.employee_id,p_id,case when p_action='paid' then 'Your reimbursement was marked completed in the demo. Reference: '||trim(p_reference)||'. No money was transferred.' else 'Finance started processing your reimbursement.' end);
end; $$;
create function public.update_my_profile(p_name text,p_department text) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or length(trim(p_name)) not between 1 and 100 or length(trim(p_department)) not between 1 and 100 then raise exception 'Enter your name and department.'; end if;
 update public.profiles set full_name=trim(p_name),department=trim(p_department) where id=auth.uid();
 perform expense_private.event(auth.uid(),null,'Profile updated');
end; $$;
create function public.mark_notifications_read(p_id uuid default null) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required.'; end if;
 update public.notifications set is_read=true where user_id=auth.uid() and (p_id is null or id=p_id);
end; $$;
create function public.admin_update_user(p_id uuid,p_role public.app_role,p_manager uuid,p_department text) returns void language plpgsql security definer set search_path = '' as $$
declare target public.profiles;
begin
 -- Serialize admin changes so concurrent demotions cannot remove the last admin.
 perform pg_advisory_xact_lock(638122);
 if expense_private.role_of(auth.uid()) is distinct from 'admin' then raise exception 'Administrator access required.'; end if;
 select * into target from public.profiles where id=p_id for update;
 if not found or p_role is null or length(trim(p_department)) not between 1 and 100 then raise exception 'Invalid user or department.'; end if;
 if target.role='admin' and p_role<>'admin' and (select count(*) from public.profiles where role='admin')<=1 then raise exception 'The organization must retain an administrator.'; end if;
 if p_manager is not null and (p_manager=p_id or expense_private.role_of(p_manager) is distinct from 'manager') then raise exception 'Select a different user with the manager role.'; end if;
 if target.role='manager' and p_role<>'manager' and (exists(select 1 from public.profiles where manager_id=p_id) or exists(select 1 from public.expenses where assigned_manager_id=p_id and status in ('pending','flagged'))) then raise exception 'Reassign employees and complete pending reviews before changing this manager role.'; end if;
 update public.profiles set role=p_role,manager_id=case when p_role='employee' then p_manager else null end,department=trim(p_department) where id=p_id;
 perform expense_private.event(auth.uid(),null,'User access updated',jsonb_build_object('user_id',p_id,'role',p_role,'manager_id',p_manager));
end; $$;
create function public.admin_update_policy(p_category text,p_limit numeric,p_active boolean) returns void language plpgsql security definer set search_path = '' as $$
begin
 if expense_private.role_of(auth.uid()) is distinct from 'admin' then raise exception 'Administrator access required.'; end if;
 if p_limit is null or p_limit<=0 or p_limit>10000000 or p_limit<>round(p_limit,2) or p_active is null then raise exception 'Enter a valid policy limit.'; end if;
 update public.expense_policies set maximum_amount=p_limit,active=p_active,updated_at=now() where category=p_category;
 if not found then raise exception 'Policy not found.'; end if;
 perform expense_private.event(auth.uid(),null,'Expense policy updated',jsonb_build_object('category',p_category,'limit',p_limit,'active',p_active));
end; $$;
revoke all on all functions in schema expense_private from public,anon,authenticated;
grant execute on function expense_private.role_of(uuid),expense_private.can_read_expense(uuid) to authenticated;
revoke all on function public.review_expense(uuid,text,text),public.process_reimbursement(uuid,text,text,date),public.update_my_profile(text,text),public.mark_notifications_read(uuid),public.admin_update_user(uuid,public.app_role,uuid,text),public.admin_update_policy(text,numeric,boolean) from public,anon;
grant execute on function public.review_expense(uuid,text,text),public.process_reimbursement(uuid,text,text,date),public.update_my_profile(text,text),public.mark_notifications_read(uuid),public.admin_update_user(uuid,public.app_role,uuid,text),public.admin_update_policy(text,numeric,boolean) to authenticated;

insert into public.expense_policies(category,maximum_amount) values
 ('Travel',5000),('Accommodation',3000),('Food',1000),('Transportation',2000),('Office Supplies',5000),('Client Meetings',2500),('Other',2000);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('receipts','receipts',false,5242880,array['image/jpeg','image/png','application/pdf'])
 on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
-- No client INSERT / UPDATE / DELETE storage policies: receipts are written only by the Edge Function.
create policy expenseflow_receipt_read on storage.objects for select to authenticated using
 (bucket_id='receipts' and exists(select 1 from public.expenses e where e.receipt_path=name and expense_private.can_read_expense(e.id)));

-- Realtime delivers only rows the caller is permitted to select under RLS.
do $$ declare tab text; begin
 foreach tab in array array['expenses','notifications'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=tab) then
     execute format('alter publication supabase_realtime add table public.%I',tab);
   end if;
 end loop;
end; $$;
commit;
