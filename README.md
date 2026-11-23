# INDETAIL

INDETAIL is a Flutter office workspace for Android and browser use, covering project delivery, team assignments, reporting, project photos, and verified attendance. The interface uses the Ivory Coast and professional blue palette, with animated transitions and INDETAIL branding.

## Website and shared data

The same Flutter app builds as a responsive website for desktop and iPhone Safari. The website and Android app use the same Supabase Auth project, PostgreSQL tables, RLS policies, Storage bucket, and Edge Function, so they read and write the same live workspace data. No second database or web-only user directory is created.

Build the live browser version with [`build-live-web.ps1`](build-live-web.ps1). It writes the website to `build/web` with the root base path and the Supabase URL and publishable key included. Host that folder over HTTPS, then use its URL in Safari on iPhone or another modern browser. This is a regular browser website and does not require an iOS installation. Browser sign-in is kept in tab-scoped `sessionStorage`; closing the tab ends that browser session. The web app uses the same role and database policies as the APK.

Attendance requests a one-time browser GPS position after the user presses a punch button. The browser must grant location access and the site must be served over HTTPS. Browsers do not provide Android's mock-location signal, so the database still checks site membership, distance, reported GPS accuracy, and open-shift state. Device-reported coordinates remain subject to the existing client-location trust limitation.

## Preview and live modes

- With no build-time Supabase values, the app opens in **Preview mode**. It shows clearly labeled illustrative project/task content, stores edits only in the running app session, and never requests location or records attendance. Preview roles let you inspect Admin, Team Leader, and Employee navigation.
- With both `SUPABASE_URL` and `SUPABASE_ANON_KEY` supplied at build time, the welcome screen identifies the live configuration and sign-in uses Supabase Auth. Live data is protected by PostgreSQL row-level security. The app does not contain a service-role key or any real company, employee, or site data.

## Supabase setup

