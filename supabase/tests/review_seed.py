#!/usr/bin/env python3
"""Trvalý demo účet pro App Review (#18) v produkci. NEMAZAT, žádný úklid.

  supabase projects api-keys --project-ref tlespfcbqzddddhjsieu -o json > <scratch>/keys.json
  python3 -I supabase/tests/review_seed.py <scratch>/keys.json ~/.bedrival/review_state.json            # založení
  supabase db query --remote --yes "select private.finalize_due_challenges();"                          # uzavřít staré výzvy hned
  supabase db query --remote --yes "update public.posts p set created_at = (c.end_date + time '14:00') at time zone c.timezone
    from public.challenges c where p.challenge_id = c.id and p.kind = 'challenge_result' and p.created_at > c.end_date + 1"
                                                                    # karty výsledků na den konce výzvy, ne nahoru do feedu
  python3 -I supabase/tests/review_seed.py <scratch>/keys.json ~/.bedrival/review_state.json --refresh  # před odesláním k review
  rm <scratch>/keys.json

State (hesla všech čtyř účtů) patří MIMO git – repo je veřejné. Heslo recenzenta jde do
App Store Connect → App Review Information. Když se state ztratí: --reset-passwords.

Uživatelé (@bedrival.app – doména se nepoužívá k posílání, účty zakládá admin API):
  R „Alex“  review@bedrival.app – přihlásí se recenzent
  B „Bára“  pozve R, C, D (je „kořen“, profil zakládá service role)
  C „Cyril“, D „Dana“
Data: 30 nocí s tagy (zjištění), názvy, komentáře a reakce; souboje B×R (skončený, R prohrál
→ R dluží), R×C (skončený, R vyhrál → ovečka, C dluží), R×B běžící, společný cíl C+R+D běžící,
čekající výzva od D, nepoužitý kód pozvánky od R (pro recenzenta se Sign in with Apple).

--refresh: dohraje noci do dneška (ingest přepíše jen svoje noci), názvy u nových karet a
když neběží žádný souboj R×B, založí nový (od včerejška). Spouštět těsně před odesláním.
"""
import datetime as dt
import importlib.util
import json
import os
import random
import secrets
import sys
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("seed_dev", os.path.join(HERE, "seed_dev.py"))
seed_dev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(seed_dev)   # jen funkce (main je pod __name__)

if len(sys.argv) < 3:
    sys.exit(__doc__)
KEYS = json.load(open(sys.argv[1]))
KEYS = KEYS if isinstance(KEYS, list) else KEYS["keys"]
ANON = next(k["api_key"] for k in KEYS if k["name"] == "anon")
SERVICE = next(k["api_key"] for k in KEYS if k["name"] == "service_role")
BASE = "https://tlespfcbqzddddhjsieu.supabase.co"
STATE = sys.argv[2]
TZ = ZoneInfo("Europe/Prague")
TODAY = dt.datetime.now(TZ).date()

USERS = {
    "r": {"email": "review@bedrival.app", "username": "alex_r", "name": "Alex"},
    "b": {"email": "demo-bara@bedrival.app", "username": "bara_n", "name": "Bára"},
    "c": {"email": "demo-cyril@bedrival.app", "username": "cyril_k", "name": "Cyril"},
    "d": {"email": "demo-dana@bedrival.app", "username": "dana_v", "name": "Dana"},
}
HISTORY = {"r": 30, "b": 30, "c": 30, "d": 20}


def req(method, path, body=None, token=None, apikey=ANON, extra=None):
    h = {"apikey": apikey, "Content-Type": "application/json", "Authorization": f"Bearer {token or apikey}"}
    h.update(extra or {})
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            txt = resp.read().decode()
            return resp.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, txt


def svc(method, path, body=None, extra=None):
    return req(method, path, body, token=SERVICE, apikey=SERVICE, extra=extra)


def ok(name, st, body, good=(200, 201, 204)):
    if st not in good:
        raise SystemExit(f"FAIL {name}: {st} {body}")
    print(f"ok   {name}")
    return body


def day(offset):
    return TODAY + dt.timedelta(days=offset)


