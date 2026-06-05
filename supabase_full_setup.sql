-- Supabase Full Setup Script
-- Run this in the Supabase SQL Editor to set up the entire backend for a new project/account.

-- 1. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Create Tables

-- PROFILES (Users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  email text,
  username text,
  full_name text,
  role text default 'viewer', -- 'admin', 'ketua', 'bendahara', 'sekretaris', 'viewer'
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- TRANSACTIONS
CREATE TABLE IF NOT EXISTS public.transactions (
  id uuid default uuid_generate_v4() primary key,
  type text not null, -- 'income', 'expense'
  amount numeric not null,
  category text not null,
  description text,
  transaction_date timestamptz not null,
  proof_url text[], -- Array of URLs
  source text not null default 'manual',
  source_ref text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ACTIVITIES
CREATE TABLE IF NOT EXISTS public.activities (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  description text,
  type text not null,
  activity_date timestamptz not null,
  pic_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- MOSQUE PROFILES
CREATE TABLE IF NOT EXISTS public.mosque_profiles (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  address text,
  logo_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- AUDIT LOGS
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid default uuid_generate_v4() primary key,
  user_id text, -- Changed from uuid to text to support offline/local user IDs (e.g. 'system', 'offline_user')
  action text not null,
  table_name text,
  record_id text,
  description text,
  created_at timestamptz default now()
);

-- QURBAN PACKAGES
CREATE TABLE IF NOT EXISTS public.qurban_packages (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  monthly_amount numeric not null,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- QURBAN PARTICIPANTS
CREATE TABLE IF NOT EXISTS public.qurban_participants (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  phone text,
  address text,
  notes text,
  start_month timestamptz not null,
  monthly_amount numeric not null,
  total_months integer not null default 10,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- QURBAN PAYMENTS
CREATE TABLE IF NOT EXISTS public.qurban_payments (
  id uuid default uuid_generate_v4() primary key,
  participant_id uuid references public.qurban_participants(id) on delete cascade not null,
  transaction_id uuid references public.transactions(id) on delete set null,
  amount numeric not null,
  payment_date timestamptz not null,
  note text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS source text not null default 'manual';

ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS source_ref text;

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mosque_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qurban_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qurban_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qurban_payments ENABLE ROW LEVEL SECURITY;

-- 3b. Data API grants
-- Supabase projects created with the newer secure default require explicit grants
-- before tables in public are visible to PostgREST/supabase-flutter. RLS policies
-- below still decide which rows/actions are allowed.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

REVOKE ALL ON TABLE
  public.profiles,
  public.transactions,
  public.activities,
  public.audit_logs,
  public.qurban_packages,
  public.qurban_participants,
  public.qurban_payments
FROM anon;

GRANT SELECT ON TABLE public.mosque_profiles TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.profiles,
  public.transactions,
  public.activities,
  public.mosque_profiles,
  public.audit_logs,
  public.qurban_packages,
  public.qurban_participants,
  public.qurban_payments
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.profiles,
  public.transactions,
  public.activities,
  public.mosque_profiles,
  public.audit_logs,
  public.qurban_packages,
  public.qurban_participants,
  public.qurban_payments
TO service_role;

-- 4. Triggers & Functions

-- Function to handle new user creation (Auth -> Public Profile)
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
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Trigger for new user
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Function to update 'updated_at' column automatically
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger AS $$
BEGIN
  new.updated_at = now();
  RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS on_profiles_updated ON public.profiles;
CREATE TRIGGER on_profiles_updated BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_transactions_updated ON public.transactions;
CREATE TRIGGER on_transactions_updated BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_activities_updated ON public.activities;
CREATE TRIGGER on_activities_updated BEFORE UPDATE ON public.activities
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_mosque_profiles_updated ON public.mosque_profiles;
CREATE TRIGGER on_mosque_profiles_updated BEFORE UPDATE ON public.mosque_profiles
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_qurban_packages_updated ON public.qurban_packages;
CREATE TRIGGER on_qurban_packages_updated BEFORE UPDATE ON public.qurban_packages
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_qurban_participants_updated ON public.qurban_participants;
CREATE TRIGGER on_qurban_participants_updated BEFORE UPDATE ON public.qurban_participants
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_qurban_payments_updated ON public.qurban_payments;
CREATE TRIGGER on_qurban_payments_updated BEFORE UPDATE ON public.qurban_payments
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

-- 5. RLS Policies

-- PROFILES
-- Read access for authenticated users
DROP POLICY IF EXISTS "Read access for authenticated users" ON public.profiles;
CREATE POLICY "Read access for authenticated users" ON public.profiles FOR SELECT USING (auth.role() = 'authenticated');

-- Users can update their own profile
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Admins and Ketua can update any profile (User Management)
DROP POLICY IF EXISTS "Admins and Ketua can update any profile" ON public.profiles;
CREATE POLICY "Admins and Ketua can update any profile" ON public.profiles FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua'))
);

-- TRANSACTIONS
DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.transactions;

-- Read: Authenticated (Everyone can view)
DROP POLICY IF EXISTS "Authenticated can read transactions" ON public.transactions;
CREATE POLICY "Authenticated can read transactions" ON public.transactions FOR SELECT USING (auth.role() = 'authenticated');

-- Modify: Admin and Bendahara only
DROP POLICY IF EXISTS "Admin and Bendahara can modify transactions" ON public.transactions;
CREATE POLICY "Admin and Bendahara can modify transactions" ON public.transactions FOR ALL USING (
  auth.role() = 'authenticated' AND 
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'bendahara'))
) WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'bendahara'))
);

