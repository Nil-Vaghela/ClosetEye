# Drape — Product Scrum Board
### *"Your closet, reimagined by AI"*

**Theme:** Warm sand + champagne gold — light, airy, premium
**Platform:** iOS & Android mobile app
**Backend:** FastAPI + PostgreSQL (Docker Compose), private API
**Auth:** Firebase Phone Auth (OTP) — iOS & Android
**Goal:** #1 trending fashion app of the year

> Branch naming: `feature/DR-S{sprint}-{id}-short-description`
> Example: `feature/DR-S2-01-body-model-onboarding`
> (Sprint 0–1 used legacy `CE-` prefix, Sprint 2+ uses `DR-` for Drape)

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
| CE-S0-05 | Flutter app skeleton (replaced React Native/Expo decision) | ✅ |
| CE-S0-06 | 4-tab navigation shell (Home, Wardrobe, Outfits, Profile) | ✅ |
| CE-S0-07 | API client (Dio + auth interceptor) | ✅ |

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

## Sprint 2 — ✅ COMPLETE — Body Model Creation
> **Goal:** User creates their personal body model used for all try-ons. This is the foundation of the try-on experience — a realistic silhouette, not a generic mannequin.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S2-01 | Mobile: body model onboarding screen ("Let's build your model") ✅| 🔴 | `feature/DR-S2-01-body-model-onboarding` |
| DR-S2-02 | Mobile: collect body measurements (height, weight, body type) ✅| 🔴 | `feature/DR-S2-02-body-measurements-form` |
| DR-S2-03 | Mobile: front-facing reference photo capture for body model ✅| 🔴 | `feature/DR-S2-03-body-photo-capture` |
| DR-S2-04 | Backend: generate body silhouette from reference photo + measurements ✅| 🔴 | `feature/DR-S2-04-body-silhouette-generation` |
| DR-S2-05 | Backend: store body model (measurements + processed image) ✅| 🔴 | `feature/DR-S2-05-body-model-storage` |
| DR-S2-06 | Backend: `POST /users/me/body-model` endpoint ✅| 🔴 | `feature/DR-S2-06-body-model-endpoint` |
| DR-S2-07 | Mobile: body model preview screen (show generated silhouette) ✅| 🟡 | `feature/DR-S2-07-body-model-preview` |
| DR-S2-08 | Mobile: update body model later (from profile settings) ✅| 🟡 | `feature/DR-S2-08-update-body-model` |
| DR-S2-09 | Backend: add body model fields to User model (migration) ✅| 🔴 | `feature/DR-S2-09-user-model-migration` |

---

## Sprint 3 — ✅ COMPLETE — Wardrobe Core (Smart Upload)
> **Goal:** User photographs clothes in ANY way — wearing them, on a bed, hanging up — AI extracts the garment cleanly and adds it to the wardrobe.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S3-01 | Backend: file upload service (local storage / S3) ✅| 🔴 | `feature/DR-S3-01-file-upload-service` |
| DR-S3-02 | Backend: detect photo type — is person wearing it, or flat lay? ✅| 🔴 | `feature/DR-S3-02-photo-type-detection` |
| DR-S3-03 | Backend: extract garment from flat-lay / hanger photo (background removal) ✅| 🔴 | `feature/DR-S3-03-flatlay-extraction` |
| DR-S3-04 | Backend: extract garment from photo of person wearing it (person + cloth segmentation) ✅| 🔴 | `feature/DR-S3-04-worn-photo-extraction` |
| DR-S3-05 | Backend: dewrinkle + clean up extracted garment image ✅| 🟡 | `feature/DR-S3-05-dewrinkle-pipeline` |
| DR-S3-06 | Backend: AI attribute detection — color, category, pattern, fabric via OpenAI Vision ✅| 🔴 | `feature/DR-S3-06-attribute-detection` |
| DR-S3-07 | Backend: auto-fill ClothingItem fields from AI response ✅| 🔴 | `feature/DR-S3-07-auto-fill-item` |
| DR-S3-08 | Mobile: camera screen — take photo (any style) ✅| 🔴 | `feature/DR-S3-08-camera-capture` |
| DR-S3-09 | Mobile: gallery picker — choose from photos ✅| 🔴 | `feature/DR-S3-09-gallery-picker` |
| DR-S3-10 | Mobile: AI processing loader ("Extracting your item...") ✅| 🟡 | `feature/DR-S3-10-processing-loader` |
| DR-S3-11 | Mobile: item review screen — confirm / edit AI-detected fields ✅| 🔴 | `feature/DR-S3-11-item-review-screen` |
| DR-S3-12 | Mobile: wardrobe grid screen (masonry layout, warm sand + gold palette) ✅| 🔴 | `feature/DR-S3-12-wardrobe-grid` |
| DR-S3-13 | Mobile: filter wardrobe by category ✅| 🟡 | `feature/DR-S3-13-wardrobe-filters` |
| DR-S3-14 | Mobile: delete item (swipe or long-press) ✅| 🟡 | `feature/DR-S3-14-delete-item` |
| DR-S3-15 | Mobile: empty state ("Add your first item") ✅| 🟢 | `feature/DR-S3-15-empty-state` |

