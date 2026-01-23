# Security Advisories

> Exported from Supabase Dashboard on 2026-01-23

## Critical Issues (RLS Disabled)

The following tables have RLS **disabled** but are exposed via PostgREST:

| Table | Status |
|-------|--------|
| `driver_route_shipments` | RLS disabled, has policies defined |
| `lab_tour_late_stops` | RLS disabled, has policies defined |
| `drivers` | RLS disabled |
| `depot_shipments` | RLS disabled |
| `driver_routes` | RLS disabled |
| `laboratory_clients` | RLS disabled |
| `location_photos` | RLS disabled |
| `lab_tours` | RLS disabled |
| `lab_tour_shipments` | RLS disabled |
| `depot` | RLS disabled |
| `lab_tour_stops` | RLS disabled |
| `locations` | RLS disabled |
| `laboratories` | RLS disabled |
| `driver_route_stops` | RLS disabled |
| `laboratory_clients_audit` | RLS disabled |
| `driver_statistics` | RLS disabled |
| `admins` | RLS disabled |
| `administrators` | RLS disabled |

### Tables with RLS Enabled

| Table | RLS Status |
|-------|------------|
| `billing_configurations` | Enabled |
| `billing_invoices` | Enabled |
| `billing_invoice_items` | Enabled |
| `laboratory_statistics` | Enabled |
| `error_logs` | Enabled |

## Security Definer Views

The following views use `SECURITY DEFINER` which may bypass RLS:

- `billing_reports`
- `error_stats`
- `critical_errors_recent`
- `v_driver_statistics_with_details`
- `v_recent_driver_statistics`
- `v_driver_performance_summary`

## Functions with Mutable Search Path

Multiple functions have mutable `search_path` which can be a security concern:

- `generate_driver_routes`
- `calculate_driver_statistics`
- `calculate_laboratory_statistics`
- `generate_lab_tour_shipments`
- ... and 40+ more

## Recommendations

1. **Enable RLS on all public tables** or move them to a non-exposed schema
2. **Add explicit search_path** to all functions
3. **Review SECURITY DEFINER views** for potential data leakage
4. **Enable leaked password protection** in Auth settings
5. **Upgrade Postgres version** to receive security patches

## Reference

- [Supabase RLS Guide](https://supabase.com/docs/guides/auth/row-level-security)
- [Database Linter Docs](https://supabase.com/docs/guides/database/database-linter)
