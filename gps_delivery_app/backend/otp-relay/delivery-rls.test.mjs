import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

test('PostgreSQL migration enforces room membership, driver-only updates and private evidence', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create role authenticated;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
    alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as
      $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated;
    grant select,insert on storage.objects to authenticated;
    create publication supabase_realtime;
  `);
  const migration = await readFile(new URL('../../database/migrations/20261027_delivery_integrations.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  const ids = { operator:'00000000-0000-0000-0000-000000000001', customer:'00000000-0000-0000-0000-000000000002',
    driver:'00000000-0000-0000-0000-000000000003', outsider:'00000000-0000-0000-0000-000000000004' };
  for (const id of Object.values(ids)) await db.query('insert into auth.users(id) values($1)',[id]);
  await db.query("insert into delivery_api_profiles values($1,'operator')",[ids.operator]);
  await db.exec("insert into delivery_live_rooms(id) values ('ORDER-A'),('ORDER-B')");
  await db.query("insert into delivery_live_members values('ORDER-A',$1,'customer'),('ORDER-A',$2,'driver')",[ids.customer,ids.driver]);
  const as = async role => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[role]]);
    await db.exec('set role authenticated');
  };
  await as('outsider');
  assert.equal((await db.query('select * from delivery_live_rooms')).rows.length,0);
  await assert.rejects(db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','chat','{\"text\":\"spam\"}')"),/row-level security/);
  await assert.rejects(db.query("insert into delivery_api_profiles values($1,'operator')",[ids.outsider]),/permission denied/);
  await as('customer');
  assert.equal((await db.query('select * from delivery_live_rooms')).rows.length,1);
  await db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','chat','{\"text\":\"Hello\"}')");
  await assert.rejects(db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','status','{\"status\":\"delivered\"}')"),/row-level security/);
  await assert.rejects(db.exec("insert into storage.objects(bucket_id,name) values('delivery-evidence','ORDER-A/customer.png')"),/row-level security/);
  await as('driver');
  await db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','status','{\"status\":\"inTransit\"}')");
  await assert.rejects(db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','status','{\"status\":\"searching\"}')"),/Invalid delivery transition/);
  await assert.rejects(db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','status','{\"status\":\"invented\"}')"),/Invalid delivery status/);
  await assert.rejects(db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','gps','{\"latitude\":99,\"longitude\":106}')"),/Invalid location/);
  await db.exec("insert into storage.objects(bucket_id,name) values('delivery-evidence','ORDER-A/driver.png')");
  await db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','pod','{\"path\":\"ORDER-A/driver.png\"}')");
  await assert.rejects(db.exec("insert into delivery_live_events(room_id,kind,payload) values('ORDER-A','pod','{\"path\":\"ORDER-B/driver.png\"}')"),/Invalid delivery evidence/);
  await assert.rejects(db.exec("insert into storage.objects(bucket_id,name) values('delivery-evidence','ORDER-B/driver.png')"),/row-level security/);
  await as('customer');
  assert.equal((await db.query('select * from storage.objects')).rows.length,1);
  await as('outsider');
  assert.equal((await db.query('select * from storage.objects')).rows.length,0);
  assert.equal((await db.query('select * from delivery_live_events')).rows.length,0);
  await as('operator');
  assert.equal((await db.query('select * from delivery_live_rooms')).rows.length,2);
});
