-- Restrict admin-account management to admins only.
--
-- Previously "Admins and Ketua can update any profile" let a ketua directly
-- (via the client SDK, bypassing the admin-users Edge Function) promote anyone
-- -- including themselves -- to admin, and modify/demote the bootstrap admin.
-- Combined with the Edge Function's admin-OR-ketua gate, a subordinate role
-- held full super-admin power, defeating the single-bootstrap-admin model that
-- claim_first_admin() is meant to guarantee.
--
-- Split the "update any profile" policy so:
--   * admins may update any profile (any role change);
--   * ketua may update only NON-admin profiles, and may NOT set role='admin'.
-- Postgres evaluates permissive policies as OR for USING and OR for WITH CHECK,
-- so a ketua setting role='admin' fails every WITH CHECK (rejected), and a
-- ketua targeting an existing admin row fails every USING (rejected).
--
-- The matching admin-users Edge Function change additionally blocks a ketua
-- from CREATE/DELETE of admin accounts (those have no client RLS path).
--
-- Safe to run repeatedly on an existing Supabase project.

DROP POLICY IF EXISTS "Admins and Ketua can update any profile" ON public.profiles;
-- Also drop the new names so a re-run is truly idempotent (Postgres has no
-- CREATE POLICY IF NOT EXISTS; without these, a second run errors).
DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;
DROP POLICY IF EXISTS "Ketua can update non-admin profiles" ON public.profiles;

CREATE POLICY "Admins can update any profile" ON public.profiles FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles caller WHERE caller.id = auth.uid() AND caller.role = 'admin')
) WITH CHECK (
  EXISTS (SELECT 1 FROM public.profiles caller WHERE caller.id = auth.uid() AND caller.role = 'admin')
);

CREATE POLICY "Ketua can update non-admin profiles" ON public.profiles FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles caller WHERE caller.id = auth.uid() AND caller.role = 'ketua')
  AND role <> 'admin'
) WITH CHECK (
  EXISTS (SELECT 1 FROM public.profiles caller WHERE caller.id = auth.uid() AND caller.role = 'ketua')
  AND role <> 'admin'
);

NOTIFY pgrst, 'reload schema';