def load_state():
    try:
        return json.load(open(STATE))
    except FileNotFoundError:
        return {"users": {}, "challenges": {}}


def save_state(state):
    with open(STATE, "w") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
    os.chmod(STATE, 0o600)


def admin_user(email):
    st, body = svc("GET", "/auth/v1/admin/users?per_page=1000")
    return next((u for u in (body or {}).get("users", []) if u.get("email") == email), None)


def login(u):
    st, tok = req("POST", "/auth/v1/token?grant_type=password", {"email": u["email"], "password": u["password"]})
    ok(f"přihlášení {u['name']}", st, tok)
    u["jwt"] = tok["access_token"]


# --- noci -------------------------------------------------------------------
# Kdo kdy spí hůř/líp, aby výsledky skončených soubojů vyšly, jak má ukázat demo.
def night_plan(key, wake):
    rng = random.Random(f"review:{key}:{wake.isoformat()}")
    tags = rng.choices([[], ["alcohol"], ["late_coffee"], ["evening_workout"], ["phone_in_bed"],
                        ["alcohol", "late_meal"], ["kid"]], [7, 2, 2, 2, 2, 1, 1])[0]
    style, deep_f, shift = rng.choices(["early", "normal", "late"], [2, 6, 1])[0], 1.0, 0.0
    off = (wake - TODAY).days
    if -20 <= off <= -14:   # souboj B×R: Bára vyhraje
        style = {"b": "early", "r": "late"}.get(key, style)
    if -12 <= off <= -6:    # souboj R×C: Alex vyhraje
        style = {"r": "early", "c": "late"}.get(key, style)
    for t in tags:
        st, df, sh = seed_dev.EFFECTS[t]
        style = st if st != "normal" else style
        deep_f *= df
        shift += sh
    return style, deep_f, shift, tags, rng


def ingest(key, u, first_offset):
    samples, hr, plan = [], [], {}
    for off in range(first_offset, 1):
        wake = day(off)
        style, deep_f, shift, tags, rng = night_plan(key, wake)
        s, h = seed_dev.make_night(rng, wake, style, deep_f, shift)
        samples += s
        hr += h
        plan[wake.isoformat()] = tags
    st, res = req("POST", "/functions/v1/ingest-sleep",
                  {"timezone": "Europe/Prague", "samples": samples, "heart_rate": hr}, token=u["jwt"])
    ok(f"ingest {u['name']}: {len((res or {}).get('nights', []))} nocí", st, res)
    return plan


def decorate_posts(key, u, plan, only_new=False):
    """Tagy, názvy a komentář u vlastních karet; staré karty dolů ve feedu (created_at = konec spánku)."""
    st, posts = req("GET", f"/rest/v1/posts?select=id,night_id,title,night:nights(night_date,sleep_end)"
                           f"&user_id=eq.{u['id']}&kind=eq.night", token=u["jwt"])
    ok(f"karty {u['name']}", st, posts)
    rng = random.Random(f"titles:{key}")
    for p in posts:
        d = p["night"]["night_date"]
        if d not in plan or (only_new and p["title"]):
            continue
        tags = plan[d]
        req("DELETE", f"/rest/v1/night_tags?night_id=eq.{p['night_id']}", token=u["jwt"])
        for tag in tags:
            req("POST", "/rest/v1/night_tags", {"night_id": p["night_id"], "tag": tag}, token=u["jwt"])
        if d != TODAY.isoformat():   # dnešní karta bez názvu (automatický název)
            matching = [t for t in seed_dev.TITLES if t[2] == tags] or [t for t in seed_dev.TITLES if not t[2]]
            title, body, _ = rng.choice(matching)
            req("PATCH", f"/rest/v1/posts?id=eq.{p['id']}", {"title": title, "body": body}, token=u["jwt"])
        if d < day(-1).isoformat():
            svc("PATCH", f"/rest/v1/posts?id=eq.{p['id']}", {"created_at": p["night"]["sleep_end"]})
    return posts


