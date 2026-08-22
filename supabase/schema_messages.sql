-- ============================================================
-- HOMELY APP - In-app messaging between guest and host
-- Run this AFTER schema_bookings.sql and schema_host_bookings.sql
-- ============================================================
-- One conversation per booking - not a standalone inbox. This keeps
-- things simple (no separate "start a conversation" flow) and
-- unambiguous (a message is always about a specific trip), matching
-- the "Message" action on both HostBookingDetailScreen and the
-- guest's BookingDetailScreen.

create table if not exists public.messages (
  id uuid default gen_random_uuid() primary key,
  booking_id uuid references public.bookings(id) on delete cascade not null,
  sender_id uuid references auth.users(id) on delete cascade not null,
  recipient_id uuid references auth.users(id) on delete cascade not null,
  body text not null,
  created_at timestamptz default now(),
  -- Set once the recipient has actually opened the conversation (see
  -- MessagesService.markRead) - null means unread. Kept per-message
  -- rather than a single "last read" timestamp on the booking so a
  -- future unread-count badge can just count nulls.
  read_at timestamptz
);

alter table public.messages enable row level security;

-- A message is only ever visible to its two participants - the guest
-- who made the booking and the host who owns the listing being
-- booked. Checked against bookings/places directly (same join
-- pattern as "Hosts can view bookings on their own listings" in
-- schema_host_bookings.sql) rather than trusting sender_id/
-- recipient_id alone, since a client could otherwise claim to be
-- either side.
create policy "Participants can view their booking's messages"
  on public.messages for select
  using (
    exists (
      select 1 from public.bookings b
      join public.places p on p.id = b.place_id
      where b.id = messages.booking_id
        and (b.user_id = auth.uid() or p.host_id = auth.uid())
    )
  );

-- A participant can only send as themselves, and only to the other
-- participant on that same booking - stops a guest or host from
-- messaging as, or to, someone with no connection to the booking.
create policy "Participants can send messages on their own bookings"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.bookings b
      join public.places p on p.id = b.place_id
      where b.id = messages.booking_id
        and (
          (b.user_id = auth.uid() and recipient_id = p.host_id)
          or (p.host_id = auth.uid() and recipient_id = b.user_id)
        )
    )
  );

-- The only update either side should ever make to a message they
-- didn't send is marking it read once they've seen it.
create policy "Recipients can mark their messages as read"
  on public.messages for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create index if not exists idx_messages_booking_id
  on public.messages (booking_id, created_at);
create index if not exists idx_messages_recipient_unread
  on public.messages (recipient_id, read_at);

-- Realtime: lets ChatScreen use Supabase's `.stream()` to get new
-- messages pushed instantly instead of polling. Wrapped so re-running
-- this file is safe even if the table's already published.
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then
  null;
end $$;