-- ACTIVITIES
DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.activities;

-- Read: Authenticated (Everyone can view)
DROP POLICY IF EXISTS "Authenticated can read activities" ON public.activities;
CREATE POLICY "Authenticated can read activities" ON public.activities FOR SELECT USING (auth.role() = 'authenticated');

-- Modify: Admin and Sekretaris only
DROP POLICY IF EXISTS "Admin and Sekretaris can modify activities" ON public.activities;
CREATE POLICY "Admin and Sekretaris can modify activities" ON public.activities FOR ALL USING (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'sekretaris'))
) WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'sekretaris'))
);

-- MOSQUE PROFILES
DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.mosque_profiles;

-- Read: Public (Everyone can view, even without login) - Required for login page check
DROP POLICY IF EXISTS "Public can read mosque profile" ON public.mosque_profiles;
CREATE POLICY "Public can read mosque profile" ON public.mosque_profiles FOR SELECT USING (true);

-- Update: Admin and Ketua only (Settings access)
DROP POLICY IF EXISTS "Admin and Ketua can update mosque profile" ON public.mosque_profiles;
CREATE POLICY "Admin and Ketua can update mosque profile" ON public.mosque_profiles FOR UPDATE USING (
  auth.role() = 'authenticated' AND 
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua'))
);

DROP POLICY IF EXISTS "Admin and Ketua can insert mosque profile" ON public.mosque_profiles;
CREATE POLICY "Admin and Ketua can insert mosque profile" ON public.mosque_profiles FOR INSERT WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua'))
);

-- AUDIT LOGS
DROP POLICY IF EXISTS "Allow authenticated select audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Allow authenticated insert audit_logs" ON public.audit_logs;

-- Read: Admin and Ketua only
DROP POLICY IF EXISTS "Admin and Ketua can read logs" ON public.audit_logs;
CREATE POLICY "Admin and Ketua can read logs" ON public.audit_logs FOR SELECT USING (
  auth.role() = 'authenticated' AND 
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua'))
);

-- Insert: Authenticated users can insert logs (system writes logs)
DROP POLICY IF EXISTS "Authenticated can insert logs" ON public.audit_logs;
CREATE POLICY "Authenticated can insert logs" ON public.audit_logs FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- QURBAN
DROP POLICY IF EXISTS "Authenticated can read qurban packages" ON public.qurban_packages;
CREATE POLICY "Authenticated can read qurban packages" ON public.qurban_packages FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admin Ketua Bendahara can modify qurban packages" ON public.qurban_packages;
CREATE POLICY "Admin Ketua Bendahara can modify qurban packages" ON public.qurban_packages FOR ALL USING (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua', 'bendahara'))
) WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua', 'bendahara'))
);

