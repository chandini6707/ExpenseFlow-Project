-- Extend the existing profile; role requests never grant permissions.
begin;
alter table public.profiles
 add column phone text not null default '' check (length(phone)<=30),
 add column job_title text not null default '' check (length(job_title)<=100),
 add column employee_code text generated always as ('EF-'||upper(substr(replace(id::text,'-',''),1,12))) stored,
 add column cost_centre text not null default '' check (length(cost_centre)<=80),
 add column managed_team text not null default '' check (length(managed_team)<=120),
 add column finance_responsibilities text not null default '' check (length(finance_responsibilities)<=500),
 add column avatar_path text,
 add column requested_role public.app_role,
 add column role_request_status text check (role_request_status in ('pending','approved','rejected')),
 add column role_requested_at timestamptz,
 add column role_reviewed_at timestamptz,
 add column role_reviewed_by uuid references public.profiles(id),
 add column role_review_comment text not null default '' check (length(role_review_comment)<=500),
 add column updated_at timestamptz not null default now(),
 add constraint requested_role_allowed check (requested_role is null or requested_role in ('employee','manager','finance')),
 add constraint avatar_owned_path check (avatar_path is null or avatar_path like id::text||'/%');
create index profiles_pending_role_requests on public.profiles(role_requested_at) where role_request_status='pending';
create index profiles_role_reviewer on public.profiles(role_reviewed_by) where role_reviewed_by is not null;

create or replace function expense_private.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare requested public.app_role;
begin
 requested := case when new.raw_user_meta_data->>'requested_role' in ('manager','finance') then (new.raw_user_meta_data->>'requested_role')::public.app_role else 'employee' end;
 insert into public.profiles(id,full_name,email,avatar_url,role,requested_role,role_request_status,role_requested_at)
 values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1),'Employee'),100),coalesce(new.email,''),
 case when new.raw_user_meta_data->>'avatar_url' like 'https://%' then new.raw_user_meta_data->>'avatar_url' else null end,
 'employee',requested,case when requested='employee' then 'approved' else 'pending' end,now());
 return new;
end; $$;

-- Full profiles (including contact information) are visible only to their owner.
-- The existing role/assignment/expense visibility is retained in a SAFE directory RPC.
drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create function expense_private.profile_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid := auth.uid(); actor_role public.app_role;
begin
 if actor is null then raise exception 'Sign in required.'; end if;
 actor_role := expense_private.role_of(actor);
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role,'department',p.department,
 'manager_id',p.manager_id,'employee_code',p.employee_code,'job_title',p.job_title,'created_at',p.created_at,
 'email',case when actor_role='admin' or p.id=actor then p.email else null end)
 || case when actor_role='admin' then jsonb_build_object('requested_role',p.requested_role,'role_request_status',p.role_request_status,'role_requested_at',p.role_requested_at) else '{}'::jsonb end
 order by p.full_name,p.id) from public.profiles p where p.id=actor or actor_role='admin'
 or (actor_role='manager' and p.manager_id=actor)
 or p.id=(select manager_id from public.profiles where id=actor)
 or exists(select 1 from public.expenses e where e.employee_id=p.id and expense_private.can_read_expense(e.id))),'[]'::jsonb);
end; $$;
create function public.profile_directory() returns jsonb language sql security invoker set search_path='' as $$ select expense_private.profile_directory(); $$;

create function expense_private.save_my_profile(p_fields jsonb) returns void language plpgsql security definer set search_path='' as $$
declare person public.profiles; k text; v text; image_path text;
begin
 if auth.uid() is null then raise exception 'Sign in required.'; end if;
 select * into person from public.profiles where id=auth.uid() for update;
 if not found then raise exception 'Profile not found.'; end if;
 if p_fields is null or jsonb_typeof(p_fields)<>'object' then raise exception 'Invalid profile details.'; end if;
 for k,v in select * from jsonb_each_text(p_fields) loop
   if k not in ('full_name','department','phone','job_title','cost_centre','managed_team','finance_responsibilities','avatar_path') then raise exception 'This profile field cannot be changed.'; end if;
   if k in ('full_name','department') and (v is null or length(trim(v)) not between 1 and 100) then raise exception 'Enter your full name and department (1–100 characters).'; end if;
   if k='phone' and (v is null or (v<>'' and v !~ '^[+0-9 ()-]{7,30}$')) then raise exception 'Enter a valid phone number.'; end if;
   if k<>'avatar_path' and v is null then raise exception 'Invalid profile field.'; end if;
   if (k='cost_centre' and person.role<>'employee') or (k='managed_team' and person.role<>'manager') or (k='finance_responsibilities' and person.role<>'finance') then raise exception 'This field is not available for your authorized role.'; end if;
 end loop;
 image_path := case when p_fields ? 'avatar_path' then p_fields->>'avatar_path' else person.avatar_path end;
 if image_path is not null and (image_path not like person.id::text||'/%' or not exists(
   select 1 from storage.objects where bucket_id='profile-avatars' and name=image_path
   and metadata->>'mimetype' in ('image/jpeg','image/png') and (metadata->>'size')::bigint between 1 and 2097152
 )) then raise exception 'Upload a valid JPG or PNG profile picture first.'; end if;
 update public.profiles set full_name=coalesce(trim(p_fields->>'full_name'),full_name),department=coalesce(trim(p_fields->>'department'),department),
 phone=coalesce(trim(p_fields->>'phone'),phone),job_title=coalesce(trim(p_fields->>'job_title'),job_title),cost_centre=coalesce(trim(p_fields->>'cost_centre'),cost_centre),
 managed_team=coalesce(trim(p_fields->>'managed_team'),managed_team),finance_responsibilities=coalesce(trim(p_fields->>'finance_responsibilities'),finance_responsibilities),
 avatar_path=image_path,avatar_url=case when p_fields ? 'avatar_path' then null else avatar_url end,updated_at=now() where id=person.id;
 perform expense_private.event(person.id,null,'Profile updated');