The connected Supabase project is [INDETAIL's project](https://supabase.com/dashboard/project/hulfgxqbdliaxulqjunj), reference `hulfgxqbdliaxulqjunj`, in the Seoul region. Migrations 001–003 create the app schema, Auth profile trigger, RLS policies, validated attendance RPC, audit log, private `project-media` bucket, and API privilege hardening. Migration 004 adds generated Employee IDs, manager-scoped team workflows, and login rate limits. Migration 005 puts privileged implementation routines in the unexposed `private` schema and exposes invoker-secured wrappers. Migration 006 adds Sunday weekly-off enforcement, punch correction review, leave requests, and monthly attendance totals. Migration 007 tightens request review privileges and keeps the attendance summary implementation private. Migration 008 repairs open punch-out handling and keeps geofence validation anchored to the original shift site. Migration 009 exposes the caller's open site through an invoker-secured RPC backed by a narrowly scoped private helper. Migration 010 adds paid holidays, holiday import, Saturday full-day credit, Admin attendance reports, and private leave and missed-punch reasons. Migration 011 sets paid leave accrual to two days per month from November 2026, lets employees choose paid or unpaid leave, and records Admin balance adjustments in a private audit log. Migration 012 explicitly denies direct access to that adjustment log.

For a fresh Supabase project, run these migrations in order as the project owner:

1. [`supabase/migrations/001_indetail.sql`](supabase/migrations/001_indetail.sql)
2. [`supabase/migrations/002_private_helpers_and_rls_tuning.sql`](supabase/migrations/002_private_helpers_and_rls_tuning.sql)
3. [`supabase/migrations/003_api_grants_hardening.sql`](supabase/migrations/003_api_grants_hardening.sql)
4. [`supabase/migrations/004_signup_employee_ids_management.sql`](supabase/migrations/004_signup_employee_ids_management.sql)
5. [`supabase/migrations/005_public_invoker_management_rpc.sql`](supabase/migrations/005_public_invoker_management_rpc.sql)
6. [`supabase/migrations/006_weekly_off_leave_and_attendance_summary.sql`](supabase/migrations/006_weekly_off_leave_and_attendance_summary.sql)
7. [`supabase/migrations/007_attendance_leave_review_security.sql`](supabase/migrations/007_attendance_leave_review_security.sql)
8. [`supabase/migrations/008_punch_out_reliability.sql`](supabase/migrations/008_punch_out_reliability.sql)
9. [`supabase/migrations/009_open_attendance_rpc_private_helper.sql`](supabase/migrations/009_open_attendance_rpc_private_helper.sql)
10. [`supabase/migrations/010_attendance_leave_holidays_admin.sql`](supabase/migrations/010_attendance_leave_holidays_admin.sql)
11. [`supabase/migrations/011_paid_leave_choice_balance_and_attendance.sql`](supabase/migrations/011_paid_leave_choice_balance_and_attendance.sql)
12. [`supabase/migrations/012_paid_leave_adjustment_access_hardening.sql`](supabase/migrations/012_paid_leave_adjustment_access_hardening.sql)

The connected project already has migrations 001–012 applied. Do not reapply them there. For a different Supabase project, run all twelve migrations in order. Paid leave is deducted only for approved paid-leave days the employee is actually absent; those days count as present. Approved unpaid-leave days count as absent. Employees can see paid holidays, and Admins can adjust current employee balances.

For a fresh project, deploy the public credential-handling function after applying all migrations:

   ```powershell
   supabase functions deploy employee-auth --project-ref hulfgxqbdliaxulqjunj
   ```

The connected project already has its Admin account. Public email signup always creates an Employee profile; the database allocates an immutable ID in the `ids` plus four-digit format. After confirming their email when requested, employees can sign in with that ID and their password. The function uses Supabase's server-side secrets and rate limits signup and Employee ID login; no service-role key is included in the APK. Admins and Team Leaders can create teams, add employees, assign team leaders, create team-scoped projects and tasks, and configure attendance locations. All new accounts start with the Employee role; only Admins can change roles. Real site coordinates still need to be entered by a workspace manager; none are seeded. The mobile app uses the project's HTTPS URL and **publishable** key.

The publishable key is sent in the `apikey` header. The `Authorization` header is only sent when a signed-in user's access token is available.

On a fresh checkout, run `flutter pub get` first. To build the live-configured, debug-signed APK for sideloading, run [`build-live-apk.ps1`](build-live-apk.ps1). It prompts for the project's publishable key (or reads `INDETAIL_SUPABASE_PUBLISHABLE_KEY`), takes the app version from `pubspec.yaml`, and writes versioned and direct APK files beside this project folder. A publishable key is intended for mobile clients; never use a service-role or secret key.

You can also build manually with the project's HTTPS URL and publishable key:

   ```powershell
    flutter build apk --debug --build-name 1.0.9 --build-number 12 `
     --dart-define="SUPABASE_URL=https://hulfgxqbdliaxulqjunj.supabase.co" `
     --dart-define="SUPABASE_ANON_KEY=your-publishable-key"
   ```

After setup, sign in as Admin or Team Leader, create teams, add employees by Employee ID, and then create projects, tasks, and deadlines for those teams. Either manager can configure attendance locations. Employees can update their own task progress and submit reports.

In Attendance, an Admin or Team Leader can add the real office coordinates and project sites. Team Leaders can manage teams and project sites in their team scope. Project geofences are available to project assignees and members of the project team. The site radius is configurable from 50 to 500 metres; the device and server require a GPS accuracy of 35 metres or better.

## App behavior

- Admin, Team Leader, and Employee roles control assignment, team visibility, and report/correction review. Daily reports and weekly summaries include review comments and approval/revision status.
- PIN unlock uses a six-digit, salted PBKDF2-HMAC-SHA256 hash. Android Keystore-backed AES-GCM protects local session/PIN records. Fingerprint unlock is offered on supported devices after the user enables it; PIN remains the fallback. Five incorrect PIN attempts trigger a short lockout.
- Email signup creates Employee accounts only and returns an immutable `ids####` identifier. A server-side Edge Function maps that ID to Auth without returning the email, verifies the password through Supabase Auth, and rate-limits attempts using hashed bucket keys.
- Sundays are weekly off days; the live UI and attendance RPC both block punches. Sundays count as paid present days. Saturdays count as half days unless Admin enables full-day credit for a selected employee; attendance, absence and paid-leave totals follow that setting. Paid leave accrues at two days per month from November 2026, carries forward without a cap, and is checked before approval. Employees choose paid or unpaid leave when applying: approved paid leave is deducted for actual absent workdays and counts as present; approved unpaid leave counts as absent. Admins can change each employee's current balance, with adjustments privately audited. Admins can add or import paid holidays from Excel; all members can view the holiday list. Members see their attendance and leave totals; only Admins can read leave or missed-punch reason text.
- Admin attendance includes employee present, leave and absent days, punch-in/out times, work hours and leave balance. Admins can export monthly summary and daily detail sheets to Excel. Browser and Android builds share these same database rules and stored records.
- Attendance reads a one-shot precise location only when the user initiates a punch or a manager chooses “Use my current GPS position” while setting up a site. There is no background or continuous location tracking. The RPC checks the account, assigned site or project-team membership, radius, accuracy, mock-location signal, and open shift state, then writes an attendance event and audit record. Rejected punches are audited too. Missed or incorrect punch requests are separate from verified attendance and can be approved or rejected by Admins and Team Leaders, with RLS and column grants restricting review writes.
- The `project-media` storage bucket is private and limits images to 8 MB. The app uses short-lived signed links for display.

### Attendance trust boundary

The database rechecks the geofence and all submitted fields, but latitude, longitude, accuracy, and Android's mock-location indicator originate on the device. A modified or rooted phone can falsify device-reported location. For higher-assurance workforce enforcement, deploy and verify a server-side Android Play Integrity attestation before accepting `record_attendance` calls. This project does not invent or embed an Integrity service credential.

## Build and check

Requirements: Flutter 3.50 or compatible, Android SDK, and JDK 17. Minimum Android version is 9 (API 28). From this folder:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

`INDETAIL-live-debug.apk` is a **debug-signed live build** for installation and QA; it is not ready for Play Store distribution. A release build needs the company's own signing key and signing configuration; do not reuse a debug key for distribution. `INDETAIL-preview-debug.apk`, when used, is the offline preview build and does not connect to Supabase.

## Project map

- `lib/` — Flutter screens, theme, models, native bridge, repository, and Supabase REST/Auth client.
- `android/` — Android manifest, INDETAIL icon/splash, Keystore-backed PIN/session storage, fingerprint prompt, precise foreground location, and image picker.
- `supabase/migrations/` — ordered schema, security tuning, API grants, Employee IDs, manager workflows, login limits, weekly off days, leave, attendance review controls, holidays, and Admin attendance reporting.
- `supabase/functions/employee-auth/` — email signup and Employee ID login endpoint; only Supabase server secrets are used there.
- `hatchable/` — the public CanvasKit response route and its matching modules, used by the hosted Flutter website.
- `test/` — role/geofence model checks and a branded launch-screen widget test.
