-- =============================================================================
-- Self Project — complete database schema
--
-- Run this once in the SQL editor of a fresh Supabase project. It creates every
-- table, view, security policy and the seeded exercise catalog and routines.
--
-- Safe to read before running: it only creates objects in the `public` schema
-- and never touches your auth data.
-- =============================================================================


-- =============================================================================
-- 1. REFERENCE DATA — the customisable part
--
-- Created first because the logging tables reference the exercise catalog.
-- =============================================================================

-- The exercise catalog.
create table public.exercise (
  id                text primary key,
  name              text not null,
  pattern           text not null,   -- squat|hinge|h_press|v_press|h_pull|v_pull|isolation
  side              text not null,   -- push | pull | legs  (groups the picker)
  is_anchor         boolean not null default false,
  counts_bodyweight boolean not null default false,
  sort_order        integer not null default 100
);

-- Fractional muscle attribution: 1.0 for a primary mover, 0.5 for a meaningful
-- secondary. Fractional counting is the quantification method that best
-- predicted hypertrophy in Pelland et al. 2025 (Sports Medicine), a
-- meta-regression across 67 studies and 2,058 participants.
create table public.exercise_muscle (
  exercise_id text not null references public.exercise(id) on delete cascade,
  muscle      text not null,
  fraction    numeric(3,2) not null check (fraction > 0 and fraction <= 1),
  primary key (exercise_id, muscle)
);

-- Routines are the workout templates the app pre-loads. Rotation order is
-- routine.position. Edit these to make the app follow your own program.
create table public.routine (
  id       text primary key,
  name     text not null,
  position integer not null
);

create table public.routine_item (
  routine_id       text    not null references public.routine(id) on delete cascade,
  position         integer not null,
  exercise_id      text    not null references public.exercise(id),
  home_exercise_id text    references public.exercise(id),   -- swapped in at "Home"
  target_sets      integer not null default 3,
  rep_low          integer not null,
  rep_high         integer not null,
  rest_seconds     integer not null default 150,
  is_core          boolean not null default true,
  primary key (routine_id, position)
);


-- =============================================================================
-- 2. LOGGING TABLES
-- =============================================================================

-- One row per day of body metrics.
create table public.body_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  logged_on   date not null,
  weight_lb   numeric(5,1),
  waist_in    numeric(4,1),
  sleep_hours numeric(3,1),
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, logged_on)
);

-- One row per training session.
create table public.workout (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  performed_on date not null,
  session_type text not null,          -- matches routine.name, or free text
  location     text,
  notes        text,
  created_at   timestamptz not null default now()
);

-- One row per working set.
create table public.lift_set (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  workout_id  uuid not null references public.workout(id) on delete cascade,
  exercise    text not null,           -- display label at time of logging
  exercise_id text references public.exercise(id),
  is_anchor   boolean not null default false,
  load_lb     numeric(6,1),
  reps        integer,
  set_index   integer not null default 1,   -- historical; the app numbers sets on read
  is_warmup   boolean not null default false,
  created_at  timestamptz not null default now()
);

-- Per-exercise notes within a session. Session-level notes live on workout.notes.
create table public.workout_exercise (
  workout_id  uuid not null references public.workout(id) on delete cascade,
  exercise_id text not null references public.exercise(id),
  user_id     uuid not null references auth.users(id) on delete cascade,
  note        text,
  updated_at  timestamptz not null default now(),
  primary key (workout_id, exercise_id)
);

-- Non-lifting work: swimming, cycling, walks, sprints, hikes.
create table public.activity (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  performed_on date not null,
  kind         text not null,
  minutes      integer,
  distance     numeric(6,2),
  unit         text,
  intensity    text,
  notes        text,
  created_at   timestamptz not null default now()
);

-- User-defined goals, checked automatically where measurable.
create table public.goal (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  kind         text not null,          -- lift | bodyweight | sessions | custom
  label        text not null,
  exercise_id  text references public.exercise(id),
  target_load  numeric(6,1),
  target_reps  integer,
  target_value numeric(7,2),
  achieved_on  date,
  created_at   timestamptz not null default now()
);


