# Drape — Product Scrum Board
### *"Your closet, reimagined by AI"*

**Theme:** White + glass morphism soft light UI
**Platform:** iOS & Android mobile app
**Backend:** FastAPI + PostgreSQL (Docker Compose), private API
**Auth:** Firebase Phone Auth (OTP) — iOS & Android
**Goal:** #1 trending fashion app of the year

> Branch naming: `feature/CE-S{sprint}-{id}-short-description`
> Example: `feature/CE-S1-01-apple-sign-in`

---

## 🧠 Product Vision (Co-Founder Notes)

The full loop that makes Drape special:

```
📸 Photo anything (worn / on bed / store shelf)
    ↓ AI extracts the garment
    ↓ Placed on YOUR body model
    ↓ Mix with clothes you own OR clothes you're considering
    ↓ AI scores the outfit + suggests what to buy
    ↓ Track cost per wear, style DNA, capsule score
```

**What makes this viral:**
- Body model from YOUR photo (not a generic mannequin)
- Try on clothes you haven't bought yet — mix with what you own
- Capsule Score gamification — people will obsess over improving it
- Cost Per Wear — data people love to share
- OOTD habit loop — daily engagement, high retention

---

## Legend
- 🔴 Critical path (must have)
- 🟡 Important (should have)
- 🟢 Nice to have / viral feature
- ✅ Done

---

## Sprint 0 — Project Setup ✅ COMPLETE

| Story ID | Task | Status |
|----------|------|--------|
| CE-S0-01 | Initialize FastAPI project structure | ✅ |
| CE-S0-02 | PostgreSQL + Docker Compose setup | ✅ |
| CE-S0-03 | SQLAlchemy models (User, ClothingItem, Outfit) | ✅ |
| CE-S0-04 | Alembic migrations — initial tables | ✅ |
| CE-S0-05 | React Native (Expo) app skeleton | ✅ |
| CE-S0-06 | 5-tab navigation shell | ✅ |
| CE-S0-07 | API client (Axios + interceptors) | ✅ |

---

## Sprint 1 — Authentication & User Profile ✅ COMPLETE
> **Goal:** Phone number OTP login via Firebase, stay logged in, set up profile.
> **Pivot note:** Switched from Apple/Google Sign In → Firebase Phone Auth (OTP) for faster iteration and no App Store review dependency.

| Story ID | Task | Priority | Status |
|----------|------|----------|--------|
| CE-S1-01 | Backend: Firebase Admin SDK — verify phone auth ID token | 🔴 | ✅ |
| CE-S1-02 | Backend: `POST /auth/phone` — create/find user, return JWT | 🔴 | ✅ |
| CE-S1-03 | Backend: PostgreSQL user model (phone_number, firebase_uid, full_name, avatar_url) | 🔴 | ✅ |
| CE-S1-04 | Backend: Alembic migration — phone auth schema | 🔴 | ✅ |
| CE-S1-05 | Backend: `PATCH /auth/profile` — update name & avatar | 🟡 | ✅ |
| CE-S1-06 | Mobile: login screen UI (glass morphism, phone input) | 🔴 | ✅ |
| CE-S1-07 | Mobile: OTP screen — 6-digit code entry | 🔴 | ✅ |
| CE-S1-08 | Mobile: iOS — custom PhoneAuthPlugin (Firebase on main actor, SFSafariViewController reCAPTCHA) | 🔴 | ✅ |
| CE-S1-09 | Mobile: Android — standard Firebase `verifyPhoneNumber` | 🔴 | ✅ |
| CE-S1-10 | Mobile: store JWT in SharedPreferences, auto-login on launch | 🔴 | ✅ |
| CE-S1-11 | Mobile: `AppAuthProvider` (ChangeNotifier) — auth state management | 🔴 | ✅ |
| CE-S1-12 | Mobile: profile setup screen (name entry, "What should we call you?") | 🟡 | ✅ |
| CE-S1-13 | Mobile: logout flow + token clear | 🟡 | ✅ |

---

