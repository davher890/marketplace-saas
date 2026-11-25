-- =============================================================================
-- Columns of the monthly orders file (Excel), chosen by the admin.
--
-- * shop_settings.order_export_columns: the columns of the file, in order,
--   by key ('order_number', 'created_at', 'items', ...; the list is in
--   server/services/orderExport.ts). NULL: every column, in the default order.
--   Set from Admin → Resumen → "Columnas del Excel".
--
-- Run before deploying the API that uses it. Safe to run more than once.
-- (Migration 11 is the online payment one, in its own pull request.)
-- =============================================================================

alter table dona_galleta.shop_settings
  add column if not exists order_export_columns text[];

notify pgrst, 'reload schema';
