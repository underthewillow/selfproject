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


-- =============================================================================
-- NUTRITION MODULE
--
-- Adds the food catalog, the daily food log, and the roll-up views that drive
-- the Food tab. Additive only: nothing here touches the training tables.
-- =============================================================================


-- =============================================================================
-- 9. REFERENCE DATA — the food catalog
--
-- Priced per the unit you actually use, not per 100 g. "1 can", "1 medium",
-- "0.5 lb raw" — the way you'd say it out loud. Saturated fat and fibre are
-- first-class columns because those are the two numbers LDL responds to.
-- =============================================================================

create table public.food (
  id              text primary key,
  name            text not null,
  category        text not null,   -- Protein | Fats | Fruit & veg | Carbs | Supplements
  unit            text not null,   -- the serving this row is priced for
  kcal            numeric(7,1) not null default 0,
  protein_g       numeric(6,1) not null default 0,
  carbs_g         numeric(6,1) not null default 0,
  fat_g           numeric(6,1) not null default 0,
  sat_fat_g       numeric(6,1) not null default 0,
  fibre_g         numeric(6,1) not null default 0,
  -- Collagen is the reason this column exists. Incomplete protein: leucine
  -- ~2.5% vs ~10.5% in whey, zero tryptophan, DIAAS near zero. The calories
  -- are real, the grams are not. Set false and it stays out of usable protein.
  counts_protein  boolean not null default true,
  -- Cheap calories that don't move saturated fat. Surfaced when a day runs short.
  is_lever        boolean not null default false,
  -- Shown in the picker. Use it for the caveats worth seeing at log time.
  note            text,
  sort_order      integer not null default 100
);


-- =============================================================================
-- 10. LOGGING TABLE
--
-- food_id points at the catalog for known items. For anything not in the
-- catalog, leave food_id null and fill name/unit and the macro columns — the
-- resolver below falls back to them. Either way, servings scales it.
-- =============================================================================

create table public.food_log (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  logged_on      date not null,
  meal           text not null default 'Breakfast',
  food_id        text references public.food(id) on delete set null,
  servings       numeric(6,2) not null default 1,
  -- Only used when food_id is null (a one-off item typed in by hand).
  name           text,
  unit           text,
  kcal           numeric(7,1),
  protein_g      numeric(6,1),
  carbs_g        numeric(6,1),
  fat_g          numeric(6,1),
  sat_fat_g      numeric(6,1),
  fibre_g        numeric(6,1),
  counts_protein boolean not null default true,
  created_at     timestamptz not null default now(),
  constraint food_log_has_an_item check (food_id is not null or name is not null)
);


-- =============================================================================
-- 11. INDEXES
-- =============================================================================

create index on public.food_log (user_id, logged_on desc);
create index on public.food_log (user_id, food_id);


-- =============================================================================
-- 12. ROW LEVEL SECURITY
-- =============================================================================

alter table public.food     enable row level security;
alter table public.food_log enable row level security;

create policy "read catalog" on public.food
  for select to authenticated using (true);
create policy "own rows" on public.food_log
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- =============================================================================
-- 13. VIEWS
--
-- All security_invoker, so they inherit the caller's row level security.
-- =============================================================================

-- One row per logged item with the catalog joined in and servings applied.
-- Everything downstream reads this, so the food_id / hand-typed distinction
-- disappears at this line and never has to be handled again.
create view public.food_log_item
with (security_invoker = true) as
select
  l.id,
  l.user_id,
  l.logged_on,
  l.meal,
  l.food_id,
  l.servings,
  coalesce(f.name,     l.name)          as name,
  coalesce(f.unit,     l.unit, '')      as unit,
  coalesce(f.category, 'Other')         as category,
  round(l.servings * coalesce(f.kcal,      l.kcal,      0), 1) as kcal,
  round(l.servings * coalesce(f.protein_g, l.protein_g, 0), 1) as protein_g,
  round(l.servings * coalesce(f.carbs_g,   l.carbs_g,   0), 1) as carbs_g,
  round(l.servings * coalesce(f.fat_g,     l.fat_g,     0), 1) as fat_g,
  round(l.servings * coalesce(f.sat_fat_g, l.sat_fat_g, 0), 1) as sat_fat_g,
  round(l.servings * coalesce(f.fibre_g,   l.fibre_g,   0), 1) as fibre_g,
  coalesce(f.counts_protein, l.counts_protein) as counts_protein,
  l.created_at
from public.food_log l
left join public.food f on f.id = l.food_id;

-- The day, totalled. usable_protein_g is the number that matters: label protein
-- minus anything flagged counts_protein = false.
create view public.daily_nutrition
with (security_invoker = true) as
select
  user_id,
  logged_on,
  round(sum(kcal))                                              as kcal,
  round(sum(protein_g), 1)                                      as protein_g,
  round(sum(protein_g) filter (where counts_protein), 1)        as usable_protein_g,
  round(sum(protein_g) filter (where not counts_protein), 1)    as uncounted_protein_g,
  round(sum(carbs_g), 1)                                        as carbs_g,
  round(sum(fat_g), 1)                                          as fat_g,
  round(sum(sat_fat_g), 1)                                      as sat_fat_g,
  round(sum(fibre_g), 1)                                        as fibre_g,
  count(*)                                                      as items
