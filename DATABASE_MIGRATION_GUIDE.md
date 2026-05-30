# Database Migration Guide - Profile Update Feature

## ✅ Status: NO NEW MIGRATIONS REQUIRED

**Good News!** Fitur update profile (username, email, password) **TIDAK memerlukan** migrasi database baru. Semua kolom yang diperlukan sudah ada di schema yang ada.

---

## 📊 Current Database Schema

### Local Database (Drift/SQLite)

**Schema Version:** 5 (Current)

**Users Table Structure:**

```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT,              -- Supabase Auth ID
  email TEXT NOT NULL,         -- ✅ Already exists
  username TEXT,               -- ✅ Already exists (added in v5)
  full_name TEXT,              -- ✅ Already exists
  role TEXT DEFAULT 'viewer',  -- ✅ Already exists
  sync_status INTEGER DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Migration History:**

- v1-2: Initial tables
- v3: Added `users` table
- v4: Renamed proof columns
- v5: Added `username` column ✅ (Already done!)

### Supabase Database (PostgreSQL)

**Profiles Table Structure:**

```sql
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY,         -- References auth.users
  email text,                  -- ✅ Already exists
  username text,               -- ✅ Already exists
  full_name text,              -- ✅ Already exists
  role text DEFAULT 'viewer',  -- ✅ Already exists
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**RLS Policies:**

- ✅ "Users can update own profile" - Allows users to update their own data
- ✅ "Admins and Ketua can update any profile" - Admin user management

---

## 🔍 Verification Checklist

### For New Installations

If you're setting up a **NEW** Supabase project, run the existing SQL file:

**File:** `supabase_full_setup.sql`

**Steps:**

1. Open Supabase Dashboard → SQL Editor
2. Copy entire content of `supabase_full_setup.sql`
3. Paste and click **RUN**
4. Verify tables created:
   ```sql
   SELECT table_name
   FROM information_schema.tables
   WHERE table_schema = 'public';
   ```
5. Expected tables:
   - ✅ profiles
   - ✅ transactions
   - ✅ activities
   - ✅ mosque_profiles
   - ✅ audit_logs

### For Existing Installations

If you already have the app running, **NO ACTION NEEDED**. Verify your schema:

**Check Local Database (Drift):**

```dart
// In your app, check schema version
final db = GetIt.I<AppDatabase>();
print('Schema version: ${db.schemaVersion}'); // Should be 5
```

**Check Supabase Database:**

```sql
-- Run in Supabase SQL Editor
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'profiles';
```

**Expected columns:**

- ✅ id (uuid)
- ✅ email (text)
- ✅ username (text)
- ✅ full_name (text)
- ✅ role (text)
- ✅ created_at (timestamptz)
- ✅ updated_at (timestamptz)

---

## 🚀 Deployment Steps

### Step 1: Verify Current Schema

**Local Database:**

```bash
# No action needed - Drift handles migrations automatically
# Schema version 5 already includes username column
```

**Supabase Database:**

```sql
-- Verify profiles table has all required columns
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
ORDER BY ordinal_position;
```

### Step 2: Verify RLS Policies

```sql
-- Check if user can update their own profile
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'profiles';
```

**Expected policies:**

1. ✅ "Read access for authenticated users" (SELECT)
2. ✅ "Users can update own profile" (UPDATE)
3. ✅ "Admins and Ketua can update any profile" (UPDATE)

### Step 3: Test Profile Update

**Test Query (Supabase SQL Editor):**

```sql
-- Test if current user can update their profile
-- Replace 'YOUR_USER_ID' with actual user ID
UPDATE public.profiles
SET
  username = 'testuser',
  full_name = 'Test User',
  updated_at = now()
WHERE id = 'YOUR_USER_ID';
```

---

## 🔧 Troubleshooting

### Issue 1: "Column 'username' does not exist" (Local DB)

**Cause:** App database is on old schema version (< 5)

**Solution:**

```dart
// The app will auto-migrate on next launch
// Or manually trigger migration:
final db = GetIt.I<AppDatabase>();
await db.close();
// Restart app - Drift will run migrations
```

**Manual Fix (if needed):**

```sql
-- In SQLite (via device inspector)
ALTER TABLE users ADD COLUMN username TEXT;
```

### Issue 2: "Column 'username' does not exist" (Supabase)

**Cause:** Supabase table not created with latest schema

**Solution:**

```sql
-- Run in Supabase SQL Editor
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS username text;
```