## Sprint 2 — Body Model Creation
> **Goal:** User creates their personal body model used for all try-ons. This is the foundation of the try-on experience — a realistic silhouette, not a generic mannequin.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S2-01 | Mobile: body model onboarding screen ("Let's build your model") | 🔴 | `feature/CE-S2-01-body-model-onboarding` |
| CE-S2-02 | Mobile: collect body measurements (height, weight, body type) | 🔴 | `feature/CE-S2-02-body-measurements-form` |
| CE-S2-03 | Mobile: front-facing reference photo capture for body model | 🔴 | `feature/CE-S2-03-body-photo-capture` |
| CE-S2-04 | Backend: generate body silhouette from reference photo + measurements | 🔴 | `feature/CE-S2-04-body-silhouette-generation` |
| CE-S2-05 | Backend: store body model (measurements + processed image) | 🔴 | `feature/CE-S2-05-body-model-storage` |
| CE-S2-06 | Backend: `POST /users/me/body-model` endpoint | 🔴 | `feature/CE-S2-06-body-model-endpoint` |
| CE-S2-07 | Mobile: body model preview screen (show generated silhouette) | 🟡 | `feature/CE-S2-07-body-model-preview` |
| CE-S2-08 | Mobile: update body model later (from profile settings) | 🟡 | `feature/CE-S2-08-update-body-model` |
| CE-S2-09 | Backend: add body model fields to User model (migration) | 🔴 | `feature/CE-S2-09-user-model-migration` |

---

## Sprint 3 — Wardrobe Core (Smart Upload)
> **Goal:** User photographs clothes in ANY way — wearing them, on a bed, hanging up — AI extracts the garment cleanly and adds it to the wardrobe.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S3-01 | Backend: file upload service (local storage / S3) | 🔴 | `feature/CE-S3-01-file-upload-service` |
| CE-S3-02 | Backend: detect photo type — is person wearing it, or flat lay? | 🔴 | `feature/CE-S3-02-photo-type-detection` |
| CE-S3-03 | Backend: extract garment from flat-lay / hanger photo (background removal) | 🔴 | `feature/CE-S3-03-flatlay-extraction` |
| CE-S3-04 | Backend: extract garment from photo of person wearing it (person + cloth segmentation) | 🔴 | `feature/CE-S3-04-worn-photo-extraction` |
| CE-S3-05 | Backend: dewrinkle + clean up extracted garment image | 🟡 | `feature/CE-S3-05-dewrinkle-pipeline` |
| CE-S3-06 | Backend: AI attribute detection — color, category, pattern, fabric via OpenAI Vision | 🔴 | `feature/CE-S3-06-attribute-detection` |
| CE-S3-07 | Backend: auto-fill ClothingItem fields from AI response | 🔴 | `feature/CE-S3-07-auto-fill-item` |
| CE-S3-08 | Mobile: camera screen — take photo (any style) | 🔴 | `feature/CE-S3-08-camera-capture` |
| CE-S3-09 | Mobile: gallery picker — choose from photos | 🔴 | `feature/CE-S3-09-gallery-picker` |
| CE-S3-10 | Mobile: AI processing loader ("Extracting your item...") | 🟡 | `feature/CE-S3-10-processing-loader` |
| CE-S3-11 | Mobile: item review screen — confirm / edit AI-detected fields | 🔴 | `feature/CE-S3-11-item-review-screen` |
| CE-S3-12 | Mobile: wardrobe grid screen (masonry layout, white/burgundy) | 🔴 | `feature/CE-S3-12-wardrobe-grid` |
| CE-S3-13 | Mobile: filter wardrobe by category | 🟡 | `feature/CE-S3-13-wardrobe-filters` |
| CE-S3-14 | Mobile: delete item (swipe or long-press) | 🟡 | `feature/CE-S3-14-delete-item` |
| CE-S3-15 | Mobile: empty state ("Add your first item") | 🟢 | `feature/CE-S3-15-empty-state` |

---