end; $$;
create function public.save_my_profile(p_fields jsonb) returns void language sql security invoker set search_path='' as $$ select expense_private.save_my_profile(p_fields); $$;

create function expense_private.request_workspace_role(p_role public.app_role) returns void language plpgsql security definer set search_path='' as $$
declare person public.profiles;
begin
 if auth.uid() is null then raise exception 'Sign in required.'; end if;
 select * into person from public.profiles where id=auth.uid() for update;
 if not found or person.role<>'employee' then raise exception 'Contact an administrator to change your assigned role.'; end if;
 if p_role is null or p_role not in ('employee','manager','finance') then raise exception 'Invalid requested role.'; end if;
 -- Callback retries cannot reopen a reviewed request or alter a pending request.
 if person.requested_role=p_role then return; end if;
 if person.role_request_status='pending' then raise exception 'Your existing role request is awaiting administrator review.'; end if;
 update public.profiles set requested_role=p_role,role_request_status=case when p_role='employee' then 'approved' else 'pending' end,
 role_requested_at=now(),role_reviewed_at=null,role_reviewed_by=null,role_review_comment='',updated_at=now() where id=person.id;
 perform expense_private.event(person.id,null,'Workspace role requested',jsonb_build_object('requested_role',p_role));
end; $$;
create function public.request_workspace_role(p_role public.app_role) returns void language sql security invoker set search_path='' as $$ select expense_private.request_workspace_role(p_role); $$;

-- Preserve all existing assignment, last-admin and manager-demotion safeguards.
create function expense_private.admin_update_user(p_id uuid,p_role public.app_role,p_manager uuid,p_department text) returns void language plpgsql security definer set search_path='' as $$
declare target public.profiles;
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
 perform expense_private.event(auth.uid(),null,'User access updated',jsonb_build_object('user_id',p_id,'role',p_role,'manager_id',p_manager));
 perform expense_private.notify(p_id,null,'Your workspace access was updated. Authorized role: '||p_role||'. Refresh to open your dashboard.');
end; $$;

create or replace function public.admin_update_user(p_id uuid,p_role public.app_role,p_manager uuid,p_department text) returns void language sql security invoker set search_path='' as $$ select expense_private.admin_update_user(p_id,p_role,p_manager,p_department); $$;
revoke all on function expense_private.admin_update_user(uuid,public.app_role,uuid,text) from public,anon;
grant execute on function expense_private.admin_update_user(uuid,public.app_role,uuid,text) to authenticated;

create function expense_private.review_role_request(p_id uuid,p_decision text,p_expected_role public.app_role,p_comment text default '') returns void language plpgsql security definer set search_path='' as $$
declare person public.profiles;
begin
 perform pg_advisory_xact_lock(638122);
 if auth.uid() is null or expense_private.role_of(auth.uid()) is distinct from 'admin' then raise exception 'Administrator access required.'; end if;
 select * into person from public.profiles where id=p_id for update;
 if not found or person.role_request_status is distinct from 'pending' or person.requested_role is distinct from p_expected_role then raise exception 'This request changed or was already reviewed. Refresh the page.'; end if;
 if p_decision is null or p_decision not in ('approved','rejected') or p_comment is null or length(p_comment)>500 then raise exception 'Invalid review decision.'; end if;
 if p_decision='rejected' and length(trim(p_comment))<5 then raise exception 'Give a reason for rejecting this role request.'; end if;
 if p_decision='approved' then perform public.admin_update_user(p_id,person.requested_role,null,person.department);
 else perform expense_private.notify(p_id,null,'Your workspace role request was declined: '||trim(p_comment)); end if;
 update public.profiles set role_request_status=p_decision,role_reviewed_at=now(),role_reviewed_by=auth.uid(),role_review_comment=trim(p_comment),updated_at=now() where id=p_id;
 perform expense_private.event(auth.uid(),null,'Role request '||p_decision,jsonb_build_object('user_id',p_id,'requested_role',person.requested_role));
end; $$;
create function public.review_role_request(p_id uuid,p_decision text,p_expected_role public.app_role,p_comment text default '') returns void language sql security invoker set search_path='' as $$ select expense_private.review_role_request(p_id,p_decision,p_expected_role,p_comment); $$;

revoke all on function expense_private.profile_directory(),expense_private.save_my_profile(jsonb),expense_private.request_workspace_role(public.app_role),expense_private.review_role_request(uuid,text,public.app_role,text) from public,anon;
revoke all on function public.profile_directory(),public.save_my_profile(jsonb),public.request_workspace_role(public.app_role),public.review_role_request(uuid,text,public.app_role,text) from public,anon;
grant execute on function expense_private.profile_directory(),expense_private.save_my_profile(jsonb),expense_private.request_workspace_role(public.app_role),expense_private.review_role_request(uuid,text,public.app_role,text) to authenticated;
grant execute on function public.profile_directory(),public.save_my_profile(jsonb),public.request_workspace_role(public.app_role),public.review_role_request(uuid,text,public.app_role,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('profile-avatars','profile-avatars',false,2097152,array['image/jpeg','image/png']);
create policy expenseflow_avatar_read on storage.objects for select to authenticated using(bucket_id='profile-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy expenseflow_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='profile-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy expenseflow_avatar_delete on storage.objects for delete to authenticated using(bucket_id='profile-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
commit;
