# Nest push Worker

This is the only server piece, and it runs on the Cloudflare Workers free plan. The app calls `POST /push` in three cases:

- **A timer starts.** The Worker sends a Live Activity *push-to-start* to the partner's phone.
- **A timer changes or stops.** The Worker sends a Live Activity update or end to the partner's running activity.
- **The feed alarm is stopped or snoozed.** The Worker sends a background push, so the partner's app syncs and silences or reschedules its alarm.

Nothing is stored. Tokens come from the shared `deviceTokens` table in CloudKit.

## Deploy

1. In the Apple Developer portal, create an APNs key under Keys → + → Apple Push Notifications service. Download `AuthKey_XXXXXXXXXX.p8`.
2. Deploy the Worker:

   ```sh
   cd Nest/worker
   npx wrangler login
   npx wrangler secret put APNS_KEY_ID   # the 10-character key ID
   npx wrangler secret put APNS_KEY      # paste the whole .p8 file
   npx wrangler secret put NEST_KEY      # any long random string
   npx wrangler deploy
   ```

3. Set `NEST_WORKER_URL` (for example `https://nest-push.<you>.workers.dev`) and `NEST_WORKER_KEY` (the same `NEST_KEY`) in `project.yml`.
4. In `wrangler.toml`, set `APNS_ENV` to `development` for builds run from Xcode. Use `production` for TestFlight.

Tests: `node --test`.