from public.food_log_item
group by user_id, logged_on;

-- The same totals split by meal, for the per-meal tables on the Food tab.
create view public.meal_nutrition
with (security_invoker = true) as
select
  user_id,
  logged_on,
  meal,
  round(sum(kcal))                                       as kcal,
  round(sum(protein_g), 1)                               as protein_g,
  round(sum(protein_g) filter (where counts_protein), 1) as usable_protein_g,
  round(sum(carbs_g), 1)                                 as carbs_g,
  round(sum(fat_g), 1)                                   as fat_g,
  round(sum(sat_fat_g), 1)                               as sat_fat_g,
  round(sum(fibre_g), 1)                                 as fibre_g,
  min(created_at)                                        as first_at
from public.food_log_item
group by user_id, logged_on, meal;

-- What you actually eat, ranked. Drives the one-tap row at the top of the
-- picker so the common case is never more than a tap away.
create view public.food_favorite
with (security_invoker = true) as
select
  user_id,
  food_id,
  count(*)                                       as uses,
  max(logged_on)                                 as last_on,
  round(avg(servings), 2)                        as usual_servings
from public.food_log
where food_id is not null
group by user_id, food_id;

-- 14-day nutrition trend, for the chart and for the Sunday check-in.
create view public.nutrition_trend
with (security_invoker = true) as
select
  user_id,
  logged_on,
  kcal,
  usable_protein_g,
  carbs_g,
  fat_g,
  sat_fat_g,
  fibre_g,
  round(avg(kcal) over w)                as kcal_avg7,
  round(avg(usable_protein_g) over w, 1) as protein_avg7,
  round(avg(sat_fat_g) over w, 1)        as sat_fat_avg7,
  round(avg(fibre_g) over w, 1)          as fibre_avg7
from public.daily_nutrition
window w as (partition by user_id order by logged_on rows between 6 preceding and current row);


-- =============================================================================
-- 14. SEED — the catalog
--
-- Every item priced per the unit in the `unit` column. Sources are the branded
-- nutrition panels where a brand is named, USDA FoodData Central otherwise.
-- Add your own rows with the same shape; nothing in the app is hardcoded to
-- these ids.
-- =============================================================================

insert into public.food
  (id, name, category, unit, kcal, protein_g, carbs_g, fat_g, sat_fat_g, fibre_g,
   counts_protein, is_lever, note, sort_order) values

-- ---- Protein ----------------------------------------------------------------
('tuna_safecatch',   'Safe Catch wild albacore', 'Protein', '1 can (5 oz)',
   175, 35.0,  0,   5.0,  2.5, 0,   true,  false,
   'Low-mercury tested. Two cans a day is fine at your size.', 10),
('beef_8515',        'Ground beef 85/15',        'Protein', '0.5 lb raw',
   488, 42.2,  0,  34.0, 12.9, 0,   true,  false,
   'Two-thirds of a day''s saturated fat in one serving.', 11),
('beef_937',         'Ground beef 93/7',         'Protein', '0.5 lb raw',
   345, 48.0,  0,  16.0,  7.3, 0,   true,  false,
   'The swap: more protein, 5.6 g less saturated fat, same micronutrients.', 12),
('whey_levels',      'Levels vanilla whey',      'Protein', '1 scoop (32 g)',
   130, 24.0,  3.0, 2.5,  1.0, 0,   true,  false, null, 13),
('skyr_nonfat',      'Skyr, nonfat',             'Protein', '1 serving (150 g)',
   105, 18.0,  6.0, 0.3,  0,   0,   true,  false, null, 14),
('milk_1',           '1% milk',                  'Protein', '1 cup',
   102,  8.2, 12.2, 2.4,  1.5, 0,   true,  false, null, 15),
('egg_hardboiled',   'Hardboiled egg',           'Protein', '1 large',
    78,  6.3,  0.6, 5.3,  1.6, 0,   true,  false,
   'The yolk is the nutrition — choline, lutein, B12, D.', 16),
('salmon',           'Salmon, cooked',           'Protein', '6 oz',
   350, 38.0,  0,  20.0,  3.0, 0,   true,  true,
   'Best protein-per-gram-of-saturated-fat on the list.', 17),
('collagen_vital',   'Vital Proteins collagen',  'Protein', '1 tbsp (~7.4 g)',
    26,  6.7,  0,   0,    0,   0,   false, false,
   'Calories count, grams do not. Never counts toward the protein target.', 18),
('milk_2',           '2% milk',                  'Protein', '1 cup',
   122,  8.1, 12.0, 4.8,  3.1, 0,   true,  false,
   'Reference only — the extra calories arrive as saturated fat. 1% stays.', 19),
