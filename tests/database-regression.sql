-- Development database only. Run after the migration with psql -v ON_ERROR_STOP=1.
-- Real PostgreSQL role/RLS/function tests; all fixtures are rolled back.
-- Storage metadata here tests SQL attachment rules, not upload byte transport.
begin;
insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data,aud,role) values
 ('10000000-0000-4000-8000-000000000001','ef-test-e1@example.com','{"full_name":"Test employee","role":"admin"}','{}','authenticated','authenticated'),
 ('10000000-0000-4000-8000-000000000002','ef-test-e2@example.com','{"full_name":"Other employee"}','{}','authenticated','authenticated'),
 ('10000000-0000-4000-8000-000000000003','ef-test-m1@example.com','{"full_name":"Test manager"}','{}','authenticated','authenticated'),
 ('10000000-0000-4000-8000-000000000004','ef-test-m2@example.com','{"full_name":"Other manager"}','{}','authenticated','authenticated'),
 ('10000000-0000-4000-8000-000000000005','ef-test-f@example.com','{"full_name":"Test finance"}','{}','authenticated','authenticated'),
 ('10000000-0000-4000-8000-000000000006','ef-test-a@example.com','{"full_name":"Test admin"}','{}','authenticated','authenticated');
do $$ begin
 if (select role from public.profiles where id='10000000-0000-4000-8000-000000000001')<>'employee' then raise exception 'FAIL: metadata role escalation'; end if;
end; $$;
update public.profiles set role='manager' where id in ('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000004');
update public.profiles set role='finance' where id='10000000-0000-4000-8000-000000000005';
update public.profiles set role='admin' where id='10000000-0000-4000-8000-000000000006';
update public.profiles set manager_id='10000000-0000-4000-8000-000000000003' where id='10000000-0000-4000-8000-000000000001';
update public.profiles set manager_id='10000000-0000-4000-8000-000000000004' where id='10000000-0000-4000-8000-000000000002';
insert into storage.objects(bucket_id,name) values
 ('receipts','10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/test.png'),
 ('receipts','10000000-0000-4000-8000-000000000002/20000000-0000-4000-8000-000000000002/test.png'),
 ('receipts','10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000003/test.png');
