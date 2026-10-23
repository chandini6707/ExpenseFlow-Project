-- Complete unassigned-employee workflow using real SQL/RLS; no persistent test data.
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('40000000-0000-4000-8000-000000000001','unassigned-e@example.com','{"full_name":"Unassigned employee","requested_role":"manager"}'),
 ('40000000-0000-4000-8000-000000000002','unassigned-m1@example.com','{"full_name":"Assigned reviewer"}'),
 ('40000000-0000-4000-8000-000000000003','unassigned-m2@example.com','{"full_name":"Other reviewer"}'),
 ('40000000-0000-4000-8000-000000000004','unassigned-a@example.com','{"full_name":"Trusted administrator"}'),
 ('40000000-0000-4000-8000-000000000005','unassigned-f@example.com','{"full_name":"Finance reviewer"}');
update public.profiles set role='manager' where id in ('40000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003');
update public.profiles set role='admin' where id='40000000-0000-4000-8000-000000000004';
update public.profiles set role='finance' where id='40000000-0000-4000-8000-000000000005';
do $$ begin
 if not exists(select 1 from public.profiles where id='40000000-0000-4000-8000-000000000001' and role='employee' and manager_id is null and role_request_status='pending') then raise exception 'FAIL: fixture is not an unapproved ordinary employee'; end if;
end; $$;
insert into storage.objects(bucket_id,name) values
 ('receipts','40000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000001/receipt.png'),
 ('receipts','40000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000002/receipt.png'),
 ('receipts','40000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000003/receipt.png');
-- This is the trusted writer used only after Edge Auth.getUser verifies the employee.
set local role service_role;
select public.save_expense_verified('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',
 jsonb_build_object('title','Unassigned travel','merchant','Rail test','category','Travel','amount',275.55,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date,'assigned_manager_id','40000000-0000-4000-8000-000000000003'),true,
 '40000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000001/receipt.png',repeat('f',64),'receipt.png','image/png');
