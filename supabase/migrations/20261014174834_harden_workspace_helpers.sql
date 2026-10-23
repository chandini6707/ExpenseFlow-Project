-- Preserve existing RPC names while keeping privileged implementations out of public.
-- No table, user, authentication or workflow status changes.
begin;
create or replace function expense_private.admin_update_policy(p_category text,p_limit numeric,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or expense_private.role_of(auth.uid()) is distinct from 'admin' then raise exception 'Administrator access required.'; end if;
 if p_limit is null or p_limit<=0 or p_limit>10000000 or p_limit<>round(p_limit,2) or p_active is null then raise exception 'Enter a valid policy limit.'; end if;
 update public.expense_policies set maximum_amount=p_limit,active=p_active,updated_at=now() where category=p_category;
 if not found then raise exception 'Policy not found.'; end if;
 perform expense_private.event(auth.uid(),null,'Expense policy updated',jsonb_build_object('category',p_category,'limit',p_limit,'active',p_active));
end; $$;
create or replace function public.admin_update_policy(p_category text,p_limit numeric,p_active boolean)
returns void language sql security invoker set search_path='' as $$
 select expense_private.admin_update_policy(p_category,p_limit,p_active);
$$;
create or replace function expense_private.mark_notifications_read(p_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required.'; end if;
 update public.notifications set is_read=true where user_id=auth.uid() and not is_read and (p_id is null or id=p_id);
end; $$;
create or replace function public.mark_notifications_read(p_id uuid default null)
returns void language sql security invoker set search_path='' as $$
 select expense_private.mark_notifications_read(p_id);
$$;
-- Older clients keep this compatibility endpoint; the current profile validator owns writes.
create or replace function public.update_my_profile(p_name text,p_department text)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if p_name is null or p_department is null or length(trim(p_name)) not between 1 and 100 or length(trim(p_department)) not between 1 and 100 then raise exception 'Enter your name and department.'; end if;
 perform expense_private.save_my_profile(jsonb_build_object('full_name',trim(p_name),'department',trim(p_department)));
end; $$;
revoke all on function expense_private.admin_update_policy(text,numeric,boolean),expense_private.mark_notifications_read(uuid) from public,anon;
revoke all on function public.admin_update_policy(text,numeric,boolean),public.mark_notifications_read(uuid),public.update_my_profile(text,text) from public,anon;
grant execute on function expense_private.admin_update_policy(text,numeric,boolean),expense_private.mark_notifications_read(uuid) to authenticated;
grant execute on function public.admin_update_policy(text,numeric,boolean),public.mark_notifications_read(uuid),public.update_my_profile(text,text) to authenticated;
-- Supabase's optional platform event trigger must not be exposed as a client RPC.
-- Revoking API execution does not remove or disable the database DDL trigger.
do $$ begin
 if to_regprocedure('public.rls_auto_enable()') is not null then
  execute 'revoke execute on function public.rls_auto_enable() from public,anon,authenticated';
 end if;
end; $$;
commit;
