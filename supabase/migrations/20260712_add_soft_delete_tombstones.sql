-- Cross-device delete reconciliation via soft-delete tombstones.
--
-- Problem: a hard DELETE on one device never reached other devices. The app's
-- pull logic only inserts/updates rows the server returns; it can't learn that
-- a row disappeared. So a transaction or qurban payment deleted on phone A
-- stayed on phone B forever, leaving B's balances and qurban totals
-- permanently wrong.
--
-- Fix: the client no longer hard-DELETEs these rows. It stamps a nullable
-- deleted_at, which every device observes on its next incremental pull and then
-- mirrors by deleting its local copy. The existing handle_updated_at() BEFORE
-- UPDATE trigger bumps updated_at when deleted_at is set, so the pull cursor
-- picks the tombstone up. RLS is unchanged: the same FOR ALL role-gated
-- policies that previously authorized the DELETE authorize this UPDATE (none of
-- them pin columns).
--
-- Existing rows default to deleted_at = NULL (not deleted). Non-breaking.

alter table public.transactions        add column if not exists deleted_at timestamptz;
alter table public.activities          add column if not exists deleted_at timestamptz;
alter table public.qurban_packages     add column if not exists deleted_at timestamptz;
alter table public.qurban_participants add column if not exists deleted_at timestamptz;
alter table public.qurban_payments     add column if not exists deleted_at timestamptz;