select public.save_expense_verified('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
 jsonb_build_object('title','Test trip','merchant','IRCTC','category','Travel','amount',2000,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,
 '10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/test.png',repeat('a',64),'test.png','image/png');
-- A replay of the same submission must not create another claim or event.
select public.save_expense_verified('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
 jsonb_build_object('title','Test trip','merchant','IRCTC','category','Travel','amount',2000,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,
 '10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/test.png',repeat('a',64),'test.png','image/png');
select public.save_expense_verified('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',
 jsonb_build_object('title','Other trip','merchant','IRCTC','category','Travel','amount',2200,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,
 '10000000-0000-4000-8000-000000000002/20000000-0000-4000-8000-000000000002/test.png',repeat('b',64),'test.png','image/png');
select public.save_expense_verified('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003',
 jsonb_build_object('title','Duplicate receipt','merchant','Another vendor','category','Travel','amount',1200,'expense_date',current_date,'purpose','Official client meeting','payment_method','Cash','transaction_date',current_date),true,
 '10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000003/test.png',repeat('a',64),'test.png','image/png');
do $$ begin
 if (select status from public.expenses where id='20000000-0000-4000-8000-000000000003')<>'flagged' then raise exception 'FAIL: duplicate must be flagged'; end if;
end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
   perform public.submit_bank_details('20000000-0000-4000-8000-000000000001','Test Employee','Demo Bank','000000123456','000000123456','TEST0000001');
   raise exception 'FAIL: bank details before approval';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
 if exists(select 1 from public.expenses where employee_id='10000000-0000-4000-8000-000000000002') then raise exception 'FAIL: employee cross-record read'; end if;
 begin
   update public.profiles set role='admin' where id=auth.uid();
   raise exception 'FAIL: direct role escalation';
 exception when insufficient_privilege then null; end;
 begin
   update public.expenses set status='paid' where id='20000000-0000-4000-8000-000000000001';
   raise exception 'FAIL: direct status bypass';
 exception when insufficient_privilege then null; end;
 begin
   perform public.save_expense_verified(auth.uid(),'20000000-0000-4000-8000-000000000004','{}',true,null,null,null,null);
   raise exception 'FAIL: client trusted-writer access';
 exception when insufficient_privilege then null; end;
 begin
   perform public.review_expense('20000000-0000-4000-8000-000000000001','approved','');
   raise exception 'FAIL: employee approval';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
do $$ begin
 if exists(select 1 from public.expenses where id='20000000-0000-4000-8000-000000000001') then raise exception 'FAIL: manager cross-assignment read'; end if;
 begin
   perform public.review_expense('20000000-0000-4000-8000-000000000001','approved','');
   raise exception 'FAIL: unassigned manager approval';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin
   perform public.review_expense('20000000-0000-4000-8000-000000000003','approved','');
   raise exception 'FAIL: flagged approval without reason';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
 begin
   perform public.review_expense('20000000-0000-4000-8000-000000000003','rejected','');
   raise exception 'FAIL: rejection without reason';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select public.review_expense('20000000-0000-4000-8000-000000000001','approved','Reviewed original receipt.');
-- Exact retries succeed without duplicate decisions/tickets/events.
select public.review_expense('20000000-0000-4000-8000-000000000001','approved','Reviewed original receipt.');
select public.review_expense('20000000-0000-4000-8000-000000000003','rejected','Duplicate receipt requires correction.');
do $$ begin
 begin
   perform public.review_expense('20000000-0000-4000-8000-000000000001','approved','Second attempt');
   raise exception 'FAIL: repeat approval';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
do $$ begin
 if exists(select 1 from public.expenses where id='20000000-0000-4000-8000-000000000002') then raise exception 'FAIL: finance sees pending claims'; end if;
 begin
   perform public.process_reimbursement('20000000-0000-4000-8000-000000000001','paid','TEST-NOT-READY',current_date);
   raise exception 'FAIL: skipping processing';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
do $$ begin
 begin
   perform public.process_reimbursement('20000000-0000-4000-8000-000000000001','processing');
   raise exception 'FAIL: finance bypasses missing bank details';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.reimbursement_tickets where expense_id='20000000-0000-4000-8000-000000000001') then raise exception 'FAIL: other employee sees ticket'; end if;
 begin
   perform public.submit_bank_details('20000000-0000-4000-8000-000000000001','Other Employee','Demo Bank','000000123456','000000123456','TEST0000001');
   raise exception 'FAIL: other employee changes bank details';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.reimbursement_tickets where expense_id='20000000-0000-4000-8000-000000000001')<>1 then raise exception 'FAIL: approval ticket missing or duplicated'; end if;
 if exists(select 1 from public.reimbursement_tickets where expense_id='20000000-0000-4000-8000-000000000003') then raise exception 'FAIL: rejected purchase has ticket'; end if;
 begin
   update public.reimbursement_tickets set status='submitted';
   raise exception 'FAIL: direct ticket status change';
 exception when insufficient_privilege then null; end;
 begin
   perform public.submit_bank_details('20000000-0000-4000-8000-000000000001','Test Employee','Demo Bank','000000123456','000000123456','BAD');
   raise exception 'FAIL: invalid IFSC accepted';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
 begin
   perform public.submit_bank_details('20000000-0000-4000-8000-000000000001','Test Employee','Demo Bank','000000123456','000000999999','TEST0000001');
   raise exception 'FAIL: mismatched account confirmation';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select public.submit_bank_details('20000000-0000-4000-8000-000000000001','Test Employee','Demo Bank','000000123456','000000123456','TEST0000001');
select public.submit_bank_details('20000000-0000-4000-8000-000000000001','Test Employee','Demo Bank','000000123456','000000123456','TEST0000001');
do $$ declare summary jsonb; begin
 summary:=public.get_reimbursement_ticket('20000000-0000-4000-8000-000000000001');
 if summary->>'account_last4'<>'3456' or summary ? 'account_number' then raise exception 'FAIL: owner summary masking'; end if;
 if (select count(*) from public.audit_logs where expense_id='20000000-0000-4000-8000-000000000001' and action='Reimbursement bank details submitted')<>1 then raise exception 'FAIL: identical submission not idempotent'; end if;
end; $$;
-- All roles except finance are denied the full account-number endpoint and private table.
do $$ declare actor text; begin
 foreach actor in array array['10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000006'] loop
   perform set_config('request.jwt.claim.sub',actor,true);
   begin perform public.get_bank_details('20000000-0000-4000-8000-000000000001');raise exception 'FAIL: non-finance bank reveal';
   exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
   begin perform 1 from expense_private.bank_details;raise exception 'FAIL: direct bank table read';
   exception when insufficient_privilege then null; end;
 end loop;
end; $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
do $$ begin
 if public.get_bank_details('20000000-0000-4000-8000-000000000001')->>'account_number'<>'000000123456' then raise exception 'FAIL: finance bank reveal or leading zeros'; end if;
end; $$;
select public.process_reimbursement('20000000-0000-4000-8000-000000000001','processing');
select public.process_reimbursement('20000000-0000-4000-8000-000000000001','processing');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
   perform public.submit_bank_details('20000000-0000-4000-8000-000000000001','Changed Employee','Demo Bank','000000654321','000000654321','TEST0000001');
   raise exception 'FAIL: account changed after processing';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);

