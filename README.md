# Self Project

A self-hosted strength training tracker. One HTML file, no build step, no framework,
no app store. Runs as a web app on your phone and stores everything in your own
Supabase project.

Built for lifting logs specifically: it knows what session you're doing today, pre-fills
last week's numbers, times your rest, and tells you when you've hit a personal best —
because the thing that determines results is how many sessions you actually complete, not
how good the analytics are.

---

## What it does

**Guided sessions.** Your program lives in the database as routines. Open the app and it
tells you which session is next in the rotation, lays out the exercises in order with
target sets and rep ranges, and fills in what you lifted last time. Logging a set is a tap.
Finish an exercise and the next one opens itself. Pick "Home" instead of the gym and every
exercise swaps to its home-equipment variant automatically.

**Rest timer.** Starts on its own when you log a set, sized per exercise — long after
squats, short after lateral raises. Buzzes when it's up. `+30s` and `Skip`.

**Personal bests, detected live.** Beat your best estimated 1RM on a lift and you get a
distinct haptic pattern and a banner mid-set.

**Volume by muscle group, counted properly.** Weekly fractional sets per muscle: a direct
set counts 1.0, a meaningful secondary counts 0.5. A weighted dip gives chest 1.0, triceps
1.0, front delts 0.5; a bench press gives chest 1.0 but triceps only 0.5.

**Progressive overload.** Estimated 1RM per exercise, so different rep ranges are
comparable — 225×8 and 250×5 become the same currency. Bodyweight movements add your
current bodyweight so a +45 lb dip sits on the same scale as a barbell lift. Best of the
last four weeks against the four before it.

**Bodyweight and waist**, shown as a 7-day rolling average with a verdict on whether to
adjust calories, because the daily number is noise.

**Calendar and charts.** Month-by-month calendar coloured by sessions per day with a marker
for cardio days, plus charts for weight trend, sessions per week against target, estimated
1RM per exercise, and weekly volume.

**Goals** for a lift target, a bodyweight target, or sessions per week. They check
themselves against your logged data and stamp the date they're met.

**Cardio and everything else** — swimming, cycling, walks, sprints, hikes.

---

## How it's built

- `index.html` — the entire app. Vanilla JavaScript, no framework, no bundler, no npm.
  Charts are hand-written inline SVG. About 60 KB.
- `schema.sql` — every table, view, index and security policy, plus the seeded exercise
  catalog and routines.
- Supabase provides Postgres and auth. The only runtime dependency is `supabase-js`, loaded
  from a CDN.
- Hosting is any static host. GitHub Pages works and is free.

---

## Run your own copy

**1. Fork this repository.**

