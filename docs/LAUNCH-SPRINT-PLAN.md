# Drape Launch Sprint: Mapped Plan

Source: `SPRINT-LAUNCH.md` (written for an Expo/React Native + Google/Apple login app called ClosetEye),
mapped onto the real codebase: **Flutter + Firebase Phone Auth + FastAPI/Postgres, brand Drape**.

Status: **approved 2026-11-19. Launch cut built on branch `DR-S9-launch`.**

Done for launch: DR-S9-02, 03, 04, 05, 06, 07, 08, 09 (Alembic URL; full squash deferred), 10, 11, 12 (threadpool;
job queue deferred), 13, 14 (flags), 15, 16 (outfit engine), 17 (streak unified; tables merge deferred), 18, 19, 21 (wardrobe,
outfits), 40, 41, 42, 60, 61, 62 (server side), 63 (LLM analyses), 74, 77, 83, 84 (Android signing + build script), 87, 95.
Also: Android release manifest was missing INTERNET permission; default Flutter app icon replaced.

Blocked on Nil: DR-S9-01 (key rotation). Everything else stays in the order below, after launch.

---

## 0. Decisions I made (shout if you disagree)

| Decision | Why |
|---|---|
| Ticket prefix is **`DR-S9-xx`**, not `DR-S2-xx` | `SCRUM.md` already uses DR-S2-01..09 (Body Model sprint, done). Sprint 9 is "App Store Launch" and is the open sprint, so this plan becomes Sprint 9 and absorbs its 13 existing tickets (mapping noted per row). |
| Drop our own JWT. The app sends its **Firebase ID token** on every request; the backend verifies it with the Admin SDK | The Firebase SDK already refreshes tokens hourly and supports revocation. That removes CE-S2-12's whole refresh-token system plus the 7-day JWT problem. |
| Postgres-backed job queue, **no Redis** | One fewer paid service. Rate limits and quotas also live in Postgres. |
| API + worker on **Cloud Run** (same Google Cloud project as Firebase); Postgres on **Neon** free tier with pgvector | Cheapest path for a free app. Cloud SQL is the alternative if you want everything in Google Cloud (about $10/month minimum). |
| Image storage on **Cloud Storage for Firebase**, private bucket, deny-all security rules, backend issues signed URLs | The Firebase equivalent of the R2 ticket. Clients never touch the bucket directly, so the rules can be fully closed. |
| Fresh squashed initial migration | There is no production data yet (same call the sprint file made). |

---

## 1. Epic A: Fresh bug audit of this codebase (replaces the old Epic A)

Found by reading every backend route and service plus `flutter analyze`. Severity: 🔴 must fix before any beta, 🟠 before launch, 🟡 cleanup.

