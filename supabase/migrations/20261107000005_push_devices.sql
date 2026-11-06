-- =============================================================================
-- Devices that receive push notifications (Firebase Cloud Messaging).
--
-- The Android app registers its Firebase Installation ID (FID, FCM's
-- direct-send target that replaces registration tokens) when an admin signs
-- in, and the API notifies those devices when a new order is placed. An FID
-- belongs to one app install, so registering it again (e.g. another admin on
-- the same phone) moves it to the new user. The API removes FIDs that FCM
-- reports as no longer valid (app uninstalled, signed out).
--
-- Safe to run more than once.
-- =============================================================================

create table if not exists public.push_devices (
  fid         text primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  platform    text not null default 'android' check (platform in ('android')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- "Devices of these users" lookups when sending.
create index if not exists push_devices_user_id_idx on public.push_devices (user_id);

-- Row Level Security with no policies: only the service role (the API's admin
-- client, after checking the admin role) reads and writes them.
alter table public.push_devices enable row level security;
