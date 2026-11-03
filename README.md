# T-Money Entertainment — Modernized

Development branch: `modernized`  
Production branch: `main` (do not modify during development)

## First MVP
- Responsive, money-green branded songbook.
- Search by artist, title, or year; sort by artist, title, or year.
- Paginated catalog rendering.
- YouTube search links are convenience links only and do not indicate karaoke-library availability.
- Listed-song requests prefill the request form.
- Unlisted-song requests are accepted.
- The request form opens the guest's SMS app with a prepared message to the existing DJ number. The guest must review and send it.

## Catalog migration
Extracted 2005 song rows from the legacy HTML on `modernized`. Artist, title, and year are retained as supplied. This is the legacy published list, not yet verified against the DJ's current hard-drive library.

## Not implemented yet
- No Supabase database, admin login, or live queue.
- No automated SMS delivery or SMS provider.
- No AI discovery.
- No song availability verification.

## Release rule
GitHub Pages production publishing and the `main` branch remain unchanged until Terin approves release.

## Live queue and DJ dashboard
- `queue.html`: public Now Singing / Coming Up display.
- `dj.html`: private DJ inbox and rotation controls.
- `supabase/schema.sql`: request/event tables, row-level security, DJ actions, realtime publication, and 48-hour cleanup.
- `supabase/functions/submit-request/index.ts`: saves confirmed requests and sends a Twilio SMS when configured.
- `config.js.example`: browser-safe Supabase configuration template.

### Setup before live use
1. Create a Supabase project and run `supabase/schema.sql` in its SQL Editor.
2. Enable Realtime for `karaoke_requests` if the publication setup did not enable it automatically.
3. Copy `config.js.example` to `config.js` and enter the Supabase project URL and anon key. Do not commit real private credentials.
4. Create the DJ Auth user. Set its `app_metadata.role` to `dj` using a trusted admin process; never put the service-role key in browser code.
5. Deploy the `submit-request` Edge Function. Set its Supabase environment variables and, when ready, Twilio secrets: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`, and `TMONEY_DJ_PHONE`.
6. Test public request submission, duplicate prevention, DJ approval, live queue visibility, and the 48-hour deletion before using it at an event.

Guests do not provide phone numbers. Pending requests are DJ-only. Public visitors see only accepted singers. Requests are deleted after 48 hours; no played-history list is kept. SMS is optional and a saved request remains visible to the DJ if SMS delivery fails.