## Sprint 4 — Virtual Try-On (Wardrobe Items)
> **Goal:** User selects items from their wardrobe, sees them on their personal body model instantly.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S4-01 | Backend: pose estimation on body model image | 🔴 | `feature/CE-S4-01-pose-estimation` |
| CE-S4-02 | Backend: garment warping — fit clothing to body shape | 🔴 | `feature/CE-S4-02-garment-warping` |
| CE-S4-03 | Backend: composite — layer multiple garments on body model | 🔴 | `feature/CE-S4-03-garment-composite` |
| CE-S4-04 | Backend: `POST /tryon` endpoint — accepts item IDs, returns preview URL | 🔴 | `feature/CE-S4-04-tryon-endpoint` |
| CE-S4-05 | Mobile: try-on screen — select items from wardrobe | 🔴 | `feature/CE-S4-05-tryon-item-selector` |
| CE-S4-06 | Mobile: try-on result — view on your body model | 🔴 | `feature/CE-S4-06-tryon-result-screen` |
| CE-S4-07 | Mobile: swap individual items in the try-on view | 🟡 | `feature/CE-S4-07-swap-items-tryon` |
| CE-S4-08 | Mobile: save try-on look as an outfit | 🔴 | `feature/CE-S4-08-save-tryon-as-outfit` |
| CE-S4-09 | Mobile: save try-on image to camera roll | 🟡 | `feature/CE-S4-09-save-to-camera-roll` |
| CE-S4-10 | Mobile: loading animation during AI processing | 🟡 | `feature/CE-S4-10-tryon-loading` |

---

## Sprint 5 — Shopping Try-On (Try Before You Buy)
> **Goal:** User uploads a photo of clothes they're considering buying (from store, Instagram, website), tries them on their body model mixed with items they own — WITHOUT adding to wardrobe.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S5-01 | Backend: `ShoppingItem` model (temp item, not in wardrobe) — migration | 🔴 | `feature/CE-S5-01-shopping-item-model` |
| CE-S5-02 | Backend: extract garment from shopping photo (store shelf, mannequin, model wearing it) | 🔴 | `feature/CE-S5-02-shopping-photo-extraction` |
| CE-S5-03 | Backend: `POST /shopping/items` — upload & process shopping item | 🔴 | `feature/CE-S5-03-shopping-upload-endpoint` |
| CE-S5-04 | Backend: try-on endpoint supports mixing wardrobe + shopping items | 🔴 | `feature/CE-S5-04-mixed-tryon-endpoint` |
| CE-S5-05 | Mobile: "Try Before You Buy" section in Try-On tab | 🔴 | `feature/CE-S5-05-shopping-tryon-ui` |
| CE-S5-06 | Mobile: upload shopping item photo (camera or gallery) | 🔴 | `feature/CE-S5-06-shopping-photo-upload` |
| CE-S5-07 | Mobile: shopping item staging area ("Considering" shelf) | 🔴 | `feature/CE-S5-07-shopping-staging-shelf` |
| CE-S5-08 | Mobile: try-on with shopping items mixed with wardrobe items | 🔴 | `feature/CE-S5-08-mixed-tryon-ui` |
| CE-S5-09 | Mobile: "Add to Wardrobe" button after deciding to buy | 🟡 | `feature/CE-S5-09-move-to-wardrobe` |
| CE-S5-10 | Mobile: dismiss / clear shopping item | 🟡 | `feature/CE-S5-10-clear-shopping-item` |
| CE-S5-11 | Backend: auto-expire shopping items after 30 days | 🟢 | `feature/CE-S5-11-shopping-item-expiry` |

---

