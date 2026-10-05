# Talaria Tracker — iOS ride tracker

A native iOS ride tracker for your Talaria (or any e-moto / bike). Live GPS map,
ride stats, hidden unlockable routes, and a chase mode where something hunts
you down on the map. No Mac needed to build it.

## Features

- **Live ride tracking** — GPS route drawn on the map in real time (standard or
  satellite view), big speedometer HUD, distance / time / avg speed
- **Chase mode** — hit the CHASE MODE button, type a destination address, pick your
  pursuer (The Horde, Rival Rider, Ranger Rick). The app plots an escape route
  using pedestrian paths — tight alleys, trails, and cut-throughs cars can't
  follow — and the chaser hunts you in real time. Reach the flag (within 50 m)
  to escape, or get caught and the ride auto-pauses
- **Hidden routes** — 4 locked routes (Midnight Run, Speed Demon, Century Grind,
  Ghost Trail) that unlock as you ride. Tag rides with the ones you've unlocked
- **Ride history** — every ride saved with its route on a map, full stats, notes,
  and one-tap **GPX export** (share to Strava etc.)
- **Lifetime stats** — total distance / rides / time / top speed, km-h ↔ mph toggle
- Background location so tracking keeps going with the screen locked

## How to get the IPA (free, no Mac)

1. **Put this on GitHub.** Create a new repo at github.com, then upload these
   files (drag the whole `talaria-tracker` folder onto the repo page, or
   `git push` it).
2. **Run the build.** In your repo: **Actions** tab → **Build IPA** →
   **Run workflow**. It compiles on GitHub's Mac runners (~5–10 min, free tier).
3. **Download the IPA.** Open the finished run → download the
   **TalariaTracker-ipa** artifact → unzip to get `TalariaTracker.ipa`.

## How to install it on your iPhone (free)

The IPA is unsigned, so sideload it with your free Apple ID:

- **Sideloadly** (Windows — easiest from your PC) or **AltStore**/**SideStore**.
  Install `TalariaTracker.ipa` through it with your Apple ID.
- Free Apple IDs: the app expires every 7 days — just hit **Refresh** in
  Sideloadly/AltStore/SideStore to re-sign it. Also, the **first launch needs
  Wi-Fi** so Apple can verify the certificate.
- On first launch, allow location access ("Allow While Using") or the map and
  tracking won't work.

## Notes

- Bundle ID is `com.example.talariatracker` — change `PRODUCT_BUNDLE_IDENTIFIER`
  in the Xcode project if you want your own.
- Requires iOS 17+.
- Chase mode is a game — the chaser is virtual. Don't actually outrun the police.
