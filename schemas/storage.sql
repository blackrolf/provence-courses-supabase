-- =====================================================
-- STORAGE CONFIGURATION
-- Exported from Supabase Cloud Project
-- =====================================================

-- Storage Buckets
-- 2 buckets configured in production

-- Bucket 1: location-photos (for location reference photos)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'location-photos',
  'location-photos',
  true,
  10485760, -- 10MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
) ON CONFLICT (id) DO NOTHING;

-- Bucket 2: photos-delivery (for delivery proof photos)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'photos-delivery',
  'photos-delivery',
  true,
  10485760, -- 10MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- STORAGE POLICIES
-- =====================================================

-- Policy: Allow public read access to location-photos
CREATE POLICY "Public read access for location-photos"
ON storage.objects FOR SELECT
USING (bucket_id = 'location-photos');

-- Policy: Allow authenticated users to upload to location-photos
CREATE POLICY "Authenticated users can upload to location-photos"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'location-photos'
  AND auth.role() = 'authenticated'
);

-- Policy: Allow public read access to photos-delivery
CREATE POLICY "Public read access for photos-delivery"
ON storage.objects FOR SELECT
USING (bucket_id = 'photos-delivery');

-- Policy: Allow authenticated users to upload to photos-delivery
CREATE POLICY "Authenticated users can upload to photos-delivery"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'photos-delivery'
  AND auth.role() = 'authenticated'
);

-- Policy: Allow users to delete their own uploads
CREATE POLICY "Users can delete own uploads"
ON storage.objects FOR DELETE
USING (auth.uid()::text = owner_id);