| ID | Sev | Bug | Fix |
|---|---|---|---|
| DR-S9-01 | 🔴 | **Firebase Admin private key committed and pushed** (`backend/closeteye-c2c03-firebase-adminsdk-fbsvc-9f00efc22b.json`, commit `124eb55`, on `origin/CE-S1-01` and `origin/DR-S2-01`). Also, the Docker mount `./backend/firebase-service-account.json` is a *directory* (Docker created it because the file was missing). | **Blocked on Nil rotating the key.** Then untrack it, purge it from history (force-push), and load creds from env / Secret Manager only. |
| DR-S9-02 | 🔴 | **Try-on and flat-lay IDOR.** `tryon_service.generate_try_on_preview` and `flatlay_service.generate_flatlay` load `ClothingItem` by id with **no owner filter**. Any user can render another user's garments and have them sent to OpenAI/Replicate. | Filter by `owner_id`; return 404 for foreign ids; add tests. |
| DR-S9-03 | 🔴 | **Client-controlled image URLs, leading to SSRF.** `POST /wardrobe/batch-add` stores `original_image_url` / `product_image_url` exactly as the client sends them. Try-on and flat-lay later `httpx.get()` those URLs from the server. Attackers can point items at internal hosts or other users' files. | Items reference server-issued storage keys only. Services read bytes from storage by key and never fetch arbitrary URLs. |
| DR-S9-04 | 🔴 | **Write IDOR in outfit engine + outfits + OOTD.** `/outfit/wear` increments `total_wears` on *anyone's* items; `/outfit/feedback` reads foreign items; `outfit_id` / `daily_outfit_id` are unchecked; `POST /outfits/` attaches foreign items (FK 500 on random ids); `/ootd` accepts foreign `outfit_id` / `custom_item_ids`. | Ownership validation helper used by every route that takes ids. Dedupe ids and return 422 for unknown ones. |
| DR-S9-05 | 🔴 | **Every upload is public, including body photos.** `/uploads` is a public static mount; body photos sit at a predictable `uploads/body_models/{user_id}/original.jpg`. No EXIF strip, so phone GPS is kept. | Private storage + short-lived signed URLs (DR-S9-22). Strip EXIF, cap at 2048px. |
| DR-S9-06 | 🔴 | **Dev Settings server switcher ships in release builds.** Anyone holding the phone can point the app at any host, and that host then receives the bearer token. The default server is the LAN IP `http://10.0.0.14:8000`. | Flavors via `--dart-define` (dev / staging / prod). Dev Settings only in debug builds. |
| DR-S9-07 | 🔴 | **Production config unsafe.** `SECRET_KEY` default, `DEBUG=True` (SQL echo logs phone numbers), CORS `*` with credentials, 500 responses leak internals (`Database error: …`, `Upload processing failed: {exc}`), phone numbers logged at INFO. | `ENV` setting; refuse to boot in prod with unsafe config; global error handler returning `{error:{code,message}}`; scrub PII from logs. |
| DR-S9-08 | 🔴 | **Session handling.** 7-day JWT with no revocation; the app never handles 401, so it stays "logged in" but broken. Unused `passlib` / `bcrypt` / `hash_password`. | Verify the Firebase ID token per request (see section 0); Flutter HTTP wrapper refreshes the token or signs out on 401; delete the password code. |
| DR-S9-09 | 🟠 | **Schema drift.** `main.py` runs `Base.metadata.create_all` on startup alongside Alembic, which is why the new migration needs `_table_exists` guards. `alembic/env.py` uses the ini URL, not `settings.DATABASE_URL`. | Remove `create_all`; Alembic reads settings; fresh initial migration; `upgrade head` on an empty DB and `downgrade base` in CI. |
| DR-S9-10 | 🟠 | Deleting an item used in an outfit causes an FK error (500) via `outfit_items` and `outfit_history.outfit_id`. Cached daily outfits keep pointing at deleted items (Flutter papers over it with `ClothingItem.empty`). | `ondelete` rules, drop outfits that become empty, invalidate the daily cache on wardrobe change. |
| DR-S9-11 | 🟠 | Bad input causes 500s: ids typed `list[str]` then `uuid.UUID(iid)`, `date.fromisoformat(worn_date)` unchecked. | Typed `UUID` / `date` fields in the schemas. |
| DR-S9-12 | 🟠 | **CPU work blocks the event loop.** rembg, Pillow, `replicate.run`, `urllib` run inside async request handlers, so one upload freezes the API for every user. | Move to the worker queue (DR-S9-23). |
| DR-S9-13 | 🔴 | **Unbounded AI spend.** One `/extract-items` call = GPT-4o detect + GPT-4o describe + a gpt-image-1 / DALL·E render **per garment**. Try-on can chain IDM-VTON, then gpt-image-1 single, then gpt-image-1 multi. Style DNA and gap analysis call an LLM on every screen load. No quotas, no rate limits. | Cost epic (G) before anything else goes to beta. |
| DR-S9-14 | 🔴 | **Licensing.** Try-on's primary path is IDM-VTON, which is licensed **CC BY-NC-SA 4.0 (non-commercial)**, even when called via Replicate. Also, `generate_product_image` shows an AI *re-render* as the user's item, so it is not their actual garment. | Commercial try-on provider (Nil to pick); real cutouts instead of re-renders. Record in `docs/MODELS.md`. |
| DR-S9-15 | 🟠 | `POST /shopping/items` checks only the client `content_type`; Flutter often sends `application/octet-stream`, so real photos are rejected. `/extract-items` has no size cap. Expired shopping items and their files are never deleted. | One shared upload validator; expiry cleanup job. |
| DR-S9-16 | 🟠 | "Today" means the server clock (`date.today()`) for daily outfits, streaks and notifications. Wrong for every user once deployed in UTC. | Store the user's timezone; compute local dates. |
| DR-S9-17 | 🟠 | Two parallel engines and two wear logs. `/suggestions` (GPT-4o) vs `/outfit/daily` (algorithmic); `ootd_logs` vs `outfit_history`. The streak reads `ootd_logs` but the new "I wore this" writes `outfit_history`, so **wearing an outfit never counts toward the streak**. | One engine, one wear log, migrate the data. |
| DR-S9-18 | 🟡 | `flutter analyze`: 2 errors (dead `add_item_screen.dart` calls a nonexistent `ApiClient.addItem`; `test/widget_test.dart` references `MyApp`, so `flutter test` fails), 11 warnings, about 300 infos. | Delete dead code; real smoke test; analyzer clean. |
| DR-S9-19 | 🟡 | `docker-compose` exposes Postgres on `0.0.0.0:5432` with password `closeteye`; the Dockerfile runs `--reload` as root. | Bind to 127.0.0.1; production image: non-root, gunicorn workers, healthcheck. |
| DR-S9-20 | 🟡 | `SCRUM.md` marks work done that isn't: FCM push (S7-05) has no `firebase_messaging` and notifications are poll-only rows. Stale docs: `IMPLEMENTATION_COMPLETE.md`, `ABSOLUTE_FILE_PATHS.txt`, `FILES_MANIFEST.txt`, `.env.example` (Google/Apple keys). | Correct the board; delete stale docs; new README. |
| DR-S9-21 | 🟡 | No pagination on list endpoints. | `limit` + `cursor` everywhere. |

