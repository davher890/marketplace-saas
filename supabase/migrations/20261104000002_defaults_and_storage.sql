-- =============================================================================
-- Default settings row and storage bucket. Safe to run more than once.
--
-- Row Level Security is in the next file (...03_rls_policies.sql).
-- =============================================================================

-- Single shop settings row (shipping cost, free-shipping threshold, contact).
insert into public.shop_settings (id, shipping_flat_cents, free_shipping_threshold_cents, contact_email, contact_phone)
values (true, 495, 5000, 'donagalletashop@gmail.com', '676 00 35 63')
on conflict (id) do nothing;

-- Public bucket for product images. Files are publicly readable through their
-- public URL; uploads use signed URLs issued by the API.
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;
