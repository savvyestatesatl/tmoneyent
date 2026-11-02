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
