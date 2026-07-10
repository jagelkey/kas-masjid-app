// LEGACY / MANUAL FALLBACK ONLY -- prefer the app's "Daftarkan Masjid Baru"
// screen, which uses this exact signUp() call plus the claim_first_admin()
// DB function so the resulting account can only ever become admin once.
//
// NOTE: the `role` field below is cosmetic only. Since handle_new_user()
// always assigns 'viewer' regardless of client-supplied metadata (a
// self-registration-as-admin hole was fixed here), this script creates a
// viewer account. To make it an admin, call the claim_first_admin() RPC
// while authenticated as this user (only works if no admin exists yet), or
// have an existing admin promote it via user management.
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const adminEmail = process.env.ADMIN_EMAIL;
const adminPassword = process.env.ADMIN_PASSWORD;

if (!supabaseUrl || !supabaseAnonKey || !adminEmail || !adminPassword) {
  console.error(
    'Missing required environment variables. Set SUPABASE_URL, SUPABASE_ANON_KEY, ADMIN_EMAIL, and ADMIN_PASSWORD.',
  );
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function run() {
  console.log('Creating user...');
  const { data, error } = await supabase.auth.signUp({
    email: adminEmail,
    password: adminPassword,
    options: {
      data: {
        full_name: 'Administrator',
      },
    },
  });

  if (error) {
    console.error('Error:', error.message);
  } else {
    console.log('User created successfully (role: viewer):', data.user.id);
  }
}

run();
