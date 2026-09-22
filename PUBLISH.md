# Publishing this update

Three parts: put the files in your repo, update the database, push.

## 1. Replace the files (PowerShell)

Unzip `akarat-ai.zip` somewhere, then copy it over your repository. Your repo
is at `C:\Users\tariq\Downloads\akarat-ai\akarat-ai`; adjust if that moved.

```powershell
cd C:\Users\tariq\Downloads\akarat-ai\akarat-ai
git pull

Expand-Archive -Path "$HOME\Downloads\akarat-ai.zip" -DestinationPath "$HOME\Downloads\akarat-new" -Force
robocopy "$HOME\Downloads\akarat-new\akarat-ai" . /E /XD .git node_modules .next public
```

`robocopy` copies everything and leaves your `.git` folder alone. It prints a
summary table; exit codes 0 to 7 all mean success.

## 2. Check it builds (optional but worth ten seconds)

```powershell
npm install
npm run build
```

You want `✓ Compiled successfully`.

## 3. Commit and push

```powershell
git add -A
git commit -m "New logo, hero video fix, locations for every area in the form"
git push origin main
```

Vercel deploys on its own after the push.

## 4. Supabase — do not skip this

Supabase dashboard → SQL Editor → New query. Paste each file, click Run,
in this order:

1. `supabase/migrations/0007_listing_video.sql`
2. `supabase/migrations/0008_hardening.sql`
3. `supabase/migrations/0009_locations.sql`  ← fixes the foreign key error

All three are safe to run even if you already ran some of them.

## 5. Check

- Publish a listing in a new area such as Rabieh or Karak — it should save.
- Home page: the video keeps playing after you switch tabs and come back.
- Browser tab shows the new icon (use a private window; icons cache hard).
- Paste your site link into WhatsApp — the preview shows the logo card.