-- =============================================================================
-- 3. INDEXES
-- =============================================================================

create index on public.body_log (user_id, logged_on desc);
create index on public.workout  (user_id, performed_on desc);
create index on public.lift_set (user_id, exercise, created_at desc);
create index on public.lift_set (user_id, exercise_id, created_at desc);
create index on public.lift_set (workout_id);
create index on public.lift_set (workout_id, is_warmup);
create index on public.activity (user_id, performed_on desc);
create index on public.goal     (user_id, achieved_on);


-- =============================================================================
-- 4. ROW LEVEL SECURITY
--
-- Every user sees only their own rows. Reference data is world-readable to
-- signed-in users and writable by nobody through the API.
-- =============================================================================

alter table public.body_log          enable row level security;
alter table public.workout           enable row level security;
alter table public.lift_set          enable row level security;
alter table public.workout_exercise  enable row level security;
alter table public.activity        enable row level security;
alter table public.goal            enable row level security;
alter table public.exercise        enable row level security;
alter table public.exercise_muscle enable row level security;
alter table public.routine         enable row level security;
alter table public.routine_item    enable row level security;

create policy "own rows" on public.body_log
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own rows" on public.workout
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own rows" on public.lift_set
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own rows" on public.workout_exercise
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own rows" on public.activity
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own rows" on public.goal
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "read catalog"  on public.exercise        for select to authenticated using (true);
create policy "read catalog"  on public.exercise_muscle for select to authenticated using (true);
create policy "read routines" on public.routine         for select to authenticated using (true);
create policy "read routines" on public.routine_item    for select to authenticated using (true);

-- Keep updated_at honest on body_log upserts. Not exposed as an RPC.
create or replace function public.touch_updated_at()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

revoke execute on function public.touch_updated_at() from public, anon, authenticated;

create trigger body_log_touch before update on public.body_log
  for each row execute function public.touch_updated_at();


-- =============================================================================
-- 5. VIEWS
--
-- All views are security_invoker, so they inherit the caller's row level
-- security rather than the owner's. Each user sees only their own numbers.
-- =============================================================================

-- 7-day rolling weight average and week-over-week change.
create view public.weight_trend
with (security_invoker = true) as
with base as (
  select logged_on, weight_lb,
         round(avg(weight_lb) over (order by logged_on rows between 6 preceding and current row), 2) as avg_7d
  from public.body_log
  where weight_lb is not null
)
select logged_on, weight_lb, avg_7d,
       round(avg_7d - lag(avg_7d, 7) over (order by logged_on), 2) as change_vs_prior_week
from base;

-- Fractional weekly volume per muscle group. Warm-up sets are excluded everywhere —
-- they're recorded for your own reference but never counted as stimulus.
create view public.weekly_muscle_volume
with (security_invoker = true) as
select date_trunc('week', w.performed_on)::date as week_start,
       em.muscle,
       sum(em.fraction)::numeric(6,1) as sets
from public.lift_set ls
join public.workout w          on w.id = ls.workout_id
join public.exercise_muscle em on em.exercise_id = ls.exercise_id
where not ls.is_warmup
group by 1, 2;

create view public.weekly_total_volume
with (security_invoker = true) as
select week_start, sum(sets)::numeric(7,1) as total_sets
from public.weekly_muscle_volume group by 1;

create view public.weekly_sessions
with (security_invoker = true) as
select date_trunc('week', performed_on)::date as week_start,
       count(*) as sessions,
       string_agg(session_type, ', ' order by performed_on) as session_types
from public.workout group by 1 order by 1 desc;