**2. Create a free Supabase project** at [supabase.com](https://supabase.com). Any region;
pick the one nearest you.

**3. Run the schema.** Open the SQL Editor in your new project, paste the entire contents
of `schema.sql`, and run it. It creates 9 tables, 10 views, row-level security on
everything, and seeds 38 exercises with their muscle mappings plus four routines.

**4. Turn off email confirmation.** Authentication → Sign In / Providers → Email → switch
**Confirm email** off. Without this, your first sign-up waits on a confirmation email that
isn't configured. While you're there, switch **leaked password protection** on.

**5. Point the app at your project.** In `index.html`, near the top of the `<script>` block,
there's a config section:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_KEY = 'sb_publishable_...';
const WEEK_TARGET  = 4;
```

Both values are in Supabase under Project Settings → API. Use the **publishable** key, not
the secret one. It's safe in public source — row-level security is what protects the data,
and every table has it on.

**6. Turn on GitHub Pages.** Settings → Pages → Deploy from a branch → `main` → `/ (root)`.
Your app appears at `https://YOURNAME.github.io/YOURREPO/` within a minute or two.

**7. Open it on your phone** and use Share → Add to Home Screen. It runs full-screen with
no browser chrome.

---

## Making it yours

Almost everything opinionated lives in data, not code.

### Your own program

Edit the `routine` and `routine_item` rows at the bottom of `schema.sql`, or change them
later in the Supabase table editor. A routine is a session; a routine item is one exercise
slot in it.

```sql
insert into public.routine (id, name, position) values
  ('upper_a','Upper A',1), ('lower_a','Lower A',2);

insert into public.routine_item
  (routine_id, position, exercise_id, home_exercise_id,
   target_sets, rep_low, rep_high, rest_seconds, is_core) values
  ('upper_a', 1, 'bench_press', 'pushup', 3, 6, 10, 150, true);
```

- `routine.position` sets the rotation order the app cycles through.
- `home_exercise_id` is substituted when you pick "Home" — leave it the same as
  `exercise_id` if there's no variant.
- `is_core = false` marks an exercise as optional; it shows as a tail item you can skip on
  a short day.
- `rest_seconds` drives the rest timer for that slot.

### New exercises

```sql
insert into public.exercise (id, name, pattern, side, is_anchor, counts_bodyweight, sort_order)
values ('pendlay_row','Pendlay row','h_pull','pull',false,false,53);

insert into public.exercise_muscle (exercise_id, muscle, fraction) values
  ('pendlay_row','Back',1.0), ('pendlay_row','Biceps',0.5), ('pendlay_row','Rear delts',0.5);
```

- `side` groups it in the picker: `push`, `pull` or `legs`.
- `is_anchor = true` gives it a one-tap chip and bolds it in the overload list. Keep this to
  a handful of lifts — the point is a small set of movements you actually progress.
- `counts_bodyweight = true` adds your bodyweight when estimating 1RM. Use it for pull-ups,
  dips, push-ups, Nordics.
- `fraction` is 1.0 for a primary mover, 0.5 for a meaningful secondary. Don't inflate it;
  the volume numbers are only useful if the attribution is honest.

### Other knobs

- `WEEK_TARGET` in `index.html` — sessions per week the progress ring counts toward.
- `PLATES` and `BARBELL` in `index.html` — plate denominations and which exercises get the
  plate calculator. Change `PLATES` to `[25,20,15,10,5,2.5,1.25]` and the bar weight in
  `showPlates()` from 45 to 20 for kilos.
- Volume bands (low / maintaining / productive / high) are in `loadStats()`.
- Colours are CSS custom properties at the top of the `<style>` block.

---

## The opinionated parts, and why

This isn't a neutral tool — a few decisions are baked in. They're defensible, but you
should know what they are so you can change them.

**Fractional set counting** rather than counting every set as 1 for every muscle involved.
This is the quantification method that best predicted hypertrophy in
[Pelland et al. 2025](https://link.springer.com/article/10.1007/s40279-025-02344-w), a
meta-regression across 67 studies and 2,058 participants.

**10–20 sets per muscle per week** is flagged as the productive band. The same analysis
found gains continue to rise with volume with diminishing but not disappearing returns, so
there's no hard plateau — the upper bound here is a practical recovery ceiling, not a
finding.

**Estimated 1RM via Epley** (`load × (1 + reps/30)`) as the overload metric. It makes rep
ranges comparable. It's an estimate and gets less accurate above about 12 reps.

**7-day rolling average for bodyweight**, never the daily number, with a calorie verdict at
+0.15 to +0.6 lb/week. Those thresholds assume a slow lean bulk; invert them for a cut.

**Rotation order spaces spinal loading.** The seeded routines put the two heavily
axially-loaded sessions at opposite ends of the cycle, so two consecutive training days
never stack a heavy squat on a heavy deadlift.
[Belcher et al. 2019](https://csep.ca/2019/06/19/time-course-of-recovery-is-similar-for-the-back-squat-bench-press-and-deadlift-in-well-trained-males-2/)
found soreness takes 48–72 hours to return to baseline after hard sets of these lifts —
and, contrary to folklore, that squats took *longer* to recover from than deadlifts.

---

## Privacy and security

Row-level security is enabled on all nine tables with policies scoped to `auth.uid()`, and
all ten views are `security_invoker` so they inherit the caller's permissions rather than
the owner's. Two people using the same instance cannot see each other's data.

The publishable key in `index.html` is designed to be public. It grants no access on its
own — every query is still filtered by the policies above.

---

## Known limitations

- **No password reset.** There's no self-serve recovery, so a forgotten password needs a
  manual reset from the Supabase dashboard. Worth adding before sharing an instance widely.
- **Anyone with the URL can create an account.** There's no invite gate.
- **Routines are per-instance, not per-user.** Everyone signing in to the same deployment
  follows the same program, though anyone can log any exercise outside it. Making routines
  user-scoped means adding a `user_id` to `routine` and a matching policy.
- **Free Supabase projects pause** after about a week with no activity. Regular use avoids
  this; if it does pause, un-pause it from the dashboard.
- **Estimated 1RM is an estimate.** Treat the trend as the signal, not the absolute value.

---

## License

MIT. Do whatever you like with it.
