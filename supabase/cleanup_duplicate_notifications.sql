-- Removes duplicate lazily-generated notifications (checkin_reminder,
-- checkin_log_reminder, review_prompt), keeping the OLDEST row in
-- each duplicate set and deleting the rest. One-off cleanup - not
-- needed again once the two code fixes above are in place.
delete from public.notifications a
using public.notifications b
where a.user_id = b.user_id
  and a.booking_id = b.booking_id
  and a.type = b.type
  and a.milestone_days is not distinct from b.milestone_days
  and a.type in ('checkin_reminder', 'checkin_log_reminder', 'review_prompt')
  and a.created_at > b.created_at;
