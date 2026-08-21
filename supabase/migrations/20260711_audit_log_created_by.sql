-- Audit-log actor forgery fix.
--
-- Before this, audit_logs.user_id was the only record of "who did it", and it
-- is a free-form text column written entirely by the client. Any authenticated
-- user could therefore insert a log entry attributed to anyone else (verified
-- live via role impersonation during the 2026-07-11 audit).
--
-- created_by is server-stamped from auth.uid() and cannot be forged: the client
-- never sends it (the column default fills it in), and the tightened INSERT
-- policy rejects any row whose created_by is not the caller. user_id is kept
-- as-is for backward compatibility and offline/local actor display, but audit
-- integrity should rely on created_by.
--
-- Idempotent and safe to run on a project that already has data: existing rows
-- get created_by = NULL (they predate the column), which is fine -- they are
-- simply the historical rows written before the guarantee existed.

ALTER TABLE public.audit_logs
  ADD COLUMN IF NOT EXISTS created_by uuid DEFAULT auth.uid();

DROP POLICY IF EXISTS "Authenticated can insert logs" ON public.audit_logs;
CREATE POLICY "Authenticated can insert logs" ON public.audit_logs
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated' AND created_by = auth.uid());
