# ParlorEase setup from an Android phone

This is the phone-first path for preparing the source and pushing it to GitHub. You only need to do this once.

## A. Prepare the project

1. Download `ParlorEase.zip` to your phone and extract it. The extracted folder is named `parlorease`.
2. Install Termux from its official F-Droid distribution if you want to run Node and Git locally. Avoid outdated Termux builds from old app-store listings.
3. Open Termux and run:

   ```sh
   pkg update
   pkg install nodejs-lts git unzip
   termux-setup-storage
   ```

4. If the ZIP is in your Downloads folder, run:

   ```sh
   cd ~/storage/downloads
   unzip ParlorEase.zip
   cd parlorease
   npm install
   npm run build
   ```

   `npm install` needs an internet connection. A successful `npm run build` creates the `dist/` folder.

## B. Create a GitHub repository and push the code

1. Open GitHub in your browser and create a **new empty repository** named `parlorease` (do not initialize it with a README or license because the project already has files).
2. In Termux, from inside the `parlorease` directory, run:

   ```sh
   git init
   git add .
   git commit -m "Build ParlorEase salon system"
   git branch -M main
   git remote add origin https://github.com/YOUR-USERNAME/parlorease.git
   git push -u origin main
   ```

3. Replace `YOUR-USERNAME` with your GitHub username. GitHub does not accept your account password for Git over HTTPS. If prompted for a password, use a GitHub Personal Access Token with repository access, or configure GitHub CLI authentication.

## C. Connect Supabase

1. Create a Supabase project.
2. Open **SQL Editor**, paste the full contents of `supabase/schema.sql`, and run it once.
3. Open **Project Settings → API** (or the Connect panel) and copy the Project URL and publishable/anon key.
4. In GitHub, open your repository's **Settings → Secrets and variables → Actions** and add:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
5. In Supabase **Authentication → Users**, create the admin account. Then run this in SQL Editor, replacing the email:

   ```sql
   update public.profiles
   set role = 'admin'
   where email = 'your-admin-email@example.com';
   ```

## D. Publish with GitHub Pages

1. In the repository, open **Settings → Pages**.
2. Set **Build and deployment → Source** to **GitHub Actions**.
3. Open the **Actions** tab and wait for **Deploy ParlorEase to GitHub Pages** to finish successfully.
4. In Supabase **Authentication → URL Configuration**, add the published GitHub Pages URL to the allowed site/redirect URLs.
5. Open the Pages URL and test a guest booking. Open `/admin/login` on the same site to sign in as the administrator.

## Security notes

- Never put a Supabase `service_role` key in this project. The frontend uses only the public publishable/anon key, with row-level security protecting data.
- Do not commit `.env.local` or other files containing credentials.
- Replace sample salon services, staff names and prices before accepting real bookings.
- Before public production use, configure backups, privacy/cancellation policies, and anti-abuse protections such as CAPTCHA or a rate-limited edge function. The included database function has basic per-contact rate limiting, but it is not a complete anti-bot service.
