-- =====================================================
-- REALTIME CONFIGURATION
-- Tables enabled for Realtime subscriptions
-- =====================================================

-- Note: Realtime is enabled at the table level via Supabase Dashboard
-- or via the supabase_realtime publication

-- The following tables have Realtime enabled in production:
-- (Based on realtime.subscription table with 2 active subscriptions)

-- Enable Realtime for key tables
-- This is done via ALTER PUBLICATION in Supabase

-- Example of how to enable realtime for a table:
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_routes;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_route_stops;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_route_shipments;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.lab_tours;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.lab_tour_stops;

-- =====================================================
-- REALTIME POLICIES
-- RLS policies for Realtime access
-- =====================================================

-- Note: Realtime respects RLS policies
-- Ensure appropriate SELECT policies exist on tables
-- that need Realtime subscriptions

-- For tables without RLS, all authenticated users can subscribe
-- For tables with RLS, only rows matching policies are sent
