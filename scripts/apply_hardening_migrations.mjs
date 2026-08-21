// Applies the 2026-07 production-hardening migrations to the linked Supabase
// project over a direct Postgres connection, then verifies the result.
//
//   deno run --allow-read --allow-net --allow-env scripts/apply_hardening_migrations.mjs
//
// Credentials: SUPABASE_DB_PASSWORD is read from .env at runtime -- the same
// pattern as scripts/create_admin.js. The password is never printed, never
// embedded here, and never leaves this machine except inside the TLS
// connection to the project's own database.
//
// Both migration files are idempotent, and they run inside ONE transaction:
// either everything applies or nothing does. SET LOCAL lock_timeout makes the
// DDL bail out fast instead of queueing behind a long-running lock and
// blocking the live app's writes.

import pg from "npm:pg@8";
import { readFileSync } from "node:fs";

const MIGRATIONS = [
  {
    version: "20260712",
    name: "add_soft_delete_tombstones",
    path: "supabase/migrations/20260712_add_soft_delete_tombstones.sql",
  },
  {
    version: "20260713",
    name: "restrict_ketua_admin_management",
    path: "supabase/migrations/20260713_restrict_ketua_admin_management.sql",
  },
];

// --- credentials & connection candidates -----------------------------------

function parseEnvFile(path) {
  const out = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*"?([^"\r\n]*?)"?\s*$/);
    if (m && !line.trim().startsWith("#")) out[m[1]] = m[2];
  }
  return out;
}

const env = parseEnvFile(".env");
const password = env.SUPABASE_DB_PASSWORD;
if (!password) {
  console.error("SUPABASE_DB_PASSWORD not found in .env -- aborting.");
  Deno.exit(1);
}
const enc = encodeURIComponent(password);
const mask = (s) =>
  String(s).replaceAll(enc, "*****").replaceAll(password, "*****");

const ref = readFileSync("supabase/.temp/project-ref", "utf8").trim();
const candidates = [
  {
    label: "direct",
    url: `postgresql://postgres:${enc}@db.${ref}.supabase.co:5432/postgres`,
  },
];
try {
  // e.g. postgresql://postgres.<ref>@aws-1-<region>.pooler.supabase.com:5432/postgres
  const pooler = readFileSync("supabase/.temp/pooler-url", "utf8").trim();
  const withPw = pooler.replace("@", `:${enc}@`);
  candidates.push({ label: "pooler-session(5432)", url: withPw });
  candidates.push({
    label: "pooler-txn(6543)",
    url: withPw.replace(":5432/", ":6543/"),
  });
} catch {
  console.log("(no pooler-url cached; using direct connection only)");
}

async function connect() {
  for (const c of candidates) {
    const client = new pg.Client({
      connectionString: c.url,
      ssl: { rejectUnauthorized: false },
      connectionTimeoutMillis: 12000,
    });
    try {
      await client.connect();
      console.log(`connected via ${c.label}`);
      return client;
    } catch (e) {
      console.log(`  ${c.label}: ${mask(e.message ?? e)}`);
      try {
        await client.end();
      } catch {
        /* ignore */
      }
    }
  }
  return null;
}

// --- inspection helpers ------------------------------------------------------

async function showState(client, title) {
  const cols = await client.query(
    `select table_name from information_schema.columns
     where table_schema='public' and column_name='deleted_at'
     order by table_name`,
  );
  const pols = await client.query(
    `select policyname, cmd from pg_policies
     where schemaname='public' and tablename='profiles'
     order by policyname`,
  );
  console.log(`\n--- ${title} ---`);
  console.log(
    "tables with deleted_at :",
    cols.rows.map((r) => r.table_name).join(", ") || "(none)",
  );
  console.log("profiles policies      :");
  for (const p of pols.rows) console.log(`  [${p.cmd}] ${p.policyname}`);
}

// --- main --------------------------------------------------------------------

const client = await connect();
if (!client) {
  console.error(
    "\nCould not reach the database on any route. If the password in .env " +
      "was rotated, update .env and re-run.",
  );
  Deno.exit(1);
}

try {
  await showState(client, "BEFORE");

  await client.query("begin");
  await client.query("set local lock_timeout = '8s'");
  await client.query("set local statement_timeout = '60s'");
  for (const m of MIGRATIONS) {
    const sql = readFileSync(m.path, "utf8");
    await client.query(sql);
    console.log(`applied ${m.version}_${m.name}`);
  }
  await client.query("commit");

  // Best-effort: record both versions in the CLI's migration-history table so
  // a future `supabase db push` doesn't consider them pending. Non-fatal if
  // the table doesn't exist (project never used db push against this DB).
  try {
    await client.query(
      `insert into supabase_migrations.schema_migrations (version, name, statements)
       values ($1, $2, $3), ($4, $5, $6)
       on conflict (version) do nothing`,
      [
        MIGRATIONS[0].version,
        MIGRATIONS[0].name,
        [readFileSync(MIGRATIONS[0].path, "utf8")],
        MIGRATIONS[1].version,
        MIGRATIONS[1].name,
        [readFileSync(MIGRATIONS[1].path, "utf8")],
      ],
    );
    console.log("migration history recorded (supabase_migrations)");
  } catch (e) {
    console.log(
      `migration history not recorded (non-fatal): ${mask(e.message ?? e).split("\n")[0]}`,
    );
  }

  await showState(client, "AFTER");
  console.log("\nSUCCESS: both hardening migrations are live.");
} catch (e) {
  try {
    await client.query("rollback");
  } catch {
    /* ignore */
  }
  console.error(`\nFAILED (rolled back): ${mask(e.message ?? e)}`);
  Deno.exit(1);
} finally {
  await client.end();
}
