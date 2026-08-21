-- Closes two privilege-escalation paths found in a production-readiness audit:
-- 1. public.profiles.role could be self-updated by ANY authenticated user,
--    because "Users can update own profile" had no WITH CHECK restricting
--    which columns may change -- only which row. A viewer could call
--    supabase.from('profiles').update({'role':'admin'}).eq('id', myId)
--    directly and successfully grant themselves admin.
-- 2. handle_new_user() trusted the client-supplied `role` in signup
--    metadata, so anyone could sign up requesting role=admin directly with
--    no exploit needed at all.
--
-- Safe to run repeatedly on an existing Supabase project.

-- 1. Lock down profile self-update so `role` can never change through it.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id
  AND role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
);

-- 2. Make the admin/ketua "update any profile" policy's WITH CHECK explicit
--    instead of relying on the USING-doubles-as-WITH-CHECK fallback.
DROP POLICY IF EXISTS "Admins and Ketua can update any profile" ON public.profiles;
CREATE POLICY "Admins and Ketua can update any profile" ON public.profiles FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua'))
) WITH CHECK (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'ketua'))
);

-- 3. Never trust client-supplied role at signup; new accounts always start
--    as 'viewer'. Elevated roles are granted afterwards by an existing admin
--    (via the admin-users Edge Function) or via claim_first_admin() below.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, username, role)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', ''),
    COALESCE(new.raw_user_meta_data->>'username', ''),
    'viewer'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. One-time, atomic "become the first admin" claim used by the mosque
--    registration screen. Succeeds only if no admin exists yet anywhere in
--    this project, so it can never be used to create a second admin.
CREATE OR REPLACE FUNCTION public.claim_first_admin()
RETURNS void AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin') THEN
    RAISE EXCEPTION 'An admin already exists for this mosque';
  END IF;

  UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found for current user';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.claim_first_admin() TO authenticated;

-- 5. Public, side-effect-free check so the registration screen can show a
--    friendly "already registered" message before the user fills the form,
--    without needing SELECT access to public.profiles itself (anon has none).
CREATE OR REPLACE FUNCTION public.mosque_admin_exists()
RETURNS boolean AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin');
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE;

GRANT EXECUTE ON FUNCTION public.mosque_admin_exists() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
