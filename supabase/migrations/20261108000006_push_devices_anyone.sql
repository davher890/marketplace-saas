-- =============================================================================
-- Every app install can receive push notifications, not only admins'.
--
-- The Android app asks everyone for the notification permission when it
-- opens and registers its Firebase Installation ID. `user_id` is the account
-- signed in on that device, or null when nobody is: the device can still get
-- shop news, but only devices of admins get new-order notices.
--
-- Safe to run more than once.
-- =============================================================================

alter table public.push_devices alter column user_id drop not null;