def social(users, posts_by_key):
    lines = ["Tohle je skóre?", "Pivo vyhrálo, co.", "Respekt.", "Zítra tě porazím.", "Spíš víc než já, nefér.",
             "Jak to děláš?", "Klasika."]
    recent = {k: [p for p in ps if p["night"]["night_date"] >= day(-9).isoformat()] for k, ps in posts_by_key.items()}
    for k, u in users.items():
        rng = random.Random(f"social:{k}")
        for other, posts in recent.items():
            if other == k:
                continue
            for p in posts:
                if rng.random() < 0.7:
                    req("POST", "/rest/v1/reactions?on_conflict=post_id,user_id",
                        {"post_id": p["id"], "user_id": u["id"],
                         "kind": rng.choice(["sleeper", "zombie", "beer", "coffee", "crown"])},
                        token=u["jwt"], extra={"Prefer": "resolution=merge-duplicates"})
                if rng.random() < 0.3:
                    req("POST", "/rest/v1/comments", {"post_id": p["id"], "user_id": u["id"],
                                                      "body": rng.choice(lines)}, token=u["jwt"])
    print("ok   reakce a komentáře")


# --- výzvy ------------------------------------------------------------------
def challenge(creator, opponents, accept, start_off, ctype="duel", stake=None, target=None, start=False):
    body = {"p_type": ctype, "p_opponents": [o["id"] for o in opponents], "p_duration_days": 7, "p_stake": stake}
    if target is not None:
        body["p_target_score"] = target
    st, cid = req("POST", "/rest/v1/rpc/create_challenge", body, token=creator["jwt"])
    ok(f"výzva {ctype} od {creator['name']}", st, cid)
    for o in accept:
        ok(f"  {o['name']} přijme", *req("POST", "/rest/v1/rpc/respond_challenge",
                                         {"p_challenge": cid, "p_accept": True}, token=o["jwt"]))
    if start:
        ok("  spuštění", *req("POST", "/rest/v1/rpc/start_challenge", {"p_challenge": cid}, token=creator["jwt"]))
    if start_off is not None:   # posunout do minulosti, ať se do ní propíšou noci
        ok("  posun data", *svc("PATCH", f"/rest/v1/challenges?id=eq.{cid}",
                                {"start_date": day(start_off).isoformat(), "end_date": day(start_off + 6).isoformat()}))
    return cid


