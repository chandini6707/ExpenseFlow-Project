-- Authorization and backwards compatibility for existing helper RPCs.
-- Temporary fixtures and policy edits are all rolled back, including notifications/audit events.
begin;
do $$ begin
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and has_function_privilege('authenticated',p.oid,'execute')) then raise exception 'FAIL: public definer executable by authenticated';end if;
 if has_function_privilege('anon','public.mark_notifications_read(uuid)','execute') or has_function_privilege('anon','public.admin_update_policy(text,numeric,boolean)','execute') or has_function_privilege('anon','public.update_my_profile(text,text)','execute') then raise exception 'FAIL: anonymous helper execution';end if;
end; $$;
insert into auth.users(id,email,raw_user_meta_data) values
 ('60000000-0000-4000-8000-000000000001','helper-employee@example.com','{"full_name":"Helper employee"}'),
 ('60000000-0000-4000-8000-000000000002','helper-other@example.com','{"full_name":"Other employee"}'),
 ('60000000-0000-4000-8000-000000000003','helper-admin@example.com','{"full_name":"Helper admin"}');
update public.profiles set role='admin' where id='60000000-0000-4000-8000-000000000003';
insert into public.notifications(id,user_id,message) values
 ('61000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','Helper notification one'),
 ('61000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001','Helper notification two'),
 ('61000000-0000-4000-8000-000000000003','60000000-0000-4000-8000-000000000002','Other notification');
set local role authenticated;
select set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000001',true);
do $$ begin
 perform public.mark_notifications_read('61000000-0000-4000-8000-000000000001');
 if (select count(*) from public.notifications where is_read and user_id=auth.uid())<>1 then raise exception 'FAIL: individual notification';end if;
 perform public.mark_notifications_read('61000000-0000-4000-8000-000000000003');
 perform public.mark_notifications_read();
 if exists(select 1 from public.notifications where user_id=auth.uid() and not is_read) then raise exception 'FAIL: mark all notifications';end if;
 perform public.update_my_profile('Updated helper','Operations');
 if not exists(select 1 from public.profiles where id=auth.uid() and full_name='Updated helper' and department='Operations' and role='employee' and updated_at is not null) then raise exception 'FAIL: compatibility profile save';end if;
 begin perform public.update_my_profile(null,'Operations');raise exception 'FAIL: accepted null name';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.admin_update_policy('Travel',1,true);raise exception 'FAIL: employee policy override';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end; $$;
select set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select is_read from public.notifications where id='61000000-0000-4000-8000-000000000003') then raise exception 'FAIL: cross-user notification change';end if;
 if (select full_name from public.profiles where id=auth.uid())<>'Other employee' then raise exception 'FAIL: another profile changed';end if;
end; $$;
select set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000003',true);
do $$ begin
 perform public.admin_update_policy('Travel',4321.12,true);
 if (select maximum_amount from public.expense_policies where category='Travel')<>4321.12 then raise exception 'FAIL: trusted policy save';end if;
 begin perform public.admin_update_policy('Travel',0,true);raise exception 'FAIL: zero policy limit';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.admin_update_policy('Missing category',100,true);raise exception 'FAIL: absent policy';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 if not exists(select 1 from public.audit_logs where actor_id=auth.uid() and action='Expense policy updated') then raise exception 'FAIL: missing policy audit';end if;
end; $$;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.mark_notifications_read();raise exception 'FAIL: unauthenticated notifications';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.update_my_profile('Nobody','Operations');raise exception 'FAIL: unauthenticated profile';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.admin_update_policy('Travel',1,true);raise exception 'FAIL: unauthenticated policy';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end; $$;
reset role;
set constraints all immediate;
rollback;
select 'Helper RPC permissions, notification ownership, profile compatibility, policy authorization and auditing passed; fixtures rolled back.' as result;
