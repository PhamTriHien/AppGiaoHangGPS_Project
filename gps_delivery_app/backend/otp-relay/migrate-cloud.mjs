import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import pg from 'pg';
import { loadIntegrationConfig } from './integration-config.mjs';
import { databaseConnectionOptions } from './database-connection.mjs';

export async function migrateCloud({ env = process.env } = {}) {
  const connectionString = env.DATABASE_URL?.trim();
  if (!connectionString) throw new Error('MISSING_DATABASE_URL');
  const client = new pg.Client({ ...databaseConnectionOptions(env), connectionTimeoutMillis: 10000,
    query_timeout: 30000, application_name: 'ghst-cloud-migration' });
  await client.connect();
  try {
    await client.query('select pg_advisory_lock(734615298)');
    const installed = await client.query("select to_regprocedure('public.delivery_is_operator()') is not null as ready");
    if (!installed.rows[0].ready) {
      await client.query(await readFile(new URL('../../database/migrations/20261027_delivery_integrations.sql', import.meta.url), 'utf8'));
    }
    await client.query(await readFile(new URL('../../database/migrations/20261028_cloud_orders.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261029_payments_ghn.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261029_cloud_addresses.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261030_marketplace.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261031_market_operations.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261101_partner_memberships.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261102_local_address_import.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261103_catalog_stock_versions.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261104_market_media.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261105_market_browse.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261106_catalog_configuration.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261107_cloud_commercial_suite.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261108_cloud_logistics.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261109_admin_account_management.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261110_cloud_promo_events.sql', import.meta.url), 'utf8'));
    await client.query(await readFile(new URL('../../database/migrations/20261111_profile_push_shipping_coins.sql', import.meta.url), 'utf8'));
    const result = await client.query("select to_regprocedure('public.delivery_cloud_create(jsonb,uuid,integer,integer)') is not null and to_regprocedure('public.delivery_cloud_addresses_manage(uuid,jsonb,boolean,integer)') is not null and to_regprocedure('public.delivery_marketplace(text,jsonb)') is not null as ready");
    const operations = await client.query("select to_regprocedure('public.delivery_market_operations(text,jsonb)') is not null and to_regprocedure('public.delivery_market_run_jobs(integer)') is not null as ready");
    const memberships = await client.query("select to_regprocedure('public.delivery_cloud_membership(text,text,uuid,integer,text)') is not null as ready");
    const commercial = await client.query("select to_regprocedure('public.delivery_market_attachment_reserve(uuid,text,text,integer)') is not null and to_regprocedure('public.delivery_cloud_public_lookup(text,text)') is not null and to_regprocedure('public.delivery_market_record_prepaid_capture(uuid,text)') is not null as ready");
    const logistics = await client.query("select to_regprocedure('public.delivery_cloud_logistics(text,jsonb)') is not null as ready");
    const adminAccounts = await client.query("select to_regprocedure('public.delivery_cloud_admin_accounts(text,jsonb)') is not null as ready");
    const promoEvents = await client.query("select to_regprocedure('public.delivery_cloud_promo_events(text,jsonb)') is not null as ready");
    const profilePushCoins = await client.query("select to_regprocedure('public.delivery_cloud_notifications(text,jsonb)') is not null and exists(select 1 from information_schema.columns where table_schema='public' and table_name='delivery_cloud_accounts' and column_name='citizen_id') and exists(select 1 from information_schema.columns where table_schema='public' and table_name='delivery_cloud_orders' and column_name='payable_fee') as ready");
    return { ready: result.rows[0].ready && operations.rows[0].ready && memberships.rows[0].ready && commercial.rows[0].ready && logistics.rows[0].ready && adminAccounts.rows[0].ready && promoEvents.rows[0].ready && profilePushCoins.rows[0].ready,
      migration: '20261111_profile_push_shipping_coins', workflowVersion: 17 };
  } finally { await client.end(); }
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  await loadIntegrationConfig();
  try { console.log(JSON.stringify(await migrateCloud())); }
  catch (error) {
    // Never print connection strings, provider errors or SQL containing user data.
    console.error(error.message === 'MISSING_DATABASE_URL'
      ? 'DATABASE_URL is missing. Set the Supabase PostgreSQL connection string in backend .env. SQL Editor can install the delivery migrations, but payment/carrier routes also require DATABASE_URL on the backend.'
      : 'Cloud migration failed. Check database credentials, verified TLS, network and SQL permissions. Credentials were not printed.');
    process.exitCode = 1;
  }
}
