-- =====================================================
-- EXTENSIONS CONFIGURATION
-- Required extensions for the database
-- =====================================================

-- UUID Generation (installed in extensions schema)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- GraphQL Support
CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;

-- JWT Token handling
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;

-- Cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Async HTTP requests (for Edge Functions)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

-- Query statistics (for performance monitoring)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;

-- Supabase Vault (for secrets management)
-- Note: This is managed by Supabase automatically
-- CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- PL/pgSQL (default, always installed)
-- CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
