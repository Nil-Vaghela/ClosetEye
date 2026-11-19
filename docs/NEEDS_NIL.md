# Needs Nil

Things only Nil can do (accounts, money, keys). Step-by-step instructions are in `docs/LAUNCH-TONIGHT.md`.

| # | Item | Status |
|---|---|---|
| 1 | Rotate the leaked Firebase Admin key `9f00efc2…` (see LAUNCH-TONIGHT §1). After that Claude untracks the old file. | **Open, urgent** |
| 2 | Railway account + deploy (LAUNCH-TONIGHT §2) | Open |
| 3 | Apple Developer ($99/yr) + Google Play Console ($25) accounts | Open |
| 4 | Firebase test phone number for reviewers (LAUNCH-TONIGHT §3) | Open |
| 5 | Support email inbox (goes on the legal pages via `SUPPORT_EMAIL`) | Open |
| 6 | OpenAI monthly spend limit on platform.openai.com (backup to the in-app $15/day kill switch) | Open |
| 7 | Back up `android/app/upload-keystore.jks` + `android/key.properties` | Open |
| 8 | Legal review of `/legal/privacy` and `/legal/terms` wording | Open (fine to launch, review soon) |
| 9 | Beta testers: 12+ for the Play closed test, 30–50 overall | Open |
| 10 | Domain name (optional; the Railway domain works for launch) | Later |

## Decided (co-founder calls, change any time)

| Decision | Why |
|---|---|
| Keep app id `com.closeteye.closeteye` | Firebase apps are registered with it; users only see "Drape". |
| Host on Railway (API + Postgres + volume) for launch | Fastest path tonight; Cloud Run + Firebase Storage later. |
| Try on uses OpenAI gpt-image-1 (commercial use allowed), 3 per day; IDM-VTON off | IDM-VTON is non-commercial (CC BY-NC-SA). |
| Daily AI budget $15 (`DAILY_AI_BUDGET_USD`) | Free app; paid features pause for the day, free ones keep working. |
| "For you" suggestions use the free in-house engine, not GPT-4o | Zero cost and consistent with Today's Picks. |
| Scanned items use real cutouts, not AI re-renders | Shows the user's actual garment, costs nothing. |
| New app icon: gold hanger on warm ivory | Replaces the default Flutter icon (Apple rejects placeholders). |
