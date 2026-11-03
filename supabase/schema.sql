-- T-Money Entertainment: request and live-queue schema
-- Apply in Supabase SQL Editor. No guest phone numbers are collected.
-- Guest names and request details are automatically deleted after 48 hours.

create extension if not exists pgcrypto;
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.karaoke_events (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'T-Money Live Karaoke',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists karaoke_events_one_active
  on public.karaoke_events (is_active)
  where is_active = true;

create table if not exists public.karaoke_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.karaoke_events(id) on delete cascade,
  singer_name text not null check (char_length(trim(singer_name)) between 1 and 60),
  song_title text not null check (char_length(trim(song_title)) between 1 and 120),
  artist text check (artist is null or char_length(trim(artist)) <= 120),
  status text not null default 'pending'
    check (status in ('pending', 'queued', 'now_singing')),
  queue_position integer,
  created_at timestamptz not null default now(),
  constraint karaoke_queue_position_valid
    check ((status = 'queued' and queue_position is not null and queue_position > 0)
        or (status <> 'queued' and queue_position is null))
);

create index if not exists karaoke_requests_event_created
  on public.karaoke_requests (event_id, created_at desc);
create index if not exists karaoke_requests_event_queue
  on public.karaoke_requests (event_id, status, queue_position);

alter table public.karaoke_events enable row level security;
alter table public.karaoke_requests enable row level security;

-- Public guests can identify the current event.
drop policy if exists "Public can view active event" on public.karaoke_events;
create policy "Public can view active event"
  on public.karaoke_events for select to anon, authenticated
  using (is_active = true);

-- Only the DJ role (stored in Supabase app_metadata) can manage events.
drop policy if exists "DJ can manage events" on public.karaoke_events;
create policy "DJ can manage events"
  on public.karaoke_events for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'dj')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'dj');

-- Guests may submit requests only to the active event.
drop policy if exists "Guests can submit requests to active event" on public.karaoke_requests;
create policy "Guests can submit requests to active event"
  on public.karaoke_requests for insert to anon, authenticated
  with check (
    exists (
      select 1 from public.karaoke_events e
      where e.id = event_id and e.is_active = true
    )
    and status = 'pending'
    and queue_position is null
  );

-- Public sees only the active event's approved rotation, never the unapproved inbox.
drop policy if exists "Public can view active queue" on public.karaoke_requests;
create policy "Public can view active queue"
  on public.karaoke_requests for select to anon, authenticated
  using (
    status in ('queued', 'now_singing')
    and created_at >= now() - interval '48 hours'
    and exists (
      select 1 from public.karaoke_events e
      where e.id = event_id and e.is_active = true
    )
  );

-- DJ can see all unexpired incoming requests and manage the rotation.
drop policy if exists "DJ can view all current requests" on public.karaoke_requests;
create policy "DJ can view all current requests"
  on public.karaoke_requests for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'dj');

drop policy if exists "DJ can update requests" on public.karaoke_requests;
create policy "DJ can update requests"
  on public.karaoke_requests for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'dj')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'dj');

drop policy if exists "DJ can delete requests" on public.karaoke_requests;
create policy "DJ can delete requests"
  on public.karaoke_requests for delete to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'dj');

grant usage on schema public to anon, authenticated;
grant select on public.karaoke_events to anon, authenticated;
grant select on public.karaoke_requests to anon, authenticated;
revoke insert, update, delete on public.karaoke_requests from anon;
grant insert (event_id, singer_name, song_title, artist) on public.karaoke_requests to anon, authenticated;
grant update (status, queue_position) on public.karaoke_requests to authenticated;
grant delete on public.karaoke_requests to authenticated;

-- The DJ-only RPCs keep queue changes atomic.
create or replace function public.dj_accept_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_next_position integer;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'dj' then
    raise exception 'DJ access required';
  end if;

  select event_id into v_event_id
  from public.karaoke_requests
  where id = p_request_id and status = 'pending'
  for update;

  if v_event_id is null then
    raise exception 'Pending request not found';
  end if;

  select coalesce(max(queue_position), 0) + 1 into v_next_position
  from public.karaoke_requests
  where event_id = v_event_id and status = 'queued';

  update public.karaoke_requests
  set status = 'queued', queue_position = v_next_position
  where id = p_request_id;
end;
$$;

create or replace function public.dj_advance_queue()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_next_id uuid;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'dj' then
    raise exception 'DJ access required';
  end if;

  select id into v_event_id
  from public.karaoke_events
  where is_active = true
  limit 1
  for update;

  if v_event_id is null then
    raise exception 'No active karaoke session';
  end if;

  -- Advancing removes the previous performer; no played-history is retained.
  delete from public.karaoke_requests
  where event_id = v_event_id and status = 'now_singing';

  select id into v_next_id
  from public.karaoke_requests
  where event_id = v_event_id and status = 'queued'
  order by queue_position asc, created_at asc
  limit 1
  for update;

  if v_next_id is not null then
    update public.karaoke_requests
    set status = 'now_singing', queue_position = null
    where id = v_next_id;

    with ordered as (
      select id, row_number() over (order by queue_position asc, created_at asc) as new_position
      from public.karaoke_requests
      where event_id = v_event_id and status = 'queued'
    )
    update public.karaoke_requests r
    set queue_position = ordered.new_position
    from ordered
    where r.id = ordered.id;
  end if;

  return v_next_id;
end;
$$;

revoke all on function public.dj_accept_request(uuid) from public, anon;
revoke all on function public.dj_advance_queue() from public, anon;
grant execute on function public.dj_accept_request(uuid) to authenticated;
grant execute on function public.dj_advance_queue() to authenticated;

-- Ensure one active session exists for initial setup.
insert into public.karaoke_events (name, is_active)
select 'T-Money Live Karaoke', true
where not exists (select 1 from public.karaoke_events where is_active = true);

-- Delete all request names and details after 48 hours. No historical "played" list.
do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'tmoney-delete-requests-after-48h';

  perform cron.schedule(
    'tmoney-delete-requests-after-48h',
    '0 * * * *',
    $job$delete from public.karaoke_requests where created_at < now() - interval '48 hours';$job$
  );
end;
$$;