---

## Sprint 4 — ✅ COMPLETE — Virtual Try-On (Wardrobe Items)
> **Goal:** User selects items from their wardrobe, sees them on their personal body model instantly.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S4-01 | Backend: pose estimation on body model image ✅| 🔴 | `feature/DR-S4-01-pose-estimation` |
| DR-S4-02 | Backend: garment warping — fit clothing to body shape ✅| 🔴 | `feature/DR-S4-02-garment-warping` |
| DR-S4-03 | Backend: composite — layer multiple garments on body model ✅| 🔴 | `feature/DR-S4-03-garment-composite` |
| DR-S4-04 | Backend: `POST /tryon` endpoint — accepts item IDs, returns preview URL ✅| 🔴 | `feature/DR-S4-04-tryon-endpoint` |
| DR-S4-05 | Mobile: try-on screen — select items from wardrobe ✅| 🔴 | `feature/DR-S4-05-tryon-item-selector` |
| DR-S4-06 | Mobile: try-on result — view on your body model ✅| 🔴 | `feature/DR-S4-06-tryon-result-screen` |
| DR-S4-07 | Mobile: swap individual items in the try-on view ✅| 🟡 | `feature/DR-S4-07-swap-items-tryon` |
| DR-S4-08 | Mobile: save try-on look as an outfit ✅| 🔴 | `feature/DR-S4-08-save-tryon-as-outfit` |
| DR-S4-09 | Mobile: save try-on image to camera roll ✅| 🟡 | `feature/DR-S4-09-save-to-camera-roll` |
| DR-S4-10 | Mobile: loading animation during AI processing ✅| 🟡 | `feature/DR-S4-10-tryon-loading` |

---

## Sprint 5 — ✅ COMPLETE — Shopping Try-On (Try Before You Buy)
> **Goal:** User uploads a photo of clothes they're considering buying (from store, Instagram, website), tries them on their body model mixed with items they own — WITHOUT adding to wardrobe.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S5-01 | Backend: `ShoppingItem` model (temp item, not in wardrobe) — migration ✅| 🔴 | `feature/DR-S5-01-shopping-item-model` |
| DR-S5-02 | Backend: extract garment from shopping photo (store shelf, mannequin, model wearing it) ✅| 🔴 | `feature/DR-S5-02-shopping-photo-extraction` |
| DR-S5-03 | Backend: `POST /shopping/items` — upload & process shopping item ✅| 🔴 | `feature/DR-S5-03-shopping-upload-endpoint` |
| DR-S5-04 | Backend: try-on endpoint supports mixing wardrobe + shopping items ✅| 🔴 | `feature/DR-S5-04-mixed-tryon-endpoint` |
| DR-S5-05 | Mobile: "Try Before You Buy" section in Try-On tab ✅| 🔴 | `feature/DR-S5-05-shopping-tryon-ui` |
| DR-S5-06 | Mobile: upload shopping item photo (camera or gallery) ✅| 🔴 | `feature/DR-S5-06-shopping-photo-upload` |
| DR-S5-07 | Mobile: shopping item staging area ("Considering" shelf) ✅| 🔴 | `feature/DR-S5-07-shopping-staging-shelf` |
| DR-S5-08 | Mobile: try-on with shopping items mixed with wardrobe items ✅| 🔴 | `feature/DR-S5-08-mixed-tryon-ui` |
| DR-S5-09 | Mobile: "Add to Wardrobe" button after deciding to buy ✅| 🟡 | `feature/DR-S5-09-move-to-wardrobe` |
| DR-S5-10 | Mobile: dismiss / clear shopping item ✅| 🟡 | `feature/DR-S5-10-clear-shopping-item` |
| DR-S5-11 | Backend: auto-expire shopping items after 30 days ✅| 🟢 | `feature/DR-S5-11-shopping-item-expiry` |

