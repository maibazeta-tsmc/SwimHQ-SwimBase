# SwimHQ SwimBase

A swim team app for clubs. Swimmers, parents and coaches each have their own
login. Coaches organise swimmers into training groups and move them up or down.
Many clubs can use the same app, and each club's data is kept private.

This is the **foundation**: the database with all its privacy rules, plus a
first version of the app that can sign people in, register a club and join a
club with an invite code. The real screens (attendance, events, personal bests,
dashboards) come in later phases.

The app is built first as a **website**. The same code becomes the Android and
iPhone apps later.

---

## What's in this folder

| Folder or file | What it is |
| --- | --- |
| `lib/` | The app itself (written in Flutter). `lib/screens/` has one file per screen. |
| `web/`, `android/`, `ios/` | Files Flutter needs for the website, Android and iPhone versions. You rarely touch these. |
| `supabase/migrations/` | The database, in three files. You copy these into Supabase once (step 1). |
| `supabase/tests/` | Automatic checks that prove the privacy rules work. |
| `.github/workflows/` | Instructions for GitHub to check the code and publish the website for you. |
| `env.example.json` | A template for your Supabase settings, used only if you run the app on your own computer. |

---

## Step 1: Set up the database in Supabase (about 10 minutes)

You only do this once.

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) and sign in.
2. Click **New project**.
   - **Name:** `swimbase`
   - **Database password:** click **Generate a password**, then save it in a
     password manager. You will not need it day to day.
   - **Region:** pick **Southeast Asia (Singapore)**, closest to the Philippines.
   - Click **Create new project** and wait a minute or two.
3. In the left menu, click **SQL Editor**, then **New query**.
4. On GitHub, open `supabase/migrations/20261125000001_core_tables.sql`, click
   the **Copy raw file** button (two overlapping squares), paste it into the
   Supabase SQL editor, and click **Run**. You should see "Success. No rows
   returned".
5. Click **New query** again and do the same with
   `20261125000002_privacy_rules.sql`.
6. Then once more with `20261125000003_club_actions.sql`.

Run the three files **in that order**, each **only once**. If one shows an
error, stop and send the error text in the project chat.

Supabase may show a warning about `family_group_history` being a "security
definer view". That is expected: it is how swimmers and parents see their
group history with the coach's private notes hidden.

## Step 2: Tell Supabase where the website lives

1. In Supabase, click **Authentication** in the left menu, then
   **URL Configuration**.
2. Set **Site URL** to
   `https://maibazeta-tsmc.github.io/SwimHQ-SwimBase/`
3. Under **Redirect URLs**, click **Add URL** and add the same address, then
   also add `http://localhost:*` (for testing on your own computer). Save.

This makes the "confirm your email" link take people back to the app.

## Step 3: Put the website online with GitHub Pages (free)

1. On GitHub, open this repository and click **Settings** (top right of the
   repository, not your account settings).
2. In the left menu, click **Pages**. Under **Build and deployment**, set
   **Source** to **GitHub Actions**.
3. Still in Settings, click **Secrets and variables**, then **Actions**.
4. Click **New repository secret** and add these two. You find both values in
   Supabase under **Project Settings** (gear icon), then **API Keys** and
   **Data API**:

   | Name | Value |
   | --- | --- |
   | `SUPABASE_URL` | The **Project URL**, like `https://abcd1234.supabase.co` |
   | `SUPABASE_PUBLISHABLE_KEY` | The **Publishable key** (starts with `sb_publishable_`). Older projects call it the **anon public** key. |

5. Once this pull request is merged into `main`, GitHub builds and publishes
   the site automatically (watch it under the **Actions** tab, it takes about
   3 to 5 minutes). Your app will be at:

   **https://maibazeta-tsmc.github.io/SwimHQ-SwimBase/**

   If you added the secrets after the first build, open **Actions**, click
   **Publish web app**, then **Run workflow** to rebuild.

### Keeping keys safe

- The **publishable key** is designed to be inside the app, where anyone could
  find it. That is fine: the privacy rules in the database decide what each
  person can see, not the key.
- The **secret key** (or **service_role** key) skips all privacy rules.
  Never put it in the app, in GitHub, or in a chat message.

## Step 4: Make yourself the superadmin

1. Open the website, click **New here? Create an account**, and sign up with
   your own email. Confirm it from the email Supabase sends.
2. In Supabase, open **SQL Editor**, **New query**, paste this with your email,
   and click **Run**:

   ```sql
   insert into public.superadmins (user_id)
   select id from auth.users where email = 'your-email@example.com';
   ```

You can now see every club (read only), approve new clubs, and reassign a
club's head coach.

## Step 5: Try it out

1. Sign in and tap **Register a club**. The club shows "Waiting for approval".
2. Until a superadmin approves it, the club can set up groups and invite
   coaches, but cannot invite swimmers or parents.
3. The approval screen comes in a later phase. For now, approve a club in the
   Supabase SQL Editor:

   ```sql
   update public.clubs set status = 'approved', approved_at = now()
   where name = 'Your Club Name';
   ```

Supabase's free plan only sends a few sign-up emails per hour. If a
confirmation email doesn't arrive, wait a while, or in Supabase go to
**Authentication**, **Users**, and confirm the user by hand.

---

## How the privacy rules work (in plain words)

The database itself checks every read and write, so even a tampered copy of
the app cannot see another club's data.

| Who | Can see | Can change |
| --- | --- | --- |
| **Superadmin** (you) | Every club, read only | Approve or suspend clubs; reassign a head coach |
| **Head coach** (one per club) | Everything in their club | Everything in their club; hands out the two assistant switches |
| **Assistant coach** | Everything in their club | Add and edit swimmers, make invite codes for swimmers and parents. Creating groups and moving swimmers need a switch from the head coach. |
| **Swimmer** | Their club's groups and teammates | Their own name and phone |
| **Parent** | Only their own linked children | Their own name and phone; can remove their own link |
| **Another club** | Nothing from your club | Nothing in your club |

Other rules built in:

- Every club starts as **pending** and on the **free** plan. The plan field is
  there so paid plans can be switched on later.
- A swimmer is in exactly **one group** at a time. Every move is kept in a
  permanent history, can be scheduled for a future date, and two coaches
  moving the same swimmer at once can't overwrite each other.
- A coach's reason for a move is hidden from the family unless the coach ticks
  "share reason".
- Groups are never deleted, only archived once they are empty.
- Swimmers who leave are marked "left", so their history and times are kept.
- Invite codes look like `KX7P-29QD`, work once, and expire after 7 days.

The checks in `supabase/tests/privacy_rules_test.sql` test each of these rules
automatically on every pull request (look for the green tick on GitHub).

---

## Optional: run the app on your own computer

You don't need this to use the website, but it's handy for faster testing.

1. Install Flutter by following
   [docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install)
   (choose your computer type, then **Web** as the target). Also install
   Google Chrome.
2. Download this repository (green **Code** button, **Download ZIP**, or use
   GitHub Desktop).
3. In the folder, copy `env.example.json` to a new file named `env.json` and
   fill in your Project URL and Publishable key. `env.json` is ignored by Git,
   so it never gets uploaded.
4. Open a terminal in the folder and run:

   ```
   flutter pub get
   flutter run -d chrome --dart-define-from-file=env.json
   ```

Android phones can install a test version later without a Google Play account.

## What's next

Later phases add: the coach screens for groups and moves, the superadmin
approval screen, swimmer and parent dashboards, training sessions and
attendance, events, personal bests from Hy-Tek PDFs, team records, and push
notifications (with Firebase).