## Sprint 6 — AI Outfit Engine
> **Goal:** AI suggests outfits, scores compatibility, and tells you what to buy to unlock more looks.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S6-01 | Backend: outfit compatibility scoring (OpenAI Vision) | 🔴 | `feature/CE-S6-01-compatibility-scoring` |
| CE-S6-02 | Backend: `POST /suggestions` — top 5 outfit suggestions from wardrobe | 🔴 | `feature/CE-S6-02-suggestion-engine` |
| CE-S6-03 | Backend: occasion-based filtering (work, casual, date night, formal) | 🟡 | `feature/CE-S6-03-occasion-filter` |
| CE-S6-04 | Backend: season-aware suggestions | 🟡 | `feature/CE-S6-04-season-aware` |
| CE-S6-05 | Backend: Style DNA — identify user's style profile from wardrobe | 🟢 | `feature/CE-S6-05-style-dna` |
| CE-S6-06 | Backend: Capsule Score — count unique outfits possible from wardrobe | 🟢 | `feature/CE-S6-06-capsule-score` |
| CE-S6-07 | Backend: Cost Per Wear tracking (if user adds item price) | 🟢 | `feature/CE-S6-07-cost-per-wear` |
| CE-S6-08 | Backend: wardrobe gap analysis (what to buy to unlock more combos) | 🔴 | `feature/CE-S6-08-gap-analysis` |
| CE-S6-09 | Backend: shopping suggestions with color balance reasoning | 🟡 | `feature/CE-S6-09-shopping-suggestions` |
| CE-S6-10 | Mobile: outfit suggestion feed (swipeable cards) | 🔴 | `feature/CE-S6-10-suggestion-feed` |
| CE-S6-11 | Mobile: outfit card — items side by side + match score | 🔴 | `feature/CE-S6-11-outfit-card` |
| CE-S6-12 | Mobile: save outfit to favourites | 🔴 | `feature/CE-S6-12-save-outfit` |
| CE-S6-13 | Mobile: "What should I wear today?" daily suggestion | 🟡 | `feature/CE-S6-13-daily-suggestion` |
| CE-S6-14 | Mobile: Style DNA screen ("Your style is 70% minimalist") | 🟢 | `feature/CE-S6-14-style-dna-screen` |
| CE-S6-15 | Mobile: Capsule Score widget on home/wardrobe screen | 🟢 | `feature/CE-S6-15-capsule-score-widget` |
| CE-S6-16 | Mobile: Cost Per Wear display on item detail screen | 🟢 | `feature/CE-S6-16-cost-per-wear-ui` |
| CE-S6-17 | Mobile: shopping suggestions screen with "why this?" explanation | 🟡 | `feature/CE-S6-17-shopping-suggestions-ui` |

---

## Sprint 7 — Habit & Engagement Loop
> **Goal:** Features that bring users back every day and make the app sticky.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S7-01 | Backend: OOTD (Outfit of the Day) log endpoint | 🔴 | `feature/CE-S7-01-ootd-log-endpoint` |
| CE-S7-02 | Mobile: OOTD screen — "What are you wearing today?" | 🔴 | `feature/CE-S7-02-ootd-screen` |
| CE-S7-03 | Mobile: one-tap OOTD logging from suggestion | 🟡 | `feature/CE-S7-03-ootd-quick-log` |
| CE-S7-04 | Mobile: OOTD history calendar (see what you wore each day) | 🟡 | `feature/CE-S7-04-ootd-history` |
| CE-S7-05 | Backend: push notification service (Expo Notifications) | 🔴 | `feature/CE-S7-05-push-notifications` |
| CE-S7-06 | Mobile: daily OOTD reminder notification (user sets time) | 🟡 | `feature/CE-S7-06-daily-reminder` |
| CE-S7-07 | Mobile: "You haven't worn this in 30 days" nudge notification | 🟢 | `feature/CE-S7-07-unworn-nudge` |
| CE-S7-08 | Mobile: streak counter (how many days in a row logged OOTD) | 🟢 | `feature/CE-S7-08-streak-counter` |

---