def setup(state):
    users = state["users"]
    for k, spec in USERS.items():
        if admin_user(spec["email"]):
            raise SystemExit(f"{spec['email']} už existuje – použij --refresh (nebo --reset-passwords).")
    names = ",".join(u["username"] for u in USERS.values())
    st, taken = svc("GET", f"/rest/v1/profiles?select=username&username=in.({names})")
    if taken:
        raise SystemExit(f"Přezdívky zabrané: {taken}")
    for k, spec in USERS.items():
        pw = secrets.token_urlsafe(12)
        st, body = svc("POST", "/auth/v1/admin/users", {"email": spec["email"], "password": pw, "email_confirm": True})
        ok(f"uživatel {spec['name']}", st, body)
        users[k] = dict(spec, id=body["id"], password=pw)
        save_state(state)
        login(users[k])
    R, B, C, D = (users[k] for k in "rbcd")

    ok("profil Bára", *svc("POST", "/rest/v1/profiles", {"id": B["id"], "username": B["username"],
                                                          "display_name": B["name"], "timezone": "Europe/Prague"}))
    svc("POST", "/rest/v1/user_stats", {"user_id": B["id"]})
    ok("Bára souhlas", *req("POST", "/rest/v1/rpc/accept_terms", {}, token=B["jwt"]))
    svc("PATCH", f"/rest/v1/profiles?id=eq.{B['id']}", {"invites_available": 3})
    for x in (R, C, D):
        st, code = req("POST", "/rest/v1/rpc/create_invite", {}, token=B["jwt"])
        ok("pozvánka", st, code)
        ok(f"{x['name']} souhlas", *req("POST", "/rest/v1/rpc/accept_terms", {}, token=x["jwt"]))
        ok(f"{x['name']} uplatní", *req("POST", "/rest/v1/rpc/redeem_invite",
                                        {"p_code": code, "p_username": x["username"], "p_display_name": x["name"]},
                                        token=x["jwt"]))
    for a, b in ((R, C), (R, D), (C, D)):
        ok(f"{a['name']} → {b['name']}", *req("POST", "/rest/v1/rpc/send_friend_request", {"p_user": b["id"]},
                                              token=a["jwt"]))
        ok(f"{b['name']} přijme", *req("POST", "/rest/v1/rpc/respond_friend_request",
                                       {"p_user": a["id"], "p_accept": True}, token=b["jwt"]))

    # výzvy před nocemi, ať ingest zapíše denní skóre
    ch = state["challenges"]
    ch["br_done"] = challenge(B, [R], [R], -20, stake="Prohraný zve na večeři")
    ch["rc_done"] = challenge(R, [C], [C], -12, stake="Prohraný platí pivo")
    ch["rb_live"] = challenge(R, [B], [B], -3, stake="Kdo prohraje, vaří")
    ch["team_live"] = challenge(C, [R, D], [R, D], -2, ctype="team_goal", target=72,
                                stake="Když to dáme, jdeme na snídani", start=True)
    ch["dr_pending"] = challenge(D, [R], [], None, stake="Prohraný nosí týden kafe")
    save_state(state)

    posts = {}
    for k in "rbcd":
        plan = ingest(k, users[k], -(HISTORY[k] - 1))
        posts[k] = decorate_posts(k, users[k], plan)
    social(users, posts)

    st, code = req("POST", "/rest/v1/rpc/create_invite", {}, token=R["jwt"])
    ok("kód pozvánky pro review", st, code)
    state["review_invite_code"] = code
    ok("Alex: staré notifikace přečtené", *req("POST", "/rest/v1/rpc/mark_notifications_read", {}, token=R["jwt"]))
    # pár čerstvých nepřečtených, ať zvoneček něco ukazuje
    latest = max(posts["r"], key=lambda p: p["night"]["night_date"])
    ok("Bára komentuje dnešní noc", *req("POST", "/rest/v1/comments",
                                          {"post_id": latest["id"], "user_id": B["id"], "body": "Tohle je skóre?"},
                                          token=B["jwt"]))
    req("POST", "/rest/v1/reactions?on_conflict=post_id,user_id",
        {"post_id": latest["id"], "user_id": C["id"], "kind": "crown"}, token=C["jwt"],
        extra={"Prefer": "resolution=merge-duplicates"})


def refresh(state):
    users = state["users"]
    for u in users.values():
        login(u)
    for k in "rbcd":
        plan = ingest(k, users[k], -9)
        decorate_posts(k, users[k], plan, only_new=True)
    R, B = users["r"], users["b"]
    st, live = req("GET", "/rest/v1/challenges?select=id,type,status&status=eq.active&type=eq.duel", token=R["jwt"])
    if not any(c["id"] == state["challenges"].get("rb_live") for c in live or []):
        state["challenges"]["rb_live"] = challenge(R, [B], [B], -1, stake="Kdo prohraje, vaří")
        save_state(state)
        print("   nový souboj R×B (starý skončil) – noci se propíšou při dalším --refresh nebo zítřejší synchronizaci")


def reset_passwords(state):
    for k, spec in USERS.items():
        u = admin_user(spec["email"])
        if not u:
            raise SystemExit(f"{spec['email']} neexistuje")
        pw = secrets.token_urlsafe(12)
        ok(f"nové heslo {spec['name']}", *svc("PUT", f"/auth/v1/admin/users/{u['id']}", {"password": pw}))
        state["users"][k] = dict(spec, id=u["id"], password=pw)
    save_state(state)


state = load_state()
if "--reset-passwords" in sys.argv:
    reset_passwords(state)
elif "--refresh" in sys.argv:
    refresh(state)
else:
    setup(state)
for u in state["users"].values():
    u.pop("jwt", None)
save_state(state)
R = state["users"].get("r", {})
print(f"\nREVIEW ÚČET: {R.get('email')} / heslo ve {STATE}")
if state.get("review_invite_code"):
    print(f"Kód pozvánky pro review: {state['review_invite_code']}")