DROP POLICY IF EXISTS "Authenticated can read qurban participants" ON public.qurban_participants;
CREATE POLICY "Authenticated can read qurban participants" ON public.qurban_participants FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admin Ketua Bendahara can modify qurban participants" ON public.qurban_participants;
CREATE POLICY "Admin Ketua Bendahara can modify qurban participants" ON public.qurban_participants FOR ALL USING (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua', 'bendahara'))
) WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua', 'bendahara'))
);

DROP POLICY IF EXISTS "Authenticated can read qurban payments" ON public.qurban_payments;
CREATE POLICY "Authenticated can read qurban payments" ON public.qurban_payments FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admin Ketua Bendahara can modify qurban payments" ON public.qurban_payments;
CREATE POLICY "Admin Ketua Bendahara can modify qurban payments" ON public.qurban_payments FOR ALL USING (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua', 'bendahara'))
) WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua', 'bendahara'))
);

-- 6. Storage Buckets Setup (Optional - Best effort via SQL)
-- Note: Usually done via UI, but this SQL attempts to create them if supported.

insert into storage.buckets (id, name, public)
values ('proofs', 'proofs', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('logos', 'logos', true)
on conflict (id) do nothing;

-- Storage Policies

-- Proofs
DROP POLICY IF EXISTS "Public Access Proofs" ON storage.objects;
create policy "Public Access Proofs"
  on storage.objects for select
  using ( bucket_id = 'proofs' );

DROP POLICY IF EXISTS "Authenticated Upload Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Upload Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload Own Proofs" ON storage.objects;
create policy "Authenticated Upload Own Proofs"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'proofs'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Authenticated Update Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Own Proofs" ON storage.objects;
create policy "Authenticated Update Own Proofs"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'proofs'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'proofs'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Authenticated Delete Own Proofs" ON storage.objects;
create policy "Authenticated Delete Own Proofs"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'proofs'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Logos
DROP POLICY IF EXISTS "Public Access Logos" ON storage.objects;
create policy "Public Access Logos"
  on storage.objects for select
  using ( bucket_id = 'logos' );

DROP POLICY IF EXISTS "Authenticated Upload Logos" ON storage.objects;
DROP POLICY IF EXISTS "Auth Upload Logos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload Own Logos" ON storage.objects;
create policy "Authenticated Upload Own Logos"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Authenticated Update Logos" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Logos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Own Logos" ON storage.objects;
create policy "Authenticated Update Own Logos"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Authenticated Delete Own Logos" ON storage.objects;
create policy "Authenticated Delete Own Logos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 7. Indexes & Constraints
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email_unique
ON public.profiles(lower(email))
WHERE email IS NOT NULL AND email <> '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_unique
ON public.profiles(lower(username))
WHERE username IS NOT NULL AND username <> '';

CREATE INDEX IF NOT EXISTS idx_transactions_updated_at
ON public.transactions(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_source
ON public.transactions(source, source_ref);

CREATE INDEX IF NOT EXISTS idx_activities_updated_at
ON public.activities(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at
ON public.audit_logs(created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_packages_name_unique
ON public.qurban_packages(lower(name));

CREATE INDEX IF NOT EXISTS idx_qurban_packages_updated_at
ON public.qurban_packages(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_qurban_participants_updated_at
ON public.qurban_participants(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_qurban_payments_participant_id
ON public.qurban_payments(participant_id);

CREATE INDEX IF NOT EXISTS idx_qurban_payments_updated_at
ON public.qurban_payments(updated_at DESC);

INSERT INTO public.qurban_packages (id, name, monthly_amount, is_active)
VALUES
  ('00000000-0000-4000-8000-000000250000', 'Paket Qurban 250K', 250000, true),
  ('00000000-0000-4000-8000-000000275000', 'Paket Qurban 275K', 275000, true)
ON CONFLICT (id) DO UPDATE SET
  name = excluded.name,
  monthly_amount = excluded.monthly_amount,
  is_active = excluded.is_active;
