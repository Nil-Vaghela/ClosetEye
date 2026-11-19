"""
Public legal pages required by the App Store and Google Play:
privacy policy, terms of use, account deletion instructions, support.
Plain server-rendered HTML so they work at any URL the stores link to.
NEEDS_NIL: legal review of this wording before launch.
"""
from html import escape

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.core.config import settings

router = APIRouter()

_UPDATED = "November 19, 2026"

_CSS = """
:root{--bg:#FBF8F3;--fg:#2B2622;--muted:#7A6F66;--accent:#B08D57;--card:#FFFFFF;--line:#EAE2D6}
@media (prefers-color-scheme:dark){:root{--bg:#171513;--fg:#EFE9E1;--muted:#A89D92;--card:#211E1B;--line:#36302A}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);
font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:40px 16px 80px}
h1{font-size:30px;margin:0 0 4px}h2{font-size:19px;margin:32px 0 8px}
.meta{color:var(--muted);font-size:14px;margin-bottom:24px}
a{color:var(--accent)}li{margin:4px 0}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px 20px;margin:16px 0}
nav{display:flex;gap:16px;flex-wrap:wrap;font-size:14px;margin-bottom:28px}
"""


def _page(title: str, body: str) -> HTMLResponse:
    nav = ('<nav><a href="/legal/privacy">Privacy</a><a href="/legal/terms">Terms</a>'
           '<a href="/legal/delete-account">Delete your account</a><a href="/support">Support</a></nav>')
    html = (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{escape(title)} · Drape</title><style>{_CSS}</style></head>'
            f'<body><main>{nav}<h1>{escape(title)}</h1><div class="meta">Drape · Last updated {_UPDATED}</div>'
            f'{body}</main></body></html>')
    return HTMLResponse(html, headers={"Cache-Control": "public, max-age=3600"})


def _email() -> str:
    e = escape(settings.SUPPORT_EMAIL)
    return f'<a href="mailto:{e}">{e}</a>'


@router.get("/legal/privacy", response_class=HTMLResponse, include_in_schema=False)
async def privacy():
    return _page("Privacy Policy", f"""
<p>Drape is a free digital wardrobe. This policy explains what we collect, why, and the choices you have.
Short version: we use your data to run the app for you. We don't sell it and we don't show ads.</p>

<h2>What we collect</h2>
<ul>
<li><b>Phone number.</b> Used to sign you in with a one-time code (handled by Google Firebase Authentication).</li>
<li><b>Your name</b> if you add one.</li>
<li><b>Photos of your clothes</b> you upload, and the cleaned up images we make from them.</li>
<li><b>A full body photo and your height, weight and body type</b>, only if you set up virtual try on. This is optional.</li>
<li><b>What you do in your closet</b>: items, saved outfits, what you wore, likes and dislikes. This powers your suggestions.</li>
<li><b>Approximate location</b>, only if you allow it, to look up today's weather. We round it to about 1 km,
send it to our weather provider for that request, and don't store it.</li>
<li><b>Basic technical data</b> such as your time zone offset and error logs needed to keep the service working.</li>
</ul>

<h2>How photos are processed</h2>
<p>Clothing photos are processed on our own servers to remove backgrounds and detect colors and categories.
Some features send images to <b>OpenAI</b> to work: detecting the details of clothing, virtual try on images,
and outfit boards. OpenAI processes them on our behalf under its API terms, which do not allow using API data
to train its models. Your photos are never public. Every image link the app uses is private and expires.
We remove location and other metadata from photos when you upload them.</p>

<h2>What we don't do</h2>
<ul><li>We don't sell or rent your personal data.</li><li>We don't use your photos for advertising.</li>
<li>We don't share your body photo with anyone except to create the try on image you asked for.</li></ul>

<h2>Service providers</h2>
<p>Google Firebase (sign in), OpenAI (image understanding and generation), Open-Meteo (weather, receives rounded
coordinates only), and our cloud hosting and database providers. They only process data to provide their service to us.</p>

<h2>How long we keep data</h2>
<p>We keep your data while you have an account. Items in "Try before you buy" expire after 30 days.
When you delete your account we delete your profile, closet, outfits, history and every photo right away,
and remove backups within 30 days.</p>

<h2>Your choices and rights</h2>
<ul>
<li>Delete any item or your body photo any time in the app.</li>
<li>Delete your whole account in the app: <b>Profile → Delete account</b>. See <a href="/legal/delete-account">how</a>.</li>
<li>Ask us for a copy of your data or to correct it: {_email()}.</li>
<li>Turn location off any time in your phone's settings. The app works without it.</li>
</ul>

<h2>Children</h2>
<p>Drape is not meant for children under 13 and we don't knowingly collect their data.</p>

<h2>Changes</h2>
<p>If we change this policy in a meaningful way we'll tell you in the app first.</p>

<h2>Contact</h2><p>{_email()}</p>
""")


@router.get("/legal/terms", response_class=HTMLResponse, include_in_schema=False)
async def terms():
    return _page("Terms of Use", f"""
<p>Welcome to Drape. By using the app you agree to these terms.</p>
<h2>The service</h2>
<p>Drape helps you organize your clothes and suggests outfits. It's free. Some AI features have daily limits so
we can keep it free for everyone. Features can change as we improve the app.</p>
<h2>Your account</h2>
<p>You sign in with your phone number. Keep access to your phone secure. You must be at least 13 years old.</p>
<h2>Your content</h2>
<p>You own the photos you upload. You give us permission to store and process them only to run Drape for you,
including sending them to our AI providers for the features you use. Only upload photos you have the right to use,
and don't upload photos of other people without their permission.</p>
<h2>AI results</h2>
<p>Outfit suggestions, detected details and virtual try on images are generated automatically and can be wrong.
Try on images are a preview, not a promise of fit.</p>
<h2>Fair use</h2>
<p>Don't misuse the service: no attempts to access other people's data, overload our systems, or reverse engineer
the app. We may suspend accounts that do.</p>
<h2>Shopping links</h2>
<p>If Drape shows products or stores, those are third parties with their own terms.</p>
<h2>Disclaimers</h2>
<p>Drape is provided "as is". To the extent the law allows, we aren't liable for indirect or incidental damages.</p>
<h2>Ending</h2>
<p>You can delete your account any time in the app. We may end the service with notice in the app.</p>
<h2>Contact</h2><p>{_email()}</p>
""")


@router.get("/legal/delete-account", response_class=HTMLResponse, include_in_schema=False)
async def delete_account_info():
    return _page("Delete your Drape account", f"""
<div class="card"><b>In the app:</b> open <b>Profile</b>, tap <b>Delete account</b>, and confirm.</div>
<p>This permanently deletes your profile, phone sign in, closet items, outfits, history, body photo and every photo
you uploaded. It happens right away and can't be undone. Backups are cleared within 30 days.</p>
<p>Can't open the app? Email {_email()} from anywhere with the phone number on your account and we'll delete it
within 7 days.</p>
""")


@router.get("/support", response_class=HTMLResponse, include_in_schema=False)
async def support():
    return _page("Support", f"""
<p>Questions, bugs or ideas? We'd love to hear from you.</p>
<div class="card">Email {_email()}<br>We usually reply within a day.</div>
<h2>Quick answers</h2>
<ul>
<li><b>My photo didn't clean up well.</b> Lay the item flat in good light, or take it on a hanger against a plain wall.</li>
<li><b>I hit a daily limit.</b> Some AI features have daily limits so Drape can stay free. They reset every day.</li>
<li><b>How do I delete my data?</b> See <a href="/legal/delete-account">Delete your account</a>.</li>
</ul>
""")