-- Estimated 1RM (Epley) per exercise per day. Bodyweight-loaded movements add
-- current bodyweight so a +45 lb dip is comparable to a barbell lift.
create view public.exercise_e1rm_daily
with (security_invoker = true) as
with bw as (
  select coalesce((select weight_lb from public.body_log
    where weight_lb is not null order by logged_on desc limit 1), 185) as lb
)
select e.id as exercise_id, e.name, e.is_anchor, w.performed_on,
  max(round(((case when e.counts_bodyweight then ls.load_lb + (select lb from bw) else ls.load_lb end)
       * (1 + ls.reps::numeric / 30))::numeric, 1)) as e1rm,
  max(ls.load_lb) as top_load,
  count(*)        as sets
from public.lift_set ls
join public.workout  w on w.id = ls.workout_id
join public.exercise e on e.id = ls.exercise_id
where ls.reps > 0 and ls.load_lb is not null and not ls.is_warmup
group by 1, 2, 3, 4;

-- Best ever, best in the last 4 weeks, and best in the 4 weeks before that.
create view public.exercise_progress
with (security_invoker = true) as
select exercise_id, name, is_anchor,
  sum(sets)                                                   as total_sets,
  max(performed_on)                                           as last_performed,
  max(e1rm)                                                   as best_e1rm,
  max(e1rm) filter (where performed_on >= current_date - 28)  as best_28d,
  max(e1rm) filter (where performed_on <  current_date - 28
                      and performed_on >= current_date - 56)  as best_prev_28d
from public.exercise_e1rm_daily
group by 1, 2, 3;

-- Personal-best lookup used for the mid-session PR banner.
create view public.exercise_pr
with (security_invoker = true) as
select exercise_id, name, max(e1rm) as best_e1rm, max(top_load) as best_load
from public.exercise_e1rm_daily group by 1, 2;

-- One row per day anything happened, for the calendar.
create view public.daily_log
with (security_invoker = true) as
with days as (
  select performed_on from public.workout
  union
  select performed_on from public.activity
),
lifts as (
  select w.performed_on, count(distinct w.id) as sessions,
         string_agg(distinct w.session_type, '/') as types,
         count(ls.id) filter (where not ls.is_warmup) as sets,
         round(extract(epoch from (max(ls.created_at) - min(ls.created_at))) / 60)::int as minutes
  from public.workout w
  left join public.lift_set ls on ls.workout_id = w.id
  group by 1
),
acts as (
  select performed_on, count(*) as activities,
         string_agg(distinct kind, '/') as kinds, coalesce(sum(minutes), 0) as minutes
  from public.activity group by 1
)
select d.performed_on,
       coalesce(l.sessions, 0)   as sessions,
       l.types,
       coalesce(l.sets, 0)       as sets,
       coalesce(l.minutes, 0)    as lift_minutes,
       coalesce(a.activities, 0) as activities,
       a.kinds,
       coalesce(a.minutes, 0)    as activity_minutes
from days d
left join lifts l on l.performed_on = d.performed_on
left join acts  a on a.performed_on = d.performed_on;

-- Full detail for one session, including elapsed time. Powers the calendar day view.
create view public.session_detail
with (security_invoker = true) as
select w.id, w.performed_on, w.session_type, w.location, w.notes,
       min(ls.created_at) as started_at,
       max(ls.created_at) as ended_at,
       coalesce(round(extract(epoch from (max(ls.created_at) - min(ls.created_at))) / 60)::int, 0) as minutes,
       count(*) filter (where not ls.is_warmup) as work_sets,
       count(*) filter (where ls.is_warmup)     as warmup_sets
from public.workout w
left join public.lift_set ls on ls.workout_id = w.id
group by w.id, w.performed_on, w.session_type, w.location, w.notes;

create view public.training_summary
with (security_invoker = true) as
select
  (select count(*) from public.workout)  as total_sessions,
  (select count(*) from public.lift_set where not is_warmup) as total_sets,
  (select count(*) from public.activity) as total_activities,
  (select count(*) from public.workout
     where performed_on >= date_trunc('week', current_date)::date) as sessions_this_week,
  (select count(*) from public.workout
     where performed_on >= current_date - 28)                      as sessions_28d,
  (select coalesce(sum(minutes), 0) from public.activity
     where performed_on >= current_date - 28)                      as activity_minutes_28d;

