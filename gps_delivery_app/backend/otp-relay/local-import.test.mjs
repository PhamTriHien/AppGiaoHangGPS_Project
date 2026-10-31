import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

test('Address imports preview without writes, reject foreign ownership, commit atomically and survive replay', async t => {
  const db=new PGlite(); t.after(()=>db.close());
  await db.exec(`create role authenticated; create role anon;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text); alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated; create publication supabase_realtime;`);
  for(const name of ['20261027_delivery_integrations','20261028_cloud_orders','20261029_cloud_addresses','20261102_local_address_import']) {
    await db.exec(await readFile(new URL(`../../database/migrations/${name}.sql`,import.meta.url),'utf8'));
  }
  const alice=randomUUID(),bob=randomUUID();
  for(const id of [alice,bob]) await db.query('insert into auth.users values($1)',[id]);
  const as=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
  for(const id of [alice,bob]) {await as(id);await db.query('select delivery_cloud_profile($1)',[{full_name:'User',phone:'0901234567'}]);}
  const call=async(action,items)=>(await db.query('select delivery_cloud_import($1,$2) data',[action,items])).rows[0].data;
  const item=n=>({source_key:n.toString(16).padStart(64,'0'),details:{label:`Address ${n}`,recipient_name:'Recipient',recipient_phone:'0912345678',
    full_address:`${n} Nguyen Hue TP HCM`,latitude:10.77,longitude:106.7}});
  await as(alice);
  const preview=await call('preview',[item(1),{...item(2),details:{...item(2).details,latitude:91}}]);
  assert.equal(preview.ready,1);assert.deepEqual(preview.rows.map(r=>r.status),['ready','invalid']);
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,0);
  await assert.rejects(call('commit',[item(1),{...item(2),details:{...item(2).details,latitude:91}}]),/Chưa có địa chỉ/);
  await assert.rejects(call('preview',[{...item(1),user_id:bob}]),/không hợp lệ/);
  assert.equal((await call('preview',[{...item(1),details:{...item(1).details,balance:10000}}])).rows[0].status,'invalid');
  await assert.rejects(call('commit',[item(1),item(1)]),/bị trùng/);
  await assert.rejects(db.exec('select * from delivery_cloud_imports'),/permission denied/);
  const same={...item(2),details:{...item(1).details}};
  assert.deepEqual((await call('preview',[item(1),same])).rows.map(r=>r.status),['ready','duplicate']);
  await call('commit',[item(1),item(2)]);
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,2);
  assert.equal((await call('commit',[item(1),item(2)])).ready,0);
  const duplicate=await call('preview',[{...item(3),details:{...item(1).details}}]);
  assert.equal(duplicate.rows[0].status,'duplicate');
  const changed={...item(1),details:{...item(1).details,label:'Changed source'}};
  assert.equal((await call('preview',[changed])).rows[0].status,'conflict');
  await assert.rejects(call('commit',[changed,item(3)]),/Chưa có địa chỉ/);
  await as(bob);
  assert.equal((await call('preview',[item(1)])).rows[0].status,'ready');
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,0);
  await call('commit',[item(1)]);
  await as(alice);
  const address=(await db.query('select * from delivery_cloud_addresses order by created_at,id')).rows[0];
  await db.query('select delivery_cloud_addresses_manage($1,null,true,$2)',[address.id,address.version]);
  assert.equal((await call('preview',[item(1)])).rows[0].status,'imported');
  await call('commit',[item(1)]);
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,1);
  // A failure after the first write rolls the complete batch back.
  await db.exec(`reset role;create function fail_import() returns trigger language plpgsql as $$begin
    if new.label='Address 4' then raise exception 'injected import failure';end if;return new;end$$;
    create trigger fail_import before insert on delivery_cloud_addresses for each row execute function fail_import();`);
  await as(alice);
  await assert.rejects(call('commit',[item(3),item(4)]),/injected import failure/);
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,1);
  assert.equal((await call('preview',[item(3)])).rows[0].status,'ready');
  await db.exec('reset role;drop trigger fail_import on delivery_cloud_addresses;drop function fail_import()');
  await db.query('update delivery_cloud_accounts set blocked=true where user_id=$1',[alice]);
  await as(alice);
  await assert.rejects(call('preview',[item(3)]),/đang hoạt động/);
});
