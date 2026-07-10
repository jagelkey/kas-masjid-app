// LEGACY / MANUAL FALLBACK ONLY.
//
// Prefer the app's own "Daftarkan Masjid Baru" screen to create the first
// admin -- it goes through Supabase Auth properly and is guarded by the
// claim_first_admin() DB function so it can only ever succeed once. This
// script inserts into auth.users directly, which bypasses Supabase's Auth
// service and its identity-linking, and can produce an account that looks
// created but won't behave like a normal one (e.g. missing auth.identities
// rows on newer Supabase versions). Only use this if the app flow is
// genuinely unavailable to you.
//
// Never hardcode database credentials in this file -- a live production
// password was previously committed here in plaintext and must be treated
// as compromised (rotate it in the Supabase dashboard if you haven't).
const { Client } = require('pg');

const connectionString = process.env.DATABASE_URL;
const adminEmail = process.env.ADMIN_EMAIL;
const adminPassword = process.env.ADMIN_PASSWORD;
const adminFullName = process.env.ADMIN_FULL_NAME || 'Administrator';

if (!connectionString || !adminEmail || !adminPassword) {
  console.error(
    'Missing required environment variables. Set DATABASE_URL, ADMIN_EMAIL, and ADMIN_PASSWORD, e.g.:\n' +
      '  DATABASE_URL="postgresql://postgres:<password>@db.<project>.supabase.co:5432/postgres" ' +
      'ADMIN_EMAIL="admin@example.com" ADMIN_PASSWORD="<strong-password>" node create_admin.js',
  );
  process.exit(1);
}

const client = new Client({ connectionString });

async function run() {
  try {
    await client.connect();

    // Enable pgcrypto if not enabled
    await client.query(`CREATE EXTENSION IF NOT EXISTS pgcrypto;`);

    // Create admin user. Role is intentionally left out of raw_user_meta_data:
    // handle_new_user() always assigns 'viewer' regardless of metadata, so
    // grant admin afterwards from an existing admin account via user
    // management, or via the app's claim_first_admin() flow if this is truly
    // the first account.
    const res = await client.query(
      `
      INSERT INTO auth.users (
        id,
        instance_id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        email_change,
        email_change_token_new,
        recovery_token
      )
      VALUES (
        uuid_generate_v4(),
        '00000000-0000-0000-0000-000000000000',
        'authenticated',
        'authenticated',
        $1,
        crypt($2, gen_salt('bf')),
        now(),
        '{"provider": "email", "providers": ["email"]}',
        jsonb_build_object('full_name', $3::text),
        now(),
        now(),
        '',
        '',
        '',
        ''
      ) RETURNING id;
    `,
      [adminEmail, adminPassword, adminFullName],
    );

    console.log('User created successfully with ID:', res.rows[0].id);

    // Check profiles table to ensure the trigger worked
    const profileRes = await client.query(`SELECT * FROM public.profiles WHERE id = $1`, [res.rows[0].id]);
    console.log('Profile created (role will be "viewer" until granted elevated access):', profileRes.rows[0]);
  } catch (err) {
    console.error('Error creating user:', err);
  } finally {
    await client.end();
  }
}

run();
