# Launch Tonight: What Nil Does (in order)

The code is ready on branch `DR-S9-launch`. These steps need your accounts, so only you can do them.
Times are rough estimates.

> **Honest timing:** you can *submit* to both stores tonight. You can't make them *live* tonight.
> Apple review usually takes about 24–48 h. Google's first review for a new app can take a few days.
> First-time Play developer accounts also have to run a closed test (12 testers for 14 days) before production.

---

## 1. Rotate the leaked Firebase key (5 min, do this first)

The file `backend/closeteye-c2c03-firebase-adminsdk-fbsvc-9f00efc22b.json` is a **private key** that
lets anyone act as an admin on your Firebase project. It was pushed to GitHub, so treat it as public.

1. Open https://console.firebase.google.com → project **closeteye-c2c03** → ⚙️ **Project settings** → **Service accounts**.
2. Click **Generate new private key** → save the file as `backend/secrets/firebase-admin.json` (that folder is gitignored).
3. Click **Manage service account permissions** (opens Google Cloud) → the `firebase-adminsdk-fbsvc` account → **Keys** tab →
   delete the key whose ID starts with **`9f00efc2`**.
4. In `backend/.env` change the line to `FIREBASE_SERVICE_ACCOUNT_PATH=/app/secrets/firebase-admin.json`.
5. Tell Claude "key rotated". Claude will then untrack the old file. Once the key is deleted the old copy in git history is useless, so no history rewrite is needed.

## 2. Put the API online (20 min) on Railway

The phone app can't reach the server on your laptop, and Apple tests the app from their office. The API has to be on the internet.

1. https://railway.com → sign in with GitHub → **New Project → Deploy from GitHub repo** → `ClosetEye`.
   - Settings → **Root directory**: `backend`. Branch: `DR-S9-launch` (or `main` after merging).
2. In the project: **+ New → Database → PostgreSQL**.
3. Backend service → **Settings → Volumes → Add volume**, mount path `/app/uploads` (photos live here).
4. Backend service → **Variables**:
   | Name | Value |
   |---|---|
   | `ENV` | `prod` |
   | `DATABASE_URL` | Copy Postgres's `DATABASE_URL` and change `postgresql://` to **`postgresql+asyncpg://`** |
   | `SECRET_KEY` | run `python3 -c "import secrets;print(secrets.token_urlsafe(48))"` and paste |
   | `FIREBASE_SERVICE_ACCOUNT_JSON` | the **new** key file contents (whole JSON) |
   | `OPENAI_API_KEY` | your key (also set a monthly limit at platform.openai.com → Limits) |
   | `DAILY_AI_BUDGET_USD` | `15` (paid AI pauses for the day after about $15) |
   | `SUPPORT_EMAIL` | the support inbox you want on the legal pages |
   | `BASE_URL` | set after step 5 |
5. **Settings → Networking → Generate domain** (e.g. `drape-api.up.railway.app`). Put `https://<that domain>` in `BASE_URL`. Redeploy.
6. Check `https://<domain>/health` shows `{"status":"ok"}` and `https://<domain>/legal/privacy` loads.
7. Use a plan with **at least 2 GB RAM** (background removal needs it). Railway is pay-as-you-go (about $5–20 per month at launch).

Migrations run automatically on every deploy.

## 3. Reviewer login (5 min)

Apple and Google reviewers can't receive SMS codes on your number.
Firebase console → **Authentication → Sign-in method → Phone → Phone numbers for testing** →
add `+1 650-555-0142` with code `246810`. Put both in the store review notes (see section 6).

## 4. Build and upload (30 min)

```bash
cd mobile/ClosetEyeFlutter
SERVER_URL=https://<your-railway-domain> ./scripts/build_release.sh both
```
- **iOS:** needs an Apple Developer account ($99/yr). Open `ios/Runner.xcworkspace` in Xcode once, pick your Team under
  Signing & Capabilities, then rerun the script. Upload `build/ios/ipa/*.ipa` with the **Transporter** app.
  In App Store Connect create the app (bundle id `com.closeteye.closeteye`, name **Drape**).
- **Android:** needs a Play Console account ($25 one time). Create the app, enable **Play App Signing**, upload
  `build/app/outputs/bundle/release/app-release.aab` to **Internal testing** first.
  A signed test bundle already builds. Optional: Android Studio → Settings → Android SDK → SDK Tools →
  tick **Android SDK Command-line Tools** so Flutter can strip debug symbols (smaller download).
- **BACK UP** `android/app/upload-keystore.jks` and `android/key.properties` (password manager or a private drive).
  They're gitignored on purpose. Without them you can't ship Android updates without contacting Google.
- New personal Play accounts must run a **closed test with 12+ testers for 14 days** before production.
  Start the closed test tonight with your GSU testers; that clock is the real Android launch date.

## 5. Store listing text (copy and paste)

**Name:** Drape: AI Closet & Outfits
**Subtitle (iOS, 30 chars):** Your closet, styled by AI
**Promo / short description:** Snap your clothes, get outfits for today's weather, and see what to buy next. Free.

**Description:**
Drape turns your closet into outfits.

Snap a photo of any piece of clothing, on a hanger, on your bed or on you, and Drape cleans it up and
tags it for you. Then it puts together outfits from what you already own, matched to today's weather and your plans.

• Today's picks: three fresh outfits every day, picked for the weather
• Build around a piece: pick the item you want to wear and get looks that work with it
• Mix and match: try combos and see an instant outfit score
• Learns your taste: like, skip, or "never pair these" and suggestions get better
• Wear log and streaks: see what you wore and when
• Cost per wear: see which pieces earn their price
• Try before you buy: see how something new works with what you already own
• Virtual try on (beta): see an outfit on you

Free. No ads. Your photos stay private.

**Keywords (iOS):** closet,wardrobe,outfit,style,fashion,stylist,ootd,clothes,outfit planner,capsule
**Category:** Lifestyle (secondary: Shopping)
**Privacy policy URL:** `https://<domain>/legal/privacy`
**Support URL:** `https://<domain>/support`
**Account deletion URL (Google Play):** `https://<domain>/legal/delete-account`
**Age rating:** 4+ / Everyone (no user-to-user content, no ads)

## 6. Review notes (paste into both stores)

> Sign in with test phone number +1 650-555-0142 and code 246810.
> To try the app: tap + to add a clothing photo (any photo of a shirt/pants/shoes works), add 2 or 3 items,
> then open "Today's Outfit Picks" on Home. Account deletion: Profile → Delete Account.
> Virtual try on needs a full-body photo (Profile → Body model) and is limited to 3 per day.

## 7. Privacy forms

**Apple "App Privacy":** Data linked to the user, not used for tracking:
- Contact Info → **Phone Number** (App Functionality)
- User Content → **Photos** (App Functionality)
- Other Data → **Other Data Types**: body photo and height/weight/body type (optional, App Functionality)
- Identifiers → **User ID** (App Functionality)
- Usage Data → **Product Interaction** (App Functionality)
- Location → **Coarse Location** (App Functionality, **not** linked to identity). It's only used for weather and never stored, but declaring it is the safe choice.

**Google Play "Data safety":** Collected: Phone number, Photos, App interactions, Other user-generated content
(closet data), Approximate location (not stored, processed ephemerally). Encrypted in transit: Yes.
Users can request deletion: Yes (in app + URL). Shared with third parties: No (OpenAI and Firebase are service providers).

## 8. After it's live

Tell Claude and the next steps from `docs/LAUNCH-SPRINT-PLAN.md` continue: push notifications, batch upload,
insights, a commercial try-on provider, Firebase Storage, Crashlytics.