create view public.goal_status
with (security_invoker = true) as
select g.id, g.kind, g.label, g.exercise_id, g.target_load, g.target_reps,
       g.target_value, g.achieved_on, g.created_at, e.name as exercise_name,
  case g.kind
    when 'lift' then exists (
      select 1 from public.lift_set ls
      where ls.exercise_id = g.exercise_id and not ls.is_warmup
        and ls.load_lb >= coalesce(g.target_load, 0)
        and ls.reps    >= coalesce(g.target_reps, 1))
    when 'bodyweight' then coalesce(
      (select avg_7d from public.weight_trend
        where avg_7d is not null order by logged_on desc limit 1), 0) >= coalesce(g.target_value, 0)
    when 'sessions' then (
      select count(*) from public.workout
       where performed_on >= date_trunc('week', current_date)::date) >= coalesce(g.target_value, 0)
    else false
  end as is_met
from public.goal g
left join public.exercise e on e.id = g.exercise_id;


-- =============================================================================
-- 6. SEED — exercise catalog
-- =============================================================================

insert into public.exercise (id, name, pattern, side, is_anchor, counts_bodyweight, sort_order) values
  ('weighted_pullup',  'Weighted pull-up',      'v_pull',    'pull', true,  true,  1),
  ('weighted_dip',     'Weighted dip',          'h_press',   'push', true,  true,  2),
  ('squat',            'Squat (heel-elevated)', 'squat',     'legs', true,  false, 3),
  ('hinge_rdl',        'Romanian deadlift',     'hinge',     'legs', true,  false, 4),
  ('deadlift',         'Deadlift',              'hinge',     'legs', false, false, 10),
  ('trap_bar_dl',      'Trap-bar deadlift',     'hinge',     'legs', false, false, 11),
  ('leg_press',        'Leg press',             'squat',     'legs', false, false, 12),
  ('hack_squat',       'Hack squat',            'squat',     'legs', false, false, 13),
  ('split_squat',      'Bulgarian split squat', 'squat',     'legs', false, false, 14),
  ('goblet_squat',     'Goblet / vest squat',   'squat',     'legs', false, false, 15),
  ('leg_extension',    'Leg extension',         'isolation', 'legs', false, false, 16),
  ('leg_curl',         'Leg curl',              'isolation', 'legs', false, false, 17),
  ('nordic_curl',      'Nordic curl',           'isolation', 'legs', false, true,  18),
  ('good_morning',     'Good morning',          'hinge',     'legs', false, false, 19),
  ('kb_swing',         'Kettlebell swing',      'hinge',     'legs', false, false, 20),
  ('calf_raise',       'Calf raise',            'isolation', 'legs', false, false, 21),
  ('bench_press',      'Bench press',           'h_press',   'push', false, false, 30),
  ('incline_press',    'Incline press',         'h_press',   'push', false, false, 31),
  ('machine_chest',    'Machine chest press',   'h_press',   'push', false, false, 32),
  ('pushup',           'Push-up (vest)',        'h_press',   'push', false, true,  33),
  ('chest_fly',        'Chest fly / pec deck',  'isolation', 'push', false, false, 34),
  ('ohp',              'Overhead press',        'v_press',   'push', false, false, 40),
  ('kb_press',         'KB front-rack press',   'v_press',   'push', false, false, 41),
  ('push_press',       'Push press',            'v_press',   'push', false, false, 42),
  ('lateral_raise',    'Lateral raise',         'isolation', 'push', false, false, 43),
  ('triceps_ext',      'Triceps extension',     'isolation', 'push', false, false, 44),
  ('cable_row',        'Cable row',             'h_pull',    'pull', false, false, 50),
  ('chest_supp_row',   'Chest-supported row',   'h_pull',    'pull', false, false, 51),
  ('kb_row',           'KB single-arm row',     'h_pull',    'pull', false, false, 52),
  ('barbell_row',      'Barbell row',           'h_pull',    'pull', false, false, 53),
  ('lat_pulldown',     'Lat pulldown',          'v_pull',    'pull', false, false, 54),
  ('chinup',           'Chin-up',               'v_pull',    'pull', false, true,  55),
  ('face_pull',        'Face pull',             'isolation', 'pull', false, false, 56),
  ('rear_delt_fly',    'Rear delt fly',         'isolation', 'pull', false, false, 57),
  ('biceps_curl',      'Biceps curl',           'isolation', 'pull', false, false, 58),
  ('hammer_curl',      'Hammer curl',           'isolation', 'pull', false, false, 59),
  ('mace_swing',       'Mace swing',            'isolation', 'pull', false, false, 60),
  ('ab_wheel',         'Ab wheel / core',       'isolation', 'pull', false, true,  61);