## Sprint 8 — UI Polish & Design System
> **Goal:** White + burgundy design system applied consistently. App feels premium.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S8-01 | Define design tokens (colors, typography, spacing, radius) | 🔴 | `feature/CE-S8-01-design-tokens` |
| CE-S8-02 | Build component library (Button, Card, Input, Tag, Avatar, Badge) | 🔴 | `feature/CE-S8-02-component-library` |
| CE-S8-03 | Apply design system to Auth screens | 🔴 | `feature/CE-S8-03-polish-auth` |
| CE-S8-04 | Apply design system to Wardrobe screens | 🔴 | `feature/CE-S8-04-polish-wardrobe` |
| CE-S8-05 | Apply design system to Try-On screens | 🔴 | `feature/CE-S8-05-polish-tryon` |
| CE-S8-06 | Apply design system to Outfit / Suggestion screens | 🔴 | `feature/CE-S8-06-polish-outfits` |
| CE-S8-07 | Custom tab bar icons (SVG, burgundy active state) | 🟡 | `feature/CE-S8-07-tab-icons` |
| CE-S8-08 | Micro-animations (item upload, swipe cards, loading) | 🟡 | `feature/CE-S8-08-animations` |
| CE-S8-09 | App icon + splash screen (white/burgundy branding) | 🔴 | `feature/CE-S8-09-app-icon-splash` |
| CE-S8-10 | Haptic feedback on key interactions | 🟢 | `feature/CE-S8-10-haptics` |

---

## Sprint 9 — App Store Launch
> **Goal:** Both stores approved, first users in.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| CE-S9-01 | Privacy policy (required by Apple + Google) | 🔴 | `feature/CE-S9-01-privacy-policy` |
| CE-S9-02 | Terms of service | 🔴 | `feature/CE-S9-02-terms-of-service` |
| CE-S9-03 | App Store screenshots (6.7", 6.1", iPad) | 🔴 | `feature/CE-S9-03-ios-screenshots` |
| CE-S9-04 | Google Play screenshots + feature graphic | 🔴 | `feature/CE-S9-04-android-screenshots` |
| CE-S9-05 | Crash reporting — Sentry integration | 🟡 | `feature/CE-S9-05-sentry` |
| CE-S9-06 | Analytics — track key events (upload, tryon, suggestion, OOTD) | 🟡 | `feature/CE-S9-06-analytics` |
| CE-S9-07 | EAS Build setup (CI/CD for iOS + Android builds) | 🔴 | `feature/CE-S9-07-eas-build` |
| CE-S9-08 | Backend: deploy to production (Railway / Render) | 🔴 | `feature/CE-S9-08-production-deploy` |
| CE-S9-09 | Backend: production secrets + env config | 🔴 | `feature/CE-S9-09-production-env` |
| CE-S9-10 | TestFlight beta release (iOS) | 🔴 | `feature/CE-S9-10-testflight` |
| CE-S9-11 | Google Play internal testing | 🔴 | `feature/CE-S9-11-play-testing` |
| CE-S9-12 | App Store submission | 🔴 | `feature/CE-S9-12-app-store-submit` |
| CE-S9-13 | Google Play submission | 🔴 | `feature/CE-S9-13-play-store-submit` |

---

## 📊 Summary

| Sprint | Focus | Tasks | Est. Duration |
|--------|-------|-------|---------------|
| S0 | Setup | 7 | ✅ Done |
| S1 | Auth (Phone OTP) | 13 | ✅ Done |
| S2 | Body Model Creation | 9 | 1.5 weeks |
| S3 | Wardrobe Core (Smart Upload) | 15 | 2 weeks |
| S4 | Virtual Try-On (Wardrobe) | 10 | 2 weeks |
| S5 | Shopping Try-On (Try Before Buy) | 11 | 1.5 weeks |
| S6 | AI Outfit Engine | 17 | 2 weeks |
| S7 | Habit & Engagement Loop | 8 | 1 week |
| S8 | UI Polish & Design System | 10 | 1.5 weeks |
| S9 | App Store Launch | 13 | 1 week |
| **Total** | | **112 tasks** | **~14 weeks** |

---

## 🚀 What Makes Drape the Trending App of the Year

| Feature | Why It's Viral |
|---------|---------------|
| Body model from YOUR photo | Personal, not generic — people will share results |
| Try Before You Buy | Saves money — massive word of mouth |
| Capsule Score | Gamification — people compete and share |
| Cost Per Wear | Data people love — "my jacket costs me $2/wear" |
| OOTD streak | Daily habit loop like Duolingo |
| Style DNA | Identity feature — people share their style profile |