('milk_whole',       'Whole milk',               'Protein', '1 cup',
   149,  7.7, 11.7, 8.0,  4.6, 0,   true,  false,
   'Reference only — wrong lever for a high-LDL constraint.', 20),

-- ---- Fats -------------------------------------------------------------------
('mayo_chosen',      'Chosen Foods avocado-oil mayo', 'Fats', '1 tbsp',
   100,  0,    0,  11.0,  1.5, 0,   true,  true,  null, 30),
('olive_oil',        'Olive oil',                'Fats', '1 tbsp',
   119,  0,    0,  13.5,  1.9, 0,   true,  true,
   'The cheapest 120 calories you can add without touching LDL.', 31),
('walnuts',          'Walnuts',                  'Fats', '1 oz',
   185,  4.3,  3.9, 18.5, 1.7, 1.9, true,  true,  null, 32),
('almonds',          'Almonds',                  'Fats', '1 oz',
   164,  6.0,  6.1, 14.2, 1.1, 3.5, true,  true,  null, 33),
('almond_butter',    'Almond butter',            'Fats', '2 tbsp',
   190,  6.7,  6.0, 17.8, 1.5, 3.3, true,  true,  null, 34),
('avocado',          'Avocado',                  'Fats', '1 medium',
   240,  3.0, 12.8, 22.0, 3.2,10.0, true,  true,
   'Also 10 g of fibre — two levers at once.', 35),

-- ---- Fruit & veg ------------------------------------------------------------
('banana',           'Banana',                   'Fruit & veg', '1 medium',
   105,  1.3, 27.0,  0.4, 0.1, 3.1, true,  false, null, 50),
('apple',            'Apple',                    'Fruit & veg', '1 medium',
    95,  0.5, 25.1,  0.3, 0.1, 4.4, true,  false, null, 51),
('orange',           'Orange',                   'Fruit & veg', '1 medium',
    62,  1.2, 15.4,  0.2, 0,   3.1, true,  false, null, 52),
('kiwi',             'Kiwi',                     'Fruit & veg', '1 medium',
    42,  0.8, 10.1,  0.4, 0,   2.1, true,  false, null, 53),
('carrot_raw',       'Raw carrot',               'Fruit & veg', '1 medium',
    25,  0.6,  5.8,  0.2, 0,   1.7, true,  false, null, 54),
('mango_solely',     'Solely mango fruit jerky', 'Fruit & veg', '1 strip',
    70,  0.5, 17.0,  0,   0,   1.0, true,  false, null, 55),

-- ---- Carbs ------------------------------------------------------------------
('honey',            'Honey',                    'Carbs', '1 tbsp',
    64,  0.1, 17.3,  0,   0,   0,   true,  false, null, 60),
('oats',             'Oats, cooked',             'Carbs', '1 cup',
   150,  5.9, 27.4,  2.5, 0.5, 4.0, true,  true,
   'Beta-glucan — one of the few foods with a real LDL effect.', 61),
('rice_white',       'White rice, cooked',       'Carbs', '1 cup',
   205,  4.3, 44.5,  0.4, 0.1, 0.6, true,  true,  null, 62),
('potato',           'Potato, baked with skin',  'Carbs', '1 large',
   280,  7.5, 63.2,  0.4, 0.1, 6.6, true,  true,
   '280 calories and 6.6 g fibre for a tenth of a gram of saturated fat.', 63),

-- ---- Supplements ------------------------------------------------------------
('coffee_bp',        'Bulletproof coffee + creatine', 'Supplements', '1 scoop',
     5,  0,    0,    0,   0,   0,   true,  false,
   '5 g creatine, 250 mg electrolytes.', 80),
('psyllium_cap',     'Psyllium husk',            'Supplements', '1 capsule',
     2,  0,    0.5,  0,   0,   0.5, true,  false,
   '0.5 g soluble fibre. The LDL dose is 10–12 g/day — that is 20+ capsules, so move to powder.', 81),
('fish_oil',         'Fish oil',                 'Supplements', '1 soft gel',
     9,  0,    0,    1.0, 0.2, 0,   true,  false,
   '~300 mg EPA+DHA. Triglycerides, not LDL.', 82),
('vitamin_d',        'Vitamin D 10,000 IU',      'Supplements', '1 dose',
     0,  0,    0,    0,   0,   0,   true,  false,
   'Above the 4,000 IU upper limit — get 25(OH)D tested.', 83),
('heart_soil',       'Heart & Soil Whole Package','Supplements', '6 caps',
     5,  0,    0,    0,   0,   0,   true,  false,
   '3 g desiccated organ — about a ninth of an ounce of liver.', 84),
('tongkat',          'Nutricost tongkat ali',    'Supplements', 'per label',
     0,  0,    0,    0,   0,   0,   true,  false, null, 85),
('thorne_test',      'Thorne Adv. Testosterone Support', 'Supplements', '2 caps',
     0,  0,    0,    0,   0,   0,   true,  false,
   'Shilajit, luteolin, ashwagandha, L-leucine, zinc. No overlap with tongkat.', 86);