-- =============================================================================
-- 7. SEED — fractional muscle attribution
-- =============================================================================

insert into public.exercise_muscle (exercise_id, muscle, fraction) values
  ('weighted_pullup','Back',1.0),   ('weighted_pullup','Biceps',0.5),  ('weighted_pullup','Rear delts',0.5),
  ('chinup','Back',1.0),            ('chinup','Biceps',0.5),
  ('lat_pulldown','Back',1.0),      ('lat_pulldown','Biceps',0.5),
  ('cable_row','Back',1.0),         ('cable_row','Biceps',0.5),        ('cable_row','Rear delts',0.5),
  ('chest_supp_row','Back',1.0),    ('chest_supp_row','Biceps',0.5),   ('chest_supp_row','Rear delts',0.5),
  ('kb_row','Back',1.0),            ('kb_row','Biceps',0.5),           ('kb_row','Rear delts',0.5),
  ('barbell_row','Back',1.0),       ('barbell_row','Biceps',0.5),      ('barbell_row','Rear delts',0.5),
  ('weighted_dip','Chest',1.0),     ('weighted_dip','Triceps',1.0),    ('weighted_dip','Front delts',0.5),
  ('bench_press','Chest',1.0),      ('bench_press','Triceps',0.5),     ('bench_press','Front delts',0.5),
  ('incline_press','Chest',1.0),    ('incline_press','Triceps',0.5),   ('incline_press','Front delts',0.5),
  ('machine_chest','Chest',1.0),    ('machine_chest','Triceps',0.5),   ('machine_chest','Front delts',0.5),
  ('pushup','Chest',1.0),           ('pushup','Triceps',0.5),          ('pushup','Front delts',0.5),
  ('chest_fly','Chest',1.0),
  ('ohp','Front delts',1.0),        ('ohp','Triceps',0.5),             ('ohp','Side delts',0.5),
  ('kb_press','Front delts',1.0),   ('kb_press','Triceps',0.5),        ('kb_press','Side delts',0.5),
  ('push_press','Front delts',1.0), ('push_press','Triceps',0.5),      ('push_press','Side delts',0.5),
  ('lateral_raise','Side delts',1.0),
  ('face_pull','Rear delts',1.0),
  ('rear_delt_fly','Rear delts',1.0),
  ('biceps_curl','Biceps',1.0),
  ('hammer_curl','Biceps',1.0),
  ('triceps_ext','Triceps',1.0),
  ('squat','Quads',1.0),            ('squat','Glutes',0.5),
  ('leg_press','Quads',1.0),        ('leg_press','Glutes',0.5),
  ('hack_squat','Quads',1.0),       ('hack_squat','Glutes',0.5),
  ('goblet_squat','Quads',1.0),     ('goblet_squat','Glutes',0.5),
  ('split_squat','Quads',1.0),      ('split_squat','Glutes',1.0),
  ('leg_extension','Quads',1.0),
  ('hinge_rdl','Hamstrings',1.0),   ('hinge_rdl','Glutes',1.0),        ('hinge_rdl','Back',0.5),
  ('deadlift','Hamstrings',1.0),    ('deadlift','Glutes',1.0),         ('deadlift','Back',0.5),
  ('trap_bar_dl','Hamstrings',1.0), ('trap_bar_dl','Glutes',1.0),      ('trap_bar_dl','Quads',0.5),
  ('good_morning','Hamstrings',1.0),('good_morning','Glutes',0.5),
  ('kb_swing','Glutes',1.0),        ('kb_swing','Hamstrings',0.5),
  ('leg_curl','Hamstrings',1.0),
  ('nordic_curl','Hamstrings',1.0),
  ('calf_raise','Calves',1.0),
  ('mace_swing','Rear delts',0.5),  ('mace_swing','Core',1.0),
  ('ab_wheel','Core',1.0);


