-- Repair Data API exposure and remove legacy over-broad policies.
-- Safe to run repeatedly on existing Supabase projects.

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

DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.transactions;
DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.activities;
DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.mosque_profiles;
DROP POLICY IF EXISTS "Allow authenticated select audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Allow authenticated insert audit_logs" ON public.audit_logs;

DROP POLICY IF EXISTS "Admin and Bendahara can modify transactions" ON public.transactions;
CREATE POLICY "Admin and Bendahara can modify transactions"
ON public.transactions
FOR ALL
USING (
  auth.role() = 'authenticated' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin', 'bendahara')
  )
)
WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin', 'bendahara')
  )
);

DROP POLICY IF EXISTS "Admin and Sekretaris can modify activities" ON public.activities;
CREATE POLICY "Admin and Sekretaris can modify activities"
ON public.activities
FOR ALL
USING (
  auth.role() = 'authenticated' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin', 'sekretaris')
  )
)
WITH CHECK (
  auth.role() = 'authenticated' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin', 'sekretaris')
  )
);

DROP POLICY IF EXISTS "Authenticated Upload Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Upload Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload Own Proofs" ON storage.objects;
CREATE POLICY "Authenticated Upload Own Proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'proofs'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated Update Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Proofs" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Own Proofs" ON storage.objects;
CREATE POLICY "Authenticated Update Own Proofs"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'proofs'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'proofs'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated Delete Own Proofs" ON storage.objects;
CREATE POLICY "Authenticated Delete Own Proofs"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'proofs'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated Upload Logos" ON storage.objects;
DROP POLICY IF EXISTS "Auth Upload Logos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload Own Logos" ON storage.objects;
CREATE POLICY "Authenticated Upload Own Logos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'logos'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated Update Logos" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Logos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Own Logos" ON storage.objects;
CREATE POLICY "Authenticated Update Own Logos"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'logos'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'logos'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated Delete Own Logos" ON storage.objects;
CREATE POLICY "Authenticated Delete Own Logos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'logos'
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

NOTIFY pgrst, 'reload schema';