### Issue 3: "Permission denied for table profiles"

**Cause:** RLS policy not allowing user to update

**Solution:**

```sql
-- Verify user has correct role
SELECT id, email, role FROM public.profiles WHERE id = auth.uid();

-- Re-create policy if needed
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id);
```

### Issue 4: "Trigger 'on_auth_user_created' does not exist"

**Cause:** Trigger not created during initial setup

**Solution:**

```sql
-- Re-run trigger creation from supabase_full_setup.sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, username, role)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', ''),
    COALESCE(new.raw_user_meta_data->>'username', ''),
    COALESCE(new.raw_user_meta_data->>'role', 'viewer')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
```

---

## 📋 Pre-Deployment Checklist

### Local Database (Drift)

- [x] Schema version is 5
- [x] Users table has `username` column
- [x] Users table has `email` column
- [x] Users table has `full_name` column
- [x] Migration strategy handles v5 upgrade

### Supabase Database

- [ ] Profiles table exists
- [ ] Profiles table has `username` column
- [ ] Profiles table has `email` column
- [ ] Profiles table has `full_name` column
- [ ] RLS policy "Users can update own profile" exists
- [ ] RLS policy "Admins and Ketua can update any profile" exists
- [ ] Trigger `on_auth_user_created` exists
- [ ] Trigger `on_profiles_updated` exists

### Testing

- [ ] User can update their own username
- [ ] User can update their own email
- [ ] User can update their own password
- [ ] User can update their own full name
- [ ] User cannot update another user's profile (unless admin)
- [ ] Email uniqueness is enforced
- [ ] Username uniqueness is enforced
- [ ] Updated_at timestamp is auto-updated

---

## 🔄 Rollback Plan

If you need to rollback the profile update feature:

### Code Rollback

```bash
git revert <commit-hash>
git push
```

### Database Rollback

**NOT NEEDED** - No schema changes were made for this feature. All columns already existed.

---

## 📊 Database Monitoring

### Queries to Monitor

**1. Check Profile Update Activity:**

```sql
SELECT
  COUNT(*) as total_updates,
  DATE(updated_at) as update_date
FROM public.profiles
WHERE updated_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(updated_at)
ORDER BY update_date DESC;
```

**2. Check Username Uniqueness:**

```sql
SELECT
  username,
  COUNT(*) as count
FROM public.profiles
WHERE username IS NOT NULL
GROUP BY username
HAVING COUNT(*) > 1;
-- Should return 0 rows
```

**3. Check Email Uniqueness:**

```sql
SELECT
  email,
  COUNT(*) as count
FROM public.profiles
WHERE email IS NOT NULL
GROUP BY email
HAVING COUNT(*) > 1;
-- Should return 0 rows
```

**4. Check Audit Logs:**

```sql
SELECT
  action,
  table_name,
  description,
  created_at
FROM public.audit_logs
WHERE table_name = 'users'
  AND action = 'UPDATE'
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 50;
```

---

## 🎯 Performance Optimization

### Indexes (Optional but Recommended)

If you have many users, add these indexes for better performance:

```sql
-- Index on username for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_username
ON public.profiles(username)
WHERE username IS NOT NULL;

-- Index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_email
ON public.profiles(email)
WHERE email IS NOT NULL;

-- Index on updated_at for monitoring queries
CREATE INDEX IF NOT EXISTS idx_profiles_updated_at
ON public.profiles(updated_at DESC);
```

**Note:** These indexes are optional and only needed if you have > 1000 users.

---

## 📞 Support

### Database Issues

- Check Supabase Dashboard → Database → Logs
- Check app logs for Drift migration errors
- Verify RLS policies in Supabase Dashboard → Authentication → Policies

### Schema Verification

```sql
-- Get complete schema info
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('profiles', 'users')
ORDER BY table_name, ordinal_position;
```

---

## ✅ Summary

**For Profile Update Feature:**

- ✅ NO new migrations required
- ✅ All columns already exist in schema
- ✅ RLS policies already configured
- ✅ Triggers already in place
- ✅ Ready for production deployment

**Action Required:**

- ✅ Verify existing schema (checklist above)
- ✅ Test profile update functionality
- ✅ Monitor database performance
- ✅ (Optional) Add performance indexes

---

**Last Updated:** 2024-02-24  
**Schema Version:** 5 (Local), Current (Supabase)  
**Status:** ✅ No Migration Needed
