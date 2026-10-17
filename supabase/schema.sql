-- ParlorEase database schema
-- Run this whole file in Supabase SQL Editor after creating a new project.
create extension if not exists pgcrypto;

create type public.user_role as enum ('customer', 'admin');
create type public.appointment_status as enum ('pending','confirmed','checked_in','in_progress','completed','cancelled','no_show');
create type public.payment_status as enum ('unpaid','partially_paid','paid','refunded');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now()
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 100),
  category text not null default 'Other' check (char_length(trim(category)) between 2 and 50),
  description text not null default '' check (char_length(description) <= 500),
  price numeric(10,2) not null check (price >= 0 and price <= 1000000),
  duration_minutes integer not null check (duration_minutes between 10 and 600),
  active boolean not null default true,
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(trim(full_name)) between 2 and 100),
  title text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.staff_services (
  staff_id uuid not null references public.staff(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  primary key (staff_id, service_id)
);

create table public.staff_working_hours (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6), -- 0 Sunday
  starts_at time not null default '09:00',
  ends_at time not null default '18:00',
  is_working boolean not null default true,
  check (ends_at > starts_at),
  unique (staff_id, weekday)
);

create table public.staff_time_off (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null default '',
  check (ends_at > starts_at)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  booking_code text not null unique default ('PE-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  customer_name text not null check (char_length(trim(customer_name)) between 2 and 100),
  customer_email text not null check (char_length(customer_email) <= 254),
  customer_phone text not null check (char_length(trim(customer_phone)) between 5 and 30),
  service_id uuid not null references public.services(id) on delete restrict,
  staff_id uuid references public.staff(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.appointment_status not null default 'pending',
  payment_status public.payment_status not null default 'unpaid',
  total_price numeric(10,2) not null check (total_price >= 0),
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index appointments_starts_at_idx on public.appointments(starts_at);
create index appointments_status_idx on public.appointments(status);
create index appointments_service_idx on public.appointments(service_id);
create index appointments_staff_time_idx on public.appointments(staff_id, starts_at, ends_at);

create table public.salon_settings (
  id integer primary key default 1 check (id = 1),
  salon_name text not null default 'ParlorEase',
  address text not null default '',
  phone text not null default '',
  email text not null default '',
  opening_hours text not null default 'Monday–Saturday, 9 AM–6 PM',
  timezone text not null default 'Asia/Manila',
  booking_notice_hours integer not null default 2 check (booking_notice_hours between 0 and 720),
  cancellation_notice_hours integer not null default 24 check (cancellation_notice_hours between 0 and 720),
  updated_at timestamptz not null default now()
);
insert into public.salon_settings (id) values (1) on conflict (id) do nothing;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
create trigger services_updated_at before update on public.services for each row execute function public.set_updated_at();
create trigger appointments_updated_at before update on public.appointments for each row execute function public.set_updated_at();
create trigger salon_settings_updated_at before update on public.salon_settings for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'customer')
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin');
$$;

-- Public availability returns only time slots; private customer/appointment records are never exposed.
create or replace function public.get_available_slots(p_service_id uuid, p_date date, p_staff_id uuid default null)
returns table(slot_time timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_duration integer;
  v_slot timestamp;
  v_start timestamptz;
  v_end timestamptz;
  v_tz text := 'Asia/Manila';
begin
  select s.duration_minutes into v_duration from public.services s where s.id = p_service_id and s.active = true;
  if v_duration is null or p_date < (now() at time zone v_tz)::date or p_date > ((now() at time zone v_tz)::date + 90) then return; end if;
  for v_slot in select (p_date + time '09:00') + (n * interval '30 minutes') from generate_series(0,17) as gs(n) loop
    v_start := timezone(v_tz, v_slot);
    v_end := v_start + make_interval(mins => v_duration);
    if v_start < now() + interval '2 hours' or (v_end at time zone v_tz)::time > time '18:00' then continue; end if;
    if exists (
      select 1 from public.staff st
      left join public.staff_working_hours wh on wh.staff_id=st.id and wh.weekday=extract(dow from p_date)::smallint
      where st.active = true and (p_staff_id is null or st.id=p_staff_id)
        and coalesce(wh.is_working, extract(dow from p_date)::integer <> 0) = true
        and (wh.id is null or ((v_start at time zone v_tz)::time >= wh.starts_at and (v_end at time zone v_tz)::time <= wh.ends_at))
        and not exists (select 1 from public.staff_time_off off where off.staff_id=st.id and tstzrange(off.starts_at,off.ends_at,'[)') && tstzrange(v_start,v_end,'[)'))
        and not exists (select 1 from public.appointments a where a.staff_id=st.id and a.status not in ('cancelled','no_show') and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(v_start,v_end,'[)'))
        and (not exists(select 1 from public.staff_services ss where ss.staff_id=st.id) or exists(select 1 from public.staff_services ss where ss.staff_id=st.id and ss.service_id=p_service_id))
    ) then return query select v_start; end if;
  end loop;
end;
$$;

-- Public booking function: only inserts a pending booking after validating price, staff and conflicts.
-- A date-level advisory lock serializes simultaneous submissions for the same local date.
create or replace function public.create_booking(
  p_customer_name text,
  p_customer_email text,
  p_customer_phone text,
  p_service_id uuid,
  p_staff_id uuid,
  p_starts_at timestamptz,
  p_note text default null
)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_service public.services%rowtype;
  v_staff_id uuid;
  v_end timestamptz;
  v_code text;
  v_tz text := 'Asia/Manila';
begin
  if char_length(trim(coalesce(p_customer_name,''))) < 2 or char_length(trim(p_customer_name)) > 100 then raise exception 'INVALID_CUSTOMER_NAME'; end if;
  if char_length(trim(coalesce(p_customer_email,''))) < 5 or char_length(p_customer_email) > 254 or position('@' in p_customer_email) < 2 then raise exception 'INVALID_EMAIL'; end if;
  if char_length(trim(coalesce(p_customer_phone,''))) < 5 or char_length(trim(p_customer_phone)) > 30 then raise exception 'INVALID_PHONE'; end if;
  if char_length(coalesce(p_note,'')) > 500 then raise exception 'NOTE_TOO_LONG'; end if;
  if (select count(*) from public.appointments a where a.created_at > now() - interval '24 hours' and (lower(a.customer_email)=lower(trim(p_customer_email)) or a.customer_phone=trim(p_customer_phone))) >= 5 then raise exception 'BOOKING_RATE_LIMIT'; end if;
  if p_starts_at is null or p_starts_at < now() + interval '2 hours' or p_starts_at > now() + interval '90 days' then raise exception 'INVALID_APPOINTMENT_TIME'; end if;
  if extract(minute from (p_starts_at at time zone v_tz))::integer % 30 <> 0 or extract(second from (p_starts_at at time zone v_tz)) <> 0 then raise exception 'INVALID_APPOINTMENT_TIME'; end if;
  perform pg_advisory_xact_lock(hashtext('parlorease-booking-' || ((p_starts_at at time zone v_tz)::date)::text));
  select * into v_service from public.services where id=p_service_id and active=true;
  if not found then raise exception 'SERVICE_UNAVAILABLE'; end if;
  v_end := p_starts_at + make_interval(mins => v_service.duration_minutes);
  if (v_end at time zone v_tz)::time > time '18:00' or (p_starts_at at time zone v_tz)::time < time '09:00' then raise exception 'OUTSIDE_BUSINESS_HOURS'; end if;
  if p_staff_id is not null then
    select st.id into v_staff_id from public.staff st
    left join public.staff_working_hours wh on wh.staff_id=st.id and wh.weekday=extract(dow from (p_starts_at at time zone v_tz))::smallint
    where st.id=p_staff_id and st.active=true and coalesce(wh.is_working, extract(dow from (p_starts_at at time zone v_tz))::integer <> 0)=true
      and (wh.id is null or ((p_starts_at at time zone v_tz)::time >= wh.starts_at and (v_end at time zone v_tz)::time <= wh.ends_at))
      and not exists(select 1 from public.staff_time_off off where off.staff_id=st.id and tstzrange(off.starts_at,off.ends_at,'[)') && tstzrange(p_starts_at,v_end,'[)'))
      and not exists(select 1 from public.appointments a where a.staff_id=st.id and a.status not in ('cancelled','no_show') and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(p_starts_at,v_end,'[)'))
      and (not exists(select 1 from public.staff_services ss where ss.staff_id=st.id) or exists(select 1 from public.staff_services ss where ss.staff_id=st.id and ss.service_id=p_service_id));
  else
    select st.id into v_staff_id from public.staff st
    left join public.staff_working_hours wh on wh.staff_id=st.id and wh.weekday=extract(dow from (p_starts_at at time zone v_tz))::smallint
    where st.active=true and coalesce(wh.is_working, extract(dow from (p_starts_at at time zone v_tz))::integer <> 0)=true
      and (wh.id is null or ((p_starts_at at time zone v_tz)::time >= wh.starts_at and (v_end at time zone v_tz)::time <= wh.ends_at))
      and not exists(select 1 from public.staff_time_off off where off.staff_id=st.id and tstzrange(off.starts_at,off.ends_at,'[)') && tstzrange(p_starts_at,v_end,'[)'))
      and not exists(select 1 from public.appointments a where a.staff_id=st.id and a.status not in ('cancelled','no_show') and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(p_starts_at,v_end,'[)'))
      and (not exists(select 1 from public.staff_services ss where ss.staff_id=st.id) or exists(select 1 from public.staff_services ss where ss.staff_id=st.id and ss.service_id=p_service_id))
    order by st.full_name limit 1;
  end if;
  if v_staff_id is null then raise exception 'SLOT_UNAVAILABLE'; end if;
  insert into public.appointments(customer_name,customer_email,customer_phone,service_id,staff_id,starts_at,ends_at,status,payment_status,total_price,note)
  values(trim(p_customer_name),lower(trim(p_customer_email)),trim(p_customer_phone),p_service_id,v_staff_id,p_starts_at,v_end,'pending','unpaid',v_service.price,trim(coalesce(p_note,'')))
  returning booking_code into v_code;
  return jsonb_build_object('booking_code',v_code,'status','pending');
end;
$$;

-- Grants: anonymous visitors can only read active public catalog and call limited RPCs.
grant usage on schema public to anon, authenticated;
grant select on public.services, public.staff, public.staff_services, public.staff_working_hours, public.salon_settings to anon;
grant select, insert, update, delete on public.profiles, public.services, public.staff, public.staff_services, public.staff_working_hours, public.staff_time_off, public.appointments, public.salon_settings to authenticated;
grant select on public.services to anon, authenticated;
grant select on public.staff to anon, authenticated;
grant select on public.salon_settings to anon, authenticated;
grant execute on function public.get_available_slots(uuid,date,uuid) to anon, authenticated;
grant execute on function public.create_booking(text,text,text,uuid,uuid,timestamptz,text) to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
revoke all on function public.create_booking(text,text,text,uuid,uuid,timestamptz,text) from public;
revoke all on function public.get_available_slots(uuid,date,uuid) from public;

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.staff enable row level security;
alter table public.staff_services enable row level security;
alter table public.staff_working_hours enable row level security;
alter table public.staff_time_off enable row level security;
alter table public.appointments enable row level security;
alter table public.salon_settings enable row level security;

create policy "Users can read own profile" on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy "Admins can manage profiles" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Public can read active services" on public.services for select to anon, authenticated using (active=true or public.is_admin());
create policy "Admins manage services" on public.services for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Public can read active staff" on public.staff for select to anon, authenticated using (active=true or public.is_admin());
create policy "Admins manage staff" on public.staff for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Public can read staff service mapping" on public.staff_services for select to anon, authenticated using (true);
create policy "Admins manage staff services" on public.staff_services for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Public can read staff hours" on public.staff_working_hours for select to anon, authenticated using (true);
create policy "Admins manage staff hours" on public.staff_working_hours for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admins manage staff time off" on public.staff_time_off for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admins read appointments" on public.appointments for select to authenticated using (public.is_admin());
create policy "Admins update appointments" on public.appointments for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Public can read salon contact settings" on public.salon_settings for select to anon, authenticated using (true);
create policy "Admins manage salon settings" on public.salon_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Seed examples for the first visual preview. Edit/remove these after setup as needed.
insert into public.services(name,category,description,price,duration_minutes,active) values
('Signature Haircut','Hair','A considered cut, finished with a style that feels unmistakably you.',450,45,true),
('Color & Glow','Hair','Personalized color with a glossy, polished finish.',1800,120,true),
('Classic Manicure','Nails','A tidy shape, careful cuticle care and your chosen finish.',350,40,true),
('Radiance Facial','Skin','A refreshing facial ritual for a softer, brighter-looking glow.',950,60,true),
('Wash & Blowout','Hair','A salon-fresh finish with movement, volume and shine.',550,45,true),
('Spa Pedicure','Nails','A restorative foot-care treatment with a clean, elegant finish.',600,55,true)
on conflict do nothing;
insert into public.staff(full_name,title,active) values
('Ana Reyes','Senior stylist',true),('Mika Santos','Beauty specialist',true),('Jo Villanueva','Nail artist',true)
on conflict do nothing;