---

## 2. Outfit engine WIP review (`wip/outfit-engine`)

Checked against CE-S2-49/50 (outfit generator + feedback learning). **Not mergeable yet.**

**Must fix before merge**
1. Security: DR-S9-04 and DR-S9-11 issues in `/outfit/wear` and `/outfit/feedback`.
2. **A jacket is forced into every outfit whenever you own any outerwear**, even at 30°C (`jkt_list` never includes `None`).
3. Only the first 6 tops × 6 bottoms × 3 shoes × 2 jackets are ever considered, in undefined DB order, so most of a large wardrobe is never suggested.
4. No diversity: the 3 picks can share the same top and bottom. Needs MMR as the ticket specifies.
5. **The Flutter daily screen never sends lat/lon**, so weather is always "unknown" and the weather score is a constant 18.
6. Cached response omits `daily_outfit_id` (feedback from a cached view can't link back) and can reference deleted items.
7. `GET /daily` creates the "morning" notification whenever the app is opened. Side effects in a GET; this moves to the scheduler.
8. Flutter: Mix & Match drops score updates while a request is in flight (shows a stale score after fast swaps); feedback chips show "liked" even when the request failed; a no-op line in `tryon_screen.dart:153`.
9. No tests. The ticket's AC needs fixture-wardrobe tests and **200 items in under 300 ms**.

**To finish it (in scope for merge):** candidate generation over the full wardrobe with pruning; optional outerwear by temperature; MMR top-K; disliked pairs as hard excludes ("never pair"); no-repeat window; lock items ("build around this", DR-S9-42) since the API shape depends on it; unify with `/suggestions` and the wear log (DR-S9-17); tests + perf benchmark.

---

## 3. Mapped tickets

`Was` = source ticket in SPRINT-LAUNCH.md (or old Sprint 9 id). ✱ = Firebase/Flutter equivalent swapped in.

### Epic B: Ingestion pipeline
| ID | Ticket | Was |
|---|---|---|
| DR-S9-22 | ✱ Storage service: Cloud Storage for Firebase (private, deny-all rules, Admin SDK, V4 signed URLs); local disk in dev. Keys `users/{uid}/items/{id}/{original\|cutout\|clean\|thumb}.webp` | CE-32, 03, 04 |
| DR-S9-23 | Postgres-backed job queue + Cloud Run worker; upload returns 202 + `processing_status`; Flutter shimmer card + polling | CE-33 |
| DR-S9-24 | Shared upload validator: Pillow sniff, HEIC via pillow-heif, EXIF strip, 2048px cap | CE-14 |
| DR-S9-25 | rembg (BiRefNet/u2net) on the worker, auto-crop + padding; Remove.bg only as a flagged fallback | CE-35 |
| DR-S9-26 | Free-first tagging: open_clip zero-shot (category, subcategory, pattern, formality, warmth, seasons, style); gpt-4o-mini only on low confidence; `needs_review` | CE-37 |
| DR-S9-27 | Color extraction: k-means in LAB + named palette | CE-38 |
| DR-S9-28 | Clean-up step (straighten, white balance, denoise, neutral background); optional quota'd "AI polish"; original always kept | CE-36 |
| DR-S9-29 | Multi-garment split + mirror-selfie mode with a commercially-licensed segmentation model (replaces GPT-4o detect + re-render) | CE-34 |
| DR-S9-30 | Duplicate detection (pHash + embedding) | CE-39 |
| DR-S9-31 | Import from product link (OpenGraph / JSON-LD) | CE-40 |
| DR-S9-32 | ✱ Import from screenshot + share sheet (`receive_sharing_intent`) | CE-41 |
| DR-S9-33 | ✱ Batch upload (30 photos), persistent queue that survives backgrounding (`background_downloader`) | CE-42 |
| DR-S9-34 | Item schema extension + pgvector (status, formality, warmth, seasons[], style_tags, price, wear stats, source, phash, embedding…) | CE-43 |

### Epic C: Wardrobe UI (Flutter; grid, category filter, delete and empty state already exist)
| ID | Ticket | Was |
|---|---|---|
| DR-S9-35 | Search, filter sheet, sort (incl. rainbow) | CE-44 |
| DR-S9-36 | Item detail: before/after, editable tag chips, price/brand/size, cost per wear, "outfits with this", actions | CE-45 |
| DR-S9-37 | Add-item flow: framing guide, multi-select, paste link, screenshot, review detected items | CE-46 |
| DR-S9-38 | Laundry mode | CE-47 |
| DR-S9-39 | Onboarding progress meter (5 items, then 15) + friendly empty states | CE-48 |

### Epic D: Outfit engine + outfits UI
| ID | Ticket | Was |
|---|---|---|
| DR-S9-40 | **Finish + merge outfit engine WIP** (section 2) | CE-49 |
| DR-S9-41 | Feedback learning incl. "never pair these" | CE-50 |
| DR-S9-42 | Build around this item (lock) | CE-51 |
| DR-S9-43 | Shuffle reels with haptics | CE-52 |
| DR-S9-44 | Manual builder canvas + server-side Pillow composite (extends Mix & Match) | CE-53 |
| DR-S9-45 | Occasions + dress-code decoder (rules table first, cached LLM fallback) | CE-54 |
| DR-S9-46 | Mood picker | CE-55 |
| DR-S9-47 | Outfits tab: For you / Saved / Worn + calendar (merge the OOTD calendar) | CE-56 |

### Epic E: Daily habit
| ID | Ticket | Was |
|---|---|---|
| DR-S9-48 | Outfit of the Day home card: weather (Open-Meteo, coarse location via `geolocator`) + best + 2 alternates; Wear / Swap / Shuffle | CE-57 |
| DR-S9-49 | ✱ Morning push via **FCM**: `firebase_messaging`, device-token table, per-timezone scheduler in the worker, user-chosen time | CE-58, S7-05 |
| DR-S9-50 | ✱ On-device calendar hints (`device_calendar`), only the inferred occasion is sent | CE-59 |
| DR-S9-51 | Single wear log + streak (after DR-S9-17) | CE-60 |
| DR-S9-52 | No-repeat window setting | CE-61 |
| DR-S9-53 | Cost-per-wear in item detail + insights (backend exists) | CE-62 |
| DR-S9-54 | ✱ Home-screen widget (`home_widget`), stretch | CE-63 |

### Epic F: Insights + shopping
| ID | Ticket | Was |
|---|---|---|
| DR-S9-55 | Gap analysis rewritten algorithmically against a ~150-basics catalog (replaces the LLM call); `ShoppingLinkProvider` interface | CE-64 |
| DR-S9-56 | Closet insights screen | CE-65 |
| DR-S9-57 | Declutter assistant | CE-66 |
| DR-S9-58 | Style DNA: computed stats + one cached LLM title, at most weekly (exists, uncached today) | CE-67 |
| DR-S9-59 | "Before you buy" guard, built on the existing Try Before You Buy shopping items | CE-68 |

### Epic G: Cost controls (must land before beta; current code spends freely)
| ID | Ticket | Was |
|---|---|---|
| DR-S9-60 | `ai_usage` ledger, every paid call writes a row | CE-69 |
| DR-S9-61 | Per-user daily quotas + friendly limit copy | CE-70 |
| DR-S9-62 | ✱ Global `DAILY_AI_BUDGET_USD` kill switch (server) + **Firebase Remote Config** flags so the app hides paid features cleanly | CE-71 |
| DR-S9-63 | Content-hash caching (tags, polish, try-on, dress codes, explanations) | CE-72 |
| DR-S9-64 | ✱ **Firebase App Check** enforced on the API (stops scripts from burning AI budget) | new |
| DR-S9-65 | Rate limiting per user + IP (Postgres token bucket) | CE-16 |

### Epic H: Virtual try-on (beta)
| ID | Ticket | Was |
|---|---|---|
| DR-S9-66 | Free Pillow flat-lay compositor as the default preview and fallback (replaces paid gpt-image-1 flat-lay) | CE-76 |
| DR-S9-67 | Body photo privacy: private storage, delete any time, pose check (body model exists) | CE-74 |
| DR-S9-68 | Async try-on jobs on a **commercially-licensed** provider; `tryon_jobs` table | CE-75, 78 |
| DR-S9-69 | Try-on screen: Beta label, progress, compare slider, save/share | CE-77 |

### Epic I: Sharing
| ID | Ticket | Was |
|---|---|---|
| DR-S9-70 | ✱ Share card (`RepaintBoundary` + `share_plus`) | CE-79 |
| DR-S9-71 | Fit Check public link with OpenGraph image, 7-day expiry, vote rate limit | CE-80 |
| DR-S9-72 | Packing planner | CE-81 |
| DR-S9-73 | ✱ Invite links via **App Links / Universal Links** hosted on Firebase Hosting (Firebase Dynamic Links has been shut down) | CE-82 |

### Epic K: Accounts, compliance, infra
| ID | Ticket | Was |
|---|---|---|
| DR-S9-74 | ✱ Delete account: DB rows + all storage objects + **Firebase Auth user** (Admin SDK) | CE-83 |
| DR-S9-75 | Export my data (zip + signed link) | CE-84 |
| DR-S9-76 | Settings screen | CE-85 |
| DR-S9-77 | ✱ Privacy policy + terms on **Firebase Hosting**, linked from login | CE-86, 28, S9-01, S9-02 |
| DR-S9-78 | Onboarding: 3 slides, style quiz, permission priming | CE-87 |
| DR-S9-79 | ✱ Reviewer access via **Firebase Auth test phone numbers** + seeded demo account | CE-88 |
| DR-S9-80 | Seed demo wardrobe (40 license-safe items) | CE-89 |
| DR-S9-81 | ✱ **Crashlytics + Firebase Analytics** (mobile), Sentry (backend); funnel events, no PII | CE-90, S9-05, S9-06 |
| DR-S9-82 | ✱ Deploy: Cloud Run API + worker, Neon Postgres + pgvector, Secret Manager, migrations on deploy, **separate Firebase projects for dev / staging / prod** | CE-91, S9-08, S9-09 |
| DR-S9-83 | CI: GitHub Actions (ruff, pytest with Postgres, `flutter analyze`, `flutter test`); block merge | CE-92, S9-07 |
| DR-S9-84 | ✱ Release pipeline: Flutter flavors, fastlane, **Firebase App Distribution** for testers, TestFlight, Play internal | CE-93 |
| DR-S9-85 | ✱ Dependency refresh (`flutter pub outdated`, firebase_* current, pinned Python deps, store SDK minimums) | CE-30 |
| DR-S9-86 | Repo hygiene: README, `.editorconfig`, pre-commit (ruff, `dart format`) | CE-31 |
| DR-S9-87 | ✱ Permission strings: Info.plist + AndroidManifest (camera, photos, location, notifications, calendar) | CE-27 |
| DR-S9-88 | Avatar upload through the storage service | CE-15, 26 |

### Epic L: Polish (design system, icons, haptics and motion were done in Sprint 8)
| ID | Ticket | Was |
|---|---|---|
| DR-S9-89 | Accessibility: Semantics labels, dynamic type, AA contrast, color names read aloud | CE-97 |
| DR-S9-90 | Offline: cached wardrobe + today's outfit; queued uploads | CE-98 |
| DR-S9-91 | Performance: 400px WebP thumbnails, lazy grids, cold start < 2s on mid-range Android | CE-99 |

### Epic M: QA + launch
| ID | Ticket | Was |
|---|---|---|
| DR-S9-92 | Backend tests incl. a parametrized **ownership test that hits every route** | CE-100 |
| DR-S9-93 | Flutter widget tests + one Maestro E2E (onboarding, add item, outfit, share) | CE-101 |
| DR-S9-94 | `docs/QA.md` manual checklist | CE-102 |
| DR-S9-95 | Store assets + `docs/STORE.md` (privacy labels, Data safety) | CE-103, S9-03, S9-04 |
| DR-S9-96 | Beta: 30–50 testers via App Distribution / TestFlight / Play internal, shake to report | CE-104, S9-10, S9-11 |
| DR-S9-97 | Store submissions | S9-12, S9-13 |
| DR-S9-98 | Landing page on Firebase Hosting | CE-105 |

### Dropped
| Was | Why |
|---|---|
| CE-09, 10, 11 | Google/Apple sign-in, identity linking, JWKS caching: the app uses phone auth only. (Apple only requires Sign in with Apple when other third-party logins are offered.) |
| CE-12, 19, 20 | Replaced by Firebase ID token verification (DR-S9-08); `get_db` folded into DR-S9-07/09. |
| CE-23, 24, 25 | axios / app.config.ts / ImagePicker API: Expo-only. The Flutter equivalent is DR-S9-06. |
| CE-29, 94, 95, 96 | Icons, design system, app icon/splash, motion/haptics: done in Sprint 8 (I'll only verify the icon assets build). |
| CE-05 | Already fixed: `outfits.py` maps `items` into `clothing_item_ids`. |
| CE-01, 02, 03, 04, 06, 07, 08, 13, 14, 17, 18, 21, 22 | Not dropped. Re-found against this code and folded into Epic A above. |

---

## 4. Execution order

1. **Outfit engine WIP**: fix section 2, finish DR-S9-40/41/42, tests, merge `wip/outfit-engine` (as you asked).
2. **Security criticals**: DR-S9-02, 03, 04, 05, 06, 07, 08, then 01 once the key is rotated.
3. **Foundation**: DR-S9-09, 11, 18, 19, 83 (CI early), 85, 86.
4. **Final schema + fresh migration** (DR-S9-34 and all new tables), then DR-S9-10, 15, 16, 17, 21.
5. **Cost controls** DR-S9-60–65 (before any beta user touches paid AI).
6. Ingestion 22–33 → Wardrobe UI 35–39 → Engine rest 43–47 → Daily habit 48–54 → Insights 55–59 → Try-on 66–69 → Sharing 70–73 → Accounts/infra 74–88 → Polish 89–91 → QA/launch 92–98.

After every epic: `ruff`, `pytest`, `flutter analyze`, `flutter test` all green. One commit per ticket: `DR-S9-xx: …`.

---

## 5. Needs Nil (also tracked in `docs/NEEDS_NIL.md`)

- **Rotate the Firebase Admin key now** (Firebase console → Project settings → Service accounts). Approve the history rewrite + force-push.
- **App identity before the first store upload** (it can't be changed afterwards): bundle / application id is still `com.closeteye.closeteye`, Firebase project `closeteye-c2c03`. Keep, or switch to e.g. `app.drape.ios`?
- Commercial try-on provider choice (IDM-VTON is non-commercial).
- `DAILY_AI_BUDGET_USD` number and an OpenAI budget cap.
- Firebase **Blaze** plan (required for Cloud Storage buckets, Cloud Run and App Check enforcement at scale) plus separate staging/prod Firebase projects.
- Neon vs Cloud SQL; domain name; Apple Developer + Play Console accounts; legal review; beta tester list.