---

## Sprint 6 — ✅ COMPLETE — AI Outfit Engine
> **Goal:** AI suggests outfits, scores compatibility, and tells you what to buy to unlock more looks.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S6-01 | Backend: outfit compatibility scoring (OpenAI Vision) ✅| 🔴 | `feature/DR-S6-01-compatibility-scoring` |
| DR-S6-02 | Backend: `POST /suggestions` — top 5 outfit suggestions from wardrobe ✅| 🔴 | `feature/DR-S6-02-suggestion-engine` |
| DR-S6-03 | Backend: occasion-based filtering (work, casual, date night, formal) ✅| 🟡 | `feature/DR-S6-03-occasion-filter` |
| DR-S6-04 | Backend: season-aware suggestions ✅| 🟡 | `feature/DR-S6-04-season-aware` |
| DR-S6-05 | Backend: Style DNA — identify user's style profile from wardrobe ✅| 🟢 | `feature/DR-S6-05-style-dna` |
| DR-S6-06 | Backend: Capsule Score — count unique outfits possible from wardrobe ✅| 🟢 | `feature/DR-S6-06-capsule-score` |
| DR-S6-07 | Backend: Cost Per Wear tracking (if user adds item price) ✅| 🟢 | `feature/DR-S6-07-cost-per-wear` |
| DR-S6-08 | Backend: wardrobe gap analysis (what to buy to unlock more combos) ✅| 🔴 | `feature/DR-S6-08-gap-analysis` |
| DR-S6-09 | Backend: shopping suggestions with color balance reasoning ✅| 🟡 | `feature/DR-S6-09-shopping-suggestions` |
| DR-S6-10 | Mobile: outfit suggestion feed (swipeable cards) ✅| 🔴 | `feature/DR-S6-10-suggestion-feed` |
| DR-S6-11 | Mobile: outfit card — items side by side + match score ✅| 🔴 | `feature/DR-S6-11-outfit-card` |
| DR-S6-12 | Mobile: save outfit to favourites ✅| 🔴 | `feature/DR-S6-12-save-outfit` |
| DR-S6-13 | Mobile: "What should I wear today?" daily suggestion ✅| 🟡 | `feature/DR-S6-13-daily-suggestion` |
| DR-S6-14 | Mobile: Style DNA screen ("Your style is 70% minimalist") ✅| 🟢 | `feature/DR-S6-14-style-dna-screen` |
| DR-S6-15 | Mobile: Capsule Score widget on home/wardrobe screen ✅| 🟢 | `feature/DR-S6-15-capsule-score-widget` |
| DR-S6-16 | Mobile: Cost Per Wear display on item detail screen ✅| 🟢 | `feature/DR-S6-16-cost-per-wear-ui` |
| DR-S6-17 | Mobile: shopping suggestions screen with "why this?" explanation ✅| 🟡 | `feature/DR-S6-17-shopping-suggestions-ui` |

---

## Sprint 7 — ✅ COMPLETE — Habit & Engagement Loop
> **Goal:** Features that bring users back every day and make the app sticky.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S7-01 | Backend: OOTD (Outfit of the Day) log endpoint ✅| 🔴 | `feature/DR-S7-01-ootd-log-endpoint` |
| DR-S7-02 | Mobile: OOTD screen — "What are you wearing today?" ✅| 🔴 | `feature/DR-S7-02-ootd-screen` |
| DR-S7-03 | Mobile: one-tap OOTD logging from suggestion ✅| 🟡 | `feature/DR-S7-03-ootd-quick-log` |
| DR-S7-04 | Mobile: OOTD history calendar (see what you wore each day) ✅| 🟡 | `feature/DR-S7-04-ootd-history` |
| DR-S7-05 | Backend: push notification service (Firebase Cloud Messaging + flutter_local_notifications) ✅| 🔴 | `feature/DR-S7-05-push-notifications` |
| DR-S7-06 | Mobile: daily OOTD reminder notification (user sets time) ✅| 🟡 | `feature/DR-S7-06-daily-reminder` |
| DR-S7-07 | Mobile: "You haven't worn this in 30 days" nudge notification ✅| 🟢 | `feature/DR-S7-07-unworn-nudge` |
| DR-S7-08 | Mobile: streak counter (how many days in a row logged OOTD) ✅| 🟢 | `feature/DR-S7-08-streak-counter` |