do $$ begin
 begin
   perform public.process_reimbursement('20000000-0000-4000-8000-000000000001','paid',null,current_date);
   raise exception 'FAIL: missing payment reference';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
select public.process_reimbursement('20000000-0000-4000-8000-000000000001','paid','EF-ROLLBACK-TEST-REFERENCE',current_date);
select public.process_reimbursement('20000000-0000-4000-8000-000000000001','paid','EF-ROLLBACK-TEST-REFERENCE',current_date);
do $$ begin
 if (select status from public.expenses where id='20000000-0000-4000-8000-000000000001')<>'paid' then raise exception 'FAIL: final state'; end if;
 begin
   perform public.process_reimbursement('20000000-0000-4000-8000-000000000001','paid','SECOND-ATTEMPT',current_date);
   raise exception 'FAIL: double payment';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end;
end; $$;
reset role;
do $$ begin
 if (select status from public.reimbursement_tickets where expense_id='20000000-0000-4000-8000-000000000001')<>'closed' then raise exception 'FAIL: paid ticket not closed'; end if;
 if exists(select 1 from public.audit_logs where expense_id='20000000-0000-4000-8000-000000000001' and metadata::text like '%000000123456%') then raise exception 'FAIL: bank number leaked in audit'; end if;
 if not exists(select 1 from public.notifications where expense_id='20000000-0000-4000-8000-000000000001' and message like '%reimbursement ticket%') then raise exception 'FAIL: approval ticket notification'; end if;
 if (select count(*) from public.approvals where expense_id='20000000-0000-4000-8000-000000000001')<>1 then raise exception 'FAIL: approval uniqueness'; end if;
 if (select count(*) from public.reimbursements where expense_id='20000000-0000-4000-8000-000000000001')<>1 then raise exception 'FAIL: reimbursement uniqueness'; end if;
 if not exists(select 1 from public.notifications where user_id='10000000-0000-4000-8000-000000000001' and message like '%No money was transferred%') then raise exception 'FAIL: reimbursement notification'; end if;
 if (select count(*) from public.audit_logs where expense_id='20000000-0000-4000-8000-000000000001')<>7 then raise exception 'FAIL: workflow audit trail'; end if;
end; $$;

-- Exercise deferred constraints before rollback (ROLLBACK alone never runs them).
set constraints all immediate;
do $$ begin
 begin
   update public.expenses set status='approved' where id='20000000-0000-4000-8000-000000000002';
   raise exception 'FAIL: orphan approval accepted';
 exception when check_violation then null; end;
 begin
   update public.reimbursements set amount=amount+1 where expense_id='20000000-0000-4000-8000-000000000001';
   raise exception 'FAIL: mismatching payment accepted';
 exception when check_violation then null; end;
 begin
   update public.reimbursement_tickets set status='submitted' where expense_id='20000000-0000-4000-8000-000000000001';
   raise exception 'FAIL: reopening a paid ticket accepted';
 exception when check_violation then null; end;
end; $$;
-- More than one REST page of real SQL fixtures, all removed by the final rollback.
insert into public.expenses(id,employee_id,title,category,amount,expense_date,merchant)
select gen_random_uuid(),'10000000-0000-4000-8000-000000000001','Snapshot pagination fixture','Travel',0.10,current_date,'Test' from generate_series(1,1005);
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ declare snapshot jsonb; detail jsonb; begin
 snapshot:=public.expense_workspace();
 if jsonb_array_length(snapshot->'expenses')<>1007 then raise exception 'FAIL: snapshot truncation or RLS'; end if;
 detail:=public.expense_workspace('20000000-0000-4000-8000-000000000001')->'expenses'->0;
 if detail->>'status'<>'paid' or detail->'reimbursements'->0->>'status'<>'paid' or detail->'ticket'->>'status'<>'closed' then raise exception 'FAIL: mixed detail snapshot'; end if;
 if detail->'ticket' ? 'account_number' then raise exception 'FAIL: snapshot leaks bank account'; end if;
 if jsonb_array_length(public.expense_workspace('20000000-0000-4000-8000-000000000002')->'expenses')<>0 then raise exception 'FAIL: snapshot bypasses RLS'; end if;
end; $$;
reset role;

rollback;
select 'Database regression checks completed; test fixtures rolled back.' as result;
