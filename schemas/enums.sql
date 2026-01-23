-- =====================================================
-- CUSTOM ENUMS
-- Custom enumerated types used in the database
-- =====================================================

-- Late stop status for lab tour late stop requests
CREATE TYPE public.late_stop_status AS ENUM (
  'pending',
  'approved',
  'rejected'
);

COMMENT ON TYPE public.late_stop_status IS 'Status for late stop requests: pending (awaiting review), approved (accepted), rejected (denied)';