select public.save_expense_verified('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002',
 jsonb_build_object('title','Second unassigned travel','merchant','Rail test two','category','Travel','amount',125.25,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,
 '40000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000002/receipt.png',repeat('d',64),'receipt.png','image/png');
do $$ begin
 begin
   perform public.save_expense_verified('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000004',
     jsonb_build_object('title','Missing proof','merchant','Test','category','Travel','amount',1,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,null,null,null,null);
   raise exception 'FAIL: missing receipt accepted';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
reset role;
set constraints all immediate;
set constraints all deferred;

set local role authenticated;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',true);
do $$ declare row_data jsonb; begin
 row_data:=public.expense_workspace('50000000-0000-4000-8000-000000000001')->'expenses'->0;
 if row_data->>'status'<>'pending' or row_data->>'assigned_manager_id' is not null or (row_data->>'amount')::numeric<>275.55 then raise exception 'FAIL: unassigned submission was not saved correctly'; end if;
 if not exists(select 1 from storage.objects where name=row_data->>'receipt_path') then raise exception 'FAIL: employee lost receipt access'; end if;
 if not exists(select 1 from public.notifications where expense_id='50000000-0000-4000-8000-000000000001' and message like '%No manager is assigned%') then raise exception 'FAIL: missing assignment warning'; end if;
 begin perform public.admin_update_user(auth.uid(),'employee','40000000-0000-4000-8000-000000000002','Test');raise exception 'FAIL: employee self-assignment';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if;end;
 begin perform public.review_expense('50000000-0000-4000-8000-000000000001','approved','Self approval denied.');raise exception 'FAIL: employee gained manager permissions';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if;end;
 begin update public.expenses set assigned_manager_id='40000000-0000-4000-8000-000000000002' where id='50000000-0000-4000-8000-000000000001';raise exception 'FAIL: direct reassignment';exception when insufficient_privilege then null;end;
end; $$;

-- Neither manager can read, download evidence or approve an unassigned claim.
do $$ declare actor text; begin
 foreach actor in array array['40000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003'] loop
   perform set_config('request.jwt.claim.sub',actor,true);
   if jsonb_array_length(public.expense_workspace('50000000-0000-4000-8000-000000000001')->'expenses')<>0 then raise exception 'FAIL: unassigned manager can read'; end if;
   if exists(select 1 from storage.objects where name like '40000000-0000-4000-8000-000000000001/%') then raise exception 'FAIL: unassigned manager sees receipt'; end if;
   begin perform public.review_expense('50000000-0000-4000-8000-000000000001','approved','Attempt before assignment');raise exception 'FAIL: unassigned approval';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if;end;
 end loop;
end; $$;

select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000004',true);
select public.admin_update_user('40000000-0000-4000-8000-000000000001','employee','40000000-0000-4000-8000-000000000002','Engineering');
select public.admin_update_user('40000000-0000-4000-8000-000000000001','employee','40000000-0000-4000-8000-000000000002','Engineering');
do $$ begin
 if (select count(*) from public.expenses where employee_id='40000000-0000-4000-8000-000000000001' and assigned_manager_id='40000000-0000-4000-8000-000000000002' and status='pending')<>2 then raise exception 'FAIL: pending claims not routed'; end if;
 if (select count(*) from public.audit_logs where expense_id='50000000-0000-4000-8000-000000000001' and action='Expense manager assignment updated')<>1 then raise exception 'FAIL: duplicate or missing assignment audit'; end if;
end; $$;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.review_expense('50000000-0000-4000-8000-000000000001','approved','Different manager attempt');raise exception 'FAIL: other manager approval';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if;end;
end; $$;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000002',true);
select public.review_expense('50000000-0000-4000-8000-000000000001','approved','Purchase receipt checked.');
select public.review_expense('50000000-0000-4000-8000-000000000002','rejected','Business purpose not accepted.');

select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',true);
do $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='employee' and role_request_status='pending') then raise exception 'FAIL: employee was promoted to submit'; end if;
end; $$;
select public.submit_bank_details('50000000-0000-4000-8000-000000000001','Test Employee','Demo Bank','000000123456','000000123456','TEST0000001');
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000005',true);
select public.process_reimbursement('50000000-0000-4000-8000-000000000001','processing');
select public.process_reimbursement('50000000-0000-4000-8000-000000000001','paid','UNASSIGNED-ROLLBACK-TEST',current_date);
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',true);
do $$ declare row_data jsonb; begin
 row_data:=public.expense_workspace('50000000-0000-4000-8000-000000000001')->'expenses'->0;
 if row_data->>'status'<>'paid' or row_data->'ticket'->>'status'<>'closed' or row_data->'reimbursements'->0->>'status'<>'paid' then raise exception 'FAIL: completed workflow mismatch'; end if;
 if public.expense_workspace('50000000-0000-4000-8000-000000000002')->'expenses'->0->>'status'<>'rejected' then raise exception 'FAIL: rejection not saved'; end if;
end; $$;

-- Reassignment moves only open claims and preserves completed decisions/history.
reset role;
set local role service_role;
select public.save_expense_verified('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000003',
 jsonb_build_object('title','Later pending travel','merchant','Later rail test','category','Travel','amount',99.99,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,
 '40000000-0000-4000-8000-000000000001/50000000-0000-4000-8000-000000000003/receipt.png',repeat('e',64),'receipt.png','image/png');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000004',true);
select public.admin_update_user('40000000-0000-4000-8000-000000000001','employee','40000000-0000-4000-8000-000000000003','Engineering');
do $$ begin
 if (select assigned_manager_id from public.expenses where id='50000000-0000-4000-8000-000000000003')<>'40000000-0000-4000-8000-000000000003'::uuid then raise exception 'FAIL: pending claim not reassigned'; end if;
 if exists(select 1 from public.expenses where id in ('50000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002') and assigned_manager_id<>'40000000-0000-4000-8000-000000000002'::uuid) then raise exception 'FAIL: historic decision reassigned'; end if;
end; $$;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000002',true);
do $$ begin
 if jsonb_array_length(public.expense_workspace('50000000-0000-4000-8000-000000000003')->'expenses')<>0 then raise exception 'FAIL: former manager still sees open claim'; end if;
 begin perform public.review_expense('50000000-0000-4000-8000-000000000003','approved','Old manager attempt');raise exception 'FAIL: former manager review';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if;end;
end; $$;
reset role;
set constraints all immediate;
rollback;
select 'Unassigned employee submission, warnings, receipt access, later admin assignment, manager isolation, approval/rejection and reimbursement passed; all fixtures rolled back.' as result;
