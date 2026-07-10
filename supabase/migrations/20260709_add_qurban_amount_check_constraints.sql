-- Adds DB-level sanity CHECK constraints for Qurban amounts/durations.
-- Previously only enforced in the Flutter UI, so any other writer (bulk
-- import, a direct API call, a future admin tool) could still store
-- 0/negative amounts uncontested.
--
-- NOT VALID skips validating pre-existing rows, so this is safe to run
-- against a live project that may already have data -- it still enforces
-- the check on every future insert/update. Once you've confirmed existing
-- data is clean (e.g. via the SELECT checks below), you can tighten it
-- with: ALTER TABLE ... VALIDATE CONSTRAINT <name>;
--
-- Safe to run repeatedly.

-- Sanity check before applying (should return 0 rows on a healthy project):
--   SELECT * FROM public.qurban_packages WHERE monthly_amount <= 0;
--   SELECT * FROM public.qurban_participants WHERE monthly_amount <= 0 OR total_months <= 0;
--   SELECT * FROM public.qurban_payments WHERE amount <= 0;

ALTER TABLE public.qurban_packages
  DROP CONSTRAINT IF EXISTS qurban_packages_monthly_amount_positive;
ALTER TABLE public.qurban_packages
  ADD CONSTRAINT qurban_packages_monthly_amount_positive
  CHECK (monthly_amount > 0) NOT VALID;

ALTER TABLE public.qurban_participants
  DROP CONSTRAINT IF EXISTS qurban_participants_monthly_amount_positive;
ALTER TABLE public.qurban_participants
  ADD CONSTRAINT qurban_participants_monthly_amount_positive
  CHECK (monthly_amount > 0) NOT VALID;

ALTER TABLE public.qurban_participants
  DROP CONSTRAINT IF EXISTS qurban_participants_total_months_positive;
ALTER TABLE public.qurban_participants
  ADD CONSTRAINT qurban_participants_total_months_positive
  CHECK (total_months > 0) NOT VALID;

ALTER TABLE public.qurban_payments
  DROP CONSTRAINT IF EXISTS qurban_payments_amount_positive;
ALTER TABLE public.qurban_payments
  ADD CONSTRAINT qurban_payments_amount_positive
  CHECK (amount > 0) NOT VALID;

NOTIFY pgrst, 'reload schema';