---

## Sprint 8 — ✅ COMPLETE — UI Polish & Design System
> **Goal:** Warm sand + champagne gold design system (already established in S1) applied consistently across all new screens. App feels luxury and premium throughout.
> **Note:** Core design system (AppColors, AppTheme, GlassCard, GradientButton, BlobBg, floating pill nav) already built in Sprint 1.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S8-01 | Design tokens audit — ensure all screens use AppColors, no hardcoded values ✅| 🔴 | `feature/DR-S8-01-design-tokens-audit` |
| DR-S8-02 | Extend component library (Tag, Badge, Avatar, BottomSheet) ✅| 🔴 | `feature/DR-S8-02-component-library` |
| DR-S8-03 | Polish Try-On screens with Drape design system ✅| 🔴 | `feature/DR-S8-03-polish-tryon` |
| DR-S8-04 | Polish Outfit / Suggestion screens ✅| 🔴 | `feature/DR-S8-04-polish-outfits` |
| DR-S8-05 | Polish Shopping screens ✅| 🔴 | `feature/DR-S8-05-polish-shopping` |
| DR-S8-06 | Custom tab bar icons (SVG, gold active state) ✅| 🟡 | `feature/DR-S8-06-tab-icons` |
| DR-S8-07 | Micro-animations (item upload, swipe cards, loading skeletons) ✅| 🟡 | `feature/DR-S8-07-animations` |
| DR-S8-08 | App icon + splash screen (Drape branding — warm sand + gold) ✅| 🔴 | `feature/DR-S8-08-app-icon-splash` |
| DR-S8-09 | Haptic feedback on key interactions ✅| 🟢 | `feature/DR-S8-09-haptics` |

---

## Sprint 9 — App Store Launch
> **Goal:** Both stores approved, first users in.

| Story ID | Task | Priority | Branch |
|----------|------|----------|--------|
| DR-S9-01 | Privacy policy (required by Apple + Google) | 🔴 | `feature/DR-S9-01-privacy-policy` |
| DR-S9-02 | Terms of service | 🔴 | `feature/DR-S9-02-terms-of-service` |
| DR-S9-03 | App Store screenshots (6.7", 6.1", iPad) | 🔴 | `feature/DR-S9-03-ios-screenshots` |
| DR-S9-04 | Google Play screenshots + feature graphic | 🔴 | `feature/DR-S9-04-android-screenshots` |
| DR-S9-05 | Crash reporting — Sentry integration | 🟡 | `feature/DR-S9-05-sentry` |
| DR-S9-06 | Analytics — track key events (upload, tryon, suggestion, OOTD) | 🟡 | `feature/DR-S9-06-analytics` |
| DR-S9-07 | Flutter build setup — Fastlane or GitHub Actions CI/CD (iOS + Android) | 🔴 | `feature/DR-S9-07-flutter-cicd` |
| DR-S9-08 | Backend: deploy to production (Railway / Render) | 🔴 | `feature/DR-S9-08-production-deploy` |
| DR-S9-09 | Backend: production secrets + env config | 🔴 | `feature/DR-S9-09-production-env` |
| DR-S9-10 | TestFlight beta release (iOS) | 🔴 | `feature/DR-S9-10-testflight` |
| DR-S9-11 | Google Play internal testing | 🔴 | `feature/DR-S9-11-play-testing` |
| DR-S9-12 | App Store submission | 🔴 | `feature/DR-S9-12-app-store-submit` |
| DR-S9-13 | Google Play submission | 🔴 | `feature/DR-S9-13-play-store-submit` |

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