-- =============================================================================
-- 8. SEED — routines
--
-- THIS IS THE PART TO CHANGE FOR YOUR OWN PROGRAM.
-- `routine.position` sets the rotation order. The order below deliberately puts
-- the two heavily spine-loaded sessions (Push A's squat, Pull A's RDL) at
-- opposite ends of the cycle, so two consecutive training days never stack
-- them. Push B (leg press) and Pull B (kettlebell swings) are low-compression.
-- =============================================================================

insert into public.routine (id, name, position) values
  ('push_a','Push A',1), ('pull_b','Pull B',2), ('push_b','Push B',3), ('pull_a','Pull A',4);

insert into public.routine_item
  (routine_id, position, exercise_id, home_exercise_id, target_sets, rep_low, rep_high, rest_seconds, is_core) values
  -- Push A — the heavy squat day
  ('push_a',1,'squat','goblet_squat',3,6,10,180,true),
  ('push_a',2,'weighted_dip','weighted_dip',3,6,10,150,true),
  ('push_a',3,'bench_press','pushup',3,6,10,150,true),
  ('push_a',4,'ohp','kb_press',3,8,12,120,true),
  ('push_a',5,'lateral_raise','lateral_raise',3,12,20,75,false),
  ('push_a',6,'triceps_ext','triceps_ext',2,10,15,75,false),
  -- Pull B — ballistic hinge, low spinal load
  ('pull_b',1,'kb_swing','kb_swing',3,12,20,120,true),
  ('pull_b',2,'weighted_pullup','weighted_pullup',3,8,12,150,true),
  ('pull_b',3,'lat_pulldown','kb_row',3,10,15,120,true),
  ('pull_b',4,'nordic_curl','good_morning',3,10,15,120,true),
  ('pull_b',5,'rear_delt_fly','rear_delt_fly',3,15,20,75,false),
  ('pull_b',6,'hammer_curl','hammer_curl',3,10,15,75,false),
  ('pull_b',7,'calf_raise','calf_raise',3,10,15,75,false),
  -- Push B — machine-based quad work, low spinal load
  ('push_b',1,'leg_press','split_squat',3,8,12,150,true),
  ('push_b',2,'weighted_dip','weighted_dip',3,8,12,150,true),
  ('push_b',3,'incline_press','pushup',3,8,12,150,true),
  ('push_b',4,'push_press','push_press',3,10,15,120,true),
  ('push_b',5,'leg_extension','goblet_squat',3,12,15,75,false),
  ('push_b',6,'lateral_raise','lateral_raise',3,15,20,75,false),
  -- Pull A — the heavy hinge day
  ('pull_a',1,'hinge_rdl','hinge_rdl',3,6,10,180,true),
  ('pull_a',2,'weighted_pullup','weighted_pullup',3,5,8,150,true),
  ('pull_a',3,'cable_row','kb_row',3,8,12,120,true),
  ('pull_a',4,'leg_curl','good_morning',3,8,12,120,true),
  ('pull_a',5,'face_pull','rear_delt_fly',3,15,20,75,false),
  ('pull_a',6,'biceps_curl','biceps_curl',3,8,15,75,false);
