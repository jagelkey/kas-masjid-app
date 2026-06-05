-- Add Qurban module tables and transaction source metadata.
-- Safe to run multiple times on an existing Supabase project.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS source text not null default 'manual';

ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS source_ref text;

CREATE TABLE IF NOT EXISTS public.qurban_packages (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  monthly_amount numeric not null,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

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

ALTER TABLE public.qurban_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qurban_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qurban_payments ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA public TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.transactions,
  public.qurban_packages,
  public.qurban_participants,
  public.qurban_payments
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.transactions,
  public.qurban_packages,
  public.qurban_participants,
  public.qurban_payments
TO service_role;

DROP TRIGGER IF EXISTS on_qurban_packages_updated ON public.qurban_packages;
CREATE TRIGGER on_qurban_packages_updated BEFORE UPDATE ON public.qurban_packages
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_qurban_participants_updated ON public.qurban_participants;
CREATE TRIGGER on_qurban_participants_updated BEFORE UPDATE ON public.qurban_participants
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

DROP TRIGGER IF EXISTS on_qurban_payments_updated ON public.qurban_payments;
CREATE TRIGGER on_qurban_payments_updated BEFORE UPDATE ON public.qurban_payments
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

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

CREATE INDEX IF NOT EXISTS idx_transactions_source
ON public.transactions(source, source_ref);

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
