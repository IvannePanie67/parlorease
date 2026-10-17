# ParlorEase

A mobile-first salon booking website and admin dashboard using React, Vite, TypeScript and Supabase. The visual identity uses charcoal, gold and ivory with light/dark/system themes.

## What's included

- Customer homepage and service menu
- Multi-step guest booking flow
- Live availability lookup and database-side booking validation
- Supabase authentication for admin access
- Admin dashboard, appointment status management, service management, staff management, customer directory and reports
- Responsive navigation, accessible form labels, loading/error/empty states, and reduced-motion support
- GitHub Pages deployment workflow

## Important: preview vs live

Without Supabase credentials, the public site runs in preview mode using sample services. The booking form intentionally refuses to create fake bookings. Admin changes and real bookings require a configured Supabase project. Sample names, prices, salon contact details, and opening hours are placeholders; update them before publishing.

## Quick setup

1. Create a Supabase project at https://supabase.com.
2. In the Supabase dashboard, open **SQL Editor**, create a new query, paste all of `supabase/schema.sql`, and run it once.
3. In **Project Settings → API** (or the project's Connect dialog), copy the Project URL and the publishable/anon key.
4. In this repository, create a GitHub Actions repository secret named `VITE_SUPABASE_URL` and another named `VITE_SUPABASE_ANON_KEY`.
5. In **Authentication → Users**, create an administrator user. Use a strong unique password. The database trigger creates a `profiles` row with the default `customer` role.
6. In SQL Editor, grant that account admin role, replacing the email:

   ```sql
   update public.profiles
   set role = 'admin'
   where email = 'your-admin-email@example.com';
   ```

7. In Supabase Authentication URL Configuration, add your GitHub Pages URL to **Site URL** and **Redirect URLs**, for example `https://YOUR-USERNAME.github.io/YOUR-REPOSITORY/`.
8. Push the project to GitHub and enable **Settings → Pages → Build and deployment → GitHub Actions**. The included workflow builds and deploys the app.
9. Visit the published URL and test guest booking and `/admin/login`.

The anon/publishable key is intended to be used in the browser; it is not a secret. Do not put a Supabase `service_role` key in this frontend, repository, or GitHub Actions variables used for the client build.

## Run locally

Requires Node.js 20 or newer.

```bash
npm install
cp .env.example .env.local
# Edit .env.local with your Supabase URL and publishable/anon key
npm run dev
```

To create a production build:

```bash
npm run build
npm run preview
```

## Configure GitHub Pages

The included workflow at `.github/workflows/deploy.yml` builds the frontend and publishes `dist/`. Add the two repository secrets listed above before running the workflow. This project uses hash-based routing, so nested pages work on GitHub Pages.

## Before using for a real salon

- Replace sample service prices and staff names with approved real data.
- Confirm business hours, holidays, booking lead time, cancellation policy, and salon timezone.
- Configure staff working hours in `staff_working_hours`. If no rows exist for a staff member, the database uses the default 9:00 AM–6:00 PM schedule Monday–Saturday; Sundays are closed by default but can be enabled in the staff schedule editor.
- Optionally map staff to eligible services in `staff_services`; staff without mappings are considered eligible for all services.
- Review the RLS policies with a Supabase administrator and test using an anonymous browser session.
- Set up email confirmations/reminders through a trusted email provider before promising automated messages. This starter does not send email/SMS.
- Add a real payment provider only if online deposits/payments are required. The payment status field is for admin-recorded payments and does not charge cards.
- Configure backups, privacy notice, retention policy, and appropriate operational monitoring.

## Data model

`profiles`, `services`, `staff`, `staff_services`, `staff_working_hours`, `staff_time_off`, `appointments`, and `salon_settings`.

Public visitors can read the active service/staff catalog and invoke narrow database functions to check availability and request a booking. Direct public reads of appointment/customer records are blocked by row-level security. Admin UI access is gated by the profile role; database RLS independently protects management data.
