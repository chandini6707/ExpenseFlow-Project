-- Real RLS/role/profile tests. Fixtures and changes are rolled back.
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('30000000-0000-4000-8000-000000000001','profile-test-1@example.com','{"full_name":"Profile test","requested_role":"manager","role":"admin"}'),
 ('30000000-0000-4000-8000-000000000002','profile-test-2@example.com','{"full_name":"Other profile","requested_role":"finance"}'),
 ('30000000-0000-4000-8000-000000000003','profile-test-admin@example.com','{"full_name":"Profile admin"}');
update public.profiles set role='admin' where id='30000000-0000-4000-8000-000000000003';
insert into storage.objects(bucket_id,name,metadata) values('profile-avatars','30000000-0000-4000-8000-000000000001/test.png','{"mimetype":"image/png","size":200}');
set local role authenticated;
select set_config('request.jwt.claim.sub','30000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select role from public.profiles where id=auth.uid())<>'employee' then raise exception 'FAIL: request granted privileges'; end if;
 if (select role_request_status from public.profiles where id=auth.uid())<>'pending' then raise exception 'FAIL: request not saved'; end if;
 if exists(select 1 from public.profiles where id<>auth.uid()) then raise exception 'FAIL: private profile exposed'; end if;
 if public.profile_directory()::text like '%"phone"%' then raise exception 'FAIL: private directory field'; end if;
 perform public.save_my_profile('{"full_name":"Updated profile","phone":"+91 9000000000","job_title":"Analyst","cost_centre":"DEMO","avatar_path":"30000000-0000-4000-8000-000000000001/test.png"}');
 if (select phone from public.profiles where id=auth.uid())<>'+91 9000000000' then raise exception 'FAIL: profile persistence'; end if;
 begin perform public.save_my_profile('{"role":"admin"}');raise exception 'FAIL: role mutation';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.save_my_profile('{"id":"30000000-0000-4000-8000-000000000002"}');raise exception 'FAIL: owner mutation';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.save_my_profile('{"manager_id":null}');raise exception 'FAIL: manager mutation';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.save_my_profile('{"managed_team":"Unauthorized"}');raise exception 'FAIL: irrelevant field';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.save_my_profile('{"avatar_path":"30000000-0000-4000-8000-000000000002/test.png"}');raise exception 'FAIL: avatar ownership';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.save_my_profile('{"phone":"not-a-number"}');raise exception 'FAIL: invalid phone';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin update public.profiles set role='admin' where id=auth.uid();raise exception 'FAIL: direct role update';exception when insufficient_privilege then null;end;
 begin perform public.review_role_request(auth.uid(),'approved','manager','');raise exception 'FAIL: self approval';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end; $$;
select set_config('request.jwt.claim.sub','30000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='profile-avatars') then raise exception 'FAIL: another user avatar readable';end if;
 begin insert into storage.objects(bucket_id,name) values('profile-avatars','30000000-0000-4000-8000-000000000001/bad.png');raise exception 'FAIL: another user upload';exception when insufficient_privilege then null;end;
end; $$;
select set_config('request.jwt.claim.sub','30000000-0000-4000-8000-000000000003',true);
do $$ begin
 if not exists(select 1 from jsonb_array_elements(public.profile_directory()) p where p->>'role_request_status'='pending' and p->>'requested_role'='manager') then raise exception 'FAIL: admin queue';end if;
 perform public.review_role_request('30000000-0000-4000-8000-000000000001','approved','manager','Trusted review');
 perform public.review_role_request('30000000-0000-4000-8000-000000000002','rejected','finance','Employee access is appropriate.');
 begin perform public.review_role_request('30000000-0000-4000-8000-000000000001','approved','manager','');raise exception 'FAIL: duplicate review';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 if exists(select 1 from public.profiles where id<>auth.uid()) then raise exception 'FAIL: private contact access for admin';end if;
end; $$;
select set_config('request.jwt.claim.sub','30000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select role from public.profiles where id=auth.uid())<>'manager' or (select role_request_status from public.profiles where id=auth.uid())<>'approved' then raise exception 'FAIL: approved role not saved';end if;
 perform public.save_my_profile('{"managed_team":"Engineering","avatar_path":null}');
 if (select avatar_path from public.profiles where id=auth.uid()) is not null then raise exception 'FAIL: picture removal';end if;
 if not exists(select 1 from public.notifications where user_id=auth.uid()) then raise exception 'FAIL: missing access notification';end if;
end; $$;
select set_config('request.jwt.claim.sub','30000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select role from public.profiles where id=auth.uid())<>'employee' or (select role_request_status from public.profiles where id=auth.uid())<>'rejected' then raise exception 'FAIL: rejection changed role';end if;
end; $$;
reset role;
rollback;
select 'Profile ownership, requests, approvals, validation, avatar RLS and private directory checks passed; fixtures rolled back.' as result;
