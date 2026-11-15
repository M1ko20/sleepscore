#!/usr/bin/env python3
"""Demo parta pro screenshoty a video do App Storu v produkci. Jen kamarádi mezi sebou, nikoho jiného nevidí.

  supabase projects api-keys --project-ref tlespfcbqzddddhjsieu -o json > <scratch>/keys.json
  python3 -I supabase/tests/promo_seed.py <scratch>/keys.json ~/.bedrival/promo_state.json             # založení
  supabase db query --remote --yes "update public.nights set created_at = sleep_end + interval '20 minutes' where user_id in
    (select id from public.profiles where username in ('ondra_p','tomas_h','klara_s','matej_b','eliska_v','vojta_d'))"
                                    # noci „nahrané“ ráno po probuzení – uzávěrka nebere noci nahrané po konci výzvy
  supabase db query --remote --yes "select private.finalize_due_challenges();"                          # uzavřít staré výzvy
  supabase db query --remote --yes "insert into public.challenge_day_scores (challenge_id, user_id, day, score, night_id)
    select c.id, p.user_id, n.night_date, n.score, n.id from public.challenges c
    join public.challenge_participants p on p.challenge_id = c.id and p.status = 'accepted'
    join public.nights n on n.user_id = p.user_id and n.night_date between c.start_date and c.end_date
    where c.status = 'active' and n.score is not null and c.creator_id in
      (select id from public.profiles where username in ('ondra_p','tomas_h','klara_s','matej_b','eliska_v','vojta_d'))
    on conflict do nothing"                                                                            # běžící výzvy
  supabase db query --remote --yes "update public.posts p set created_at = (c.end_date + time '14:00') at time zone c.timezone
    from public.challenges c where p.challenge_id = c.id and p.kind = 'challenge_result' and p.created_at > c.end_date + 1"
  python3 -I supabase/tests/promo_seed.py <scratch>/keys.json ~/.bedrival/promo_state.json --refresh   # noci do dneška
  rm <scratch>/keys.json

Hrdina „Tomáš“ (přihlašuje se v simulátoru): bilance 9-2-0 (dvě prohry na začátku, pak 9 výher
v řadě → Odplata, Neporazitelný), 11 oveček (Pastýř), dlouhá série, Detox, Regenerace, zjištění
z tagů. Běží souboj s Ondrou (Tomáš vede) a společný cíl, čeká výzva od Vojty, včera skončil
souboj s Matějem (výhra → obrazovka výsledku). Hesla ve state mimo git.
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
_spec.loader.exec_module(seed_dev)

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
    "h": {"username": "tomas_h", "name": "Tomáš"},
    "o": {"username": "ondra_p", "name": "Ondra"},
    "k": {"username": "klara_s", "name": "Klára"},
    "m": {"username": "matej_b", "name": "Matěj"},
    "e": {"username": "eliska_v", "name": "Eliška"},
    "v": {"username": "vojta_d", "name": "Vojta"},
}
for _k, _u in USERS.items():
    _u["email"] = f"adam.mikolas64+bedrival-promo-{_u['username'].split('_')[0]}@gmail.com"
HISTORY = {"h": 80, "o": 80, "k": 80, "m": 70, "e": 70, "v": 70}

# Výzvy: (klíč, typ, zakladatel, soupeři, start, kdo vyhraje, sázka)
# Okna po 7 dnech; v okně hrdina spí podle toho, jestli má vyhrát.
CHALLENGES = [
    ("w1_o", "duel", "o", ["h"], -76, "o", "Prohraný platí pivo"),
    ("w2_k", "duel", "k", ["h"], -68, "k", "Kdo prohraje, peče buchty"),
    ("w3_o", "duel", "h", ["o"], -60, "h", "Odveta. Prohraný platí dvě piva"),
    ("w3_k", "duel", "h", ["k"], -60, "h", "Prohraný vaří"),
    ("w4_ffa", "free_for_all", "h", ["m", "e", "v"], -52, "h", "Poslední tři platí vítězi večeři"),
    ("w5_v", "duel", "v", ["h"], -44, "h", "Prohraný myje auto"),
    ("w5_e", "duel", "h", ["e"], -44, "h", "Prohraný nosí týden kafe"),
    ("w6_k", "duel", "k", ["h"], -36, "h", "Kdo prohraje, peče buchty"),
    ("w7_o", "duel", "o", ["h"], -28, "h", "Prohraný platí pivo"),
    ("w8_m", "duel", "m", ["h"], -8, "h", "Prohraný platí snídani"),
]
LIVE_DUEL = ("live_o", "o", -3, "Prohraný platí pivo celej večer")
TEAM = ("team_live", "k", ["h", "m"], -4, 75, "Když to dáme, jdeme na wellness")
PENDING = ("pending_v", "v", "Kdo prohraje, píše za druhýho seminárku")


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
HERO_TAGS = [[], [], [], ["workout"], ["reading"], ["sauna"], ["workout", "no_phone"]]
FRIEND_TAGS = [[], [], [], ["alcohol"], ["phone_in_bed"], ["studying"], ["workout"], ["reading"], ["sauna"]]


def window_role(key, off):
    """'win' / 'lose' / None podle výzvy, která v tu noc běží."""
    for _, _, creator, opp, start, winner, _ in CHALLENGES:
        if start <= off <= start + 6 and key in [creator] + opp:
            return "win" if key == winner else "lose"
    if LIVE_DUEL[2] <= off <= 0:
        return {"h": "win", "o": "lose"}.get(key)
    return None


def night_plan(key, wake):
    rng = random.Random(f"promo:{key}:{wake.isoformat()}")
    off = (wake - TODAY).days
    role = window_role(key, off)
    if key == "h":
        if off < -66:              # staré časy: alkohol a telefon (zjištění), nepravidelně
            tags = rng.choices([[], ["alcohol"], ["phone_in_bed"], ["workout"]], [3, 3, 3, 1])[0]
            style = "normal"
        elif -18 <= off <= -12:    # 7 nocí v řadě bez telefonu → Detox
            tags, style = ["no_phone"] + rng.choice([[], ["reading"]]), "early"
        else:
            tags, style = rng.choice(HERO_TAGS), "early"
        if role == "lose":
            style = "normal"
    else:
        tags = rng.choices(FRIEND_TAGS, [5, 4, 2, 2, 2, 1, 2, 1, 1])[0]
        style = rng.choices(["early", "normal", "late"], [2, 6, 2])[0]
        if role == "win":
            style, tags = "early", rng.choice([[], ["workout"], ["sauna"]])
        elif role == "lose":
            style = "late"
    deep_f, shift = 1.0, 0.0
    for t in tags:
        st, df, sh = seed_dev.EFFECTS[t]
        if st != "normal" and not (key == "h" and off >= -66):
            style = st
        deep_f *= df
        shift += sh
    if key == "h" and off >= -66:
        shift = max(-0.15, min(0.15, shift))   # hrdina chodí spát pravidelně (série)
        deep_f = max(deep_f, 1.05)
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


TITLES = {
    "workout": [("Nohy po tréninku nefungujou", "Ale spánek jo."), ("Leg day", None), ("Po fotbale jak dřevo", None)],
    "sauna": [("Sauna a pak tma", "Doporučuju."), ("Wellness víkend", None)],
    "reading": [("Dvě kapitoly a konec", None), ("Kniha místo mobilu", "Funguje to, sakra.")],
    "no_phone": [("Mobil v kuchyni", "Den čtyři. Jde to."), ("Offline", None), ("Bez mobilu", "Kdo by to řekl.")],
    "alcohol": [("Narozeniny", "Nebudu to rozebírat."), ("Jedno pivo", "Nebylo jedno."), ("Svatba", None)],
    "phone_in_bed": [("Reels vyhrály", "Ještě jedno video. A ještě jedno."), ("Netflix vyhrál", None)],
    "studying": [("Zítra zkouška", None), ("Zkouškový", "Spánek je pro slabý. Prý.")],
    "sick": [("Rýma", None)],
    "": [("Klasika", None), ("Nic moc", None), ("Spal jsem jak mimino", None), ("Konečně", "Normální noc."),
         ("Budík? Neznám.", None), ("Šel jsem spát v deset", "Jako důchodce. A vyplatilo se.")],
}


def decorate_posts(key, u, plan, only_new=False):
    st, posts = req("GET", f"/rest/v1/posts?select=id,night_id,title,night:nights(night_date,sleep_end,score)"
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
        if d != TODAY.isoformat() or key != "h":   # hrdinova dnešní karta bez názvu (výzva doplnit)
            pool = TITLES.get(next((t for t in tags if t in TITLES), ""), TITLES[""])
            title, body = rng.choice(pool)
            req("PATCH", f"/rest/v1/posts?id=eq.{p['id']}", {"title": title, "body": body}, token=u["jwt"])
        if d < day(-1).isoformat():
            svc("PATCH", f"/rest/v1/posts?id=eq.{p['id']}", {"created_at": p["night"]["sleep_end"]})
    return posts


def social(users, posts_by_key, only_recent_days=12):
    lines = ["Tohle je skóre?", "Respekt.", "Zítra tě porazím.", "Jak to děláš?", "Klasika.", "Nefér.",
             "Kdo tě naučil spát?", "To pivo se počítá.", "Já bych chtěl taky spát.", "Ovečka se třese.",
             "Brutální.", "Zase?"]
    recent = {k: [p for p in ps if p["night"]["night_date"] >= day(-only_recent_days).isoformat()]
              for k, ps in posts_by_key.items()}
    for k, u in users.items():
        rng = random.Random(f"social:{k}")
        for other, posts in recent.items():
            if other == k:
                continue
            for p in posts:
                if rng.random() < 0.8:
                    req("POST", "/rest/v1/reactions?on_conflict=post_id,user_id",
                        {"post_id": p["id"], "user_id": u["id"],
                         "kind": rng.choice(["sleeper", "zombie", "beer", "coffee", "crown"])},
                        token=u["jwt"], extra={"Prefer": "resolution=merge-duplicates"})
                if rng.random() < 0.35:
                    req("POST", "/rest/v1/comments", {"post_id": p["id"], "user_id": u["id"],
                                                      "body": rng.choice(lines)}, token=u["jwt"])
    print("ok   reakce a komentáře")


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
    if start_off is not None:
        ok("  posun data", *svc("PATCH", f"/rest/v1/challenges?id=eq.{cid}",
                                {"start_date": day(start_off).isoformat(), "end_date": day(start_off + 6).isoformat()}))
    return cid


def setup(state):
    users = state["users"]
    for spec in USERS.values():
        if admin_user(spec["email"]):
            raise SystemExit(f"{spec['email']} už existuje – použij --refresh.")
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
    O = users["o"]
    ok("profil Ondra", *svc("POST", "/rest/v1/profiles", {"id": O["id"], "username": O["username"],
                                                           "display_name": O["name"], "timezone": "Europe/Prague"}))
    svc("POST", "/rest/v1/user_stats", {"user_id": O["id"]})
    ok("Ondra souhlas", *req("POST", "/rest/v1/rpc/accept_terms", {}, token=O["jwt"]))
    # 3 pozvánky na člověka (service role profily neupraví): Ondra zve Tomáše, Kláru a Matěje, Tomáš Elišku a Vojtu.
    for k in "hkmev":
        x = users[k]
        inviter = O if k in "hkm" else users["h"]
        st, code = req("POST", "/rest/v1/rpc/create_invite", {}, token=inviter["jwt"])
        ok("pozvánka", st, code)
        ok(f"{x['name']} souhlas", *req("POST", "/rest/v1/rpc/accept_terms", {}, token=x["jwt"]))
        ok(f"{x['name']} uplatní", *req("POST", "/rest/v1/rpc/redeem_invite",
                                        {"p_code": code, "p_username": x["username"], "p_display_name": x["name"]},
                                        token=x["jwt"]))
    pairs = [(a, b) for i, a in enumerate("hkmev") for b in "hkmev"[i + 1:] if (a, b) not in (("h", "e"), ("h", "v"))]
    for a, b in pairs:
        A, B = users[a], users[b]
        ok(f"{A['name']} → {B['name']}", *req("POST", "/rest/v1/rpc/send_friend_request", {"p_user": B["id"]},
                                              token=A["jwt"]))
        ok(f"{B['name']} přijme", *req("POST", "/rest/v1/rpc/respond_friend_request",
                                       {"p_user": A["id"], "p_accept": True}, token=B["jwt"]))

    posts = {}
    for k in USERS:
        plan = ingest(k, users[k], -(HISTORY[k] - 1))
        posts[k] = decorate_posts(k, users[k], plan)
    social(users, posts)

    # Výzvy až po nocích: cron uzávěrky by jinak mezi založením a nahráním nocí uzavřel staré výzvy
    # s nulami. Uzávěrka bere skóre z nocí sama; běžícím výzvám je doplní SQL v návodu nahoře.
    ch = state["challenges"]
    for key, ctype, creator, opp, start, _, stake in CHALLENGES:
        opps = [users[x] for x in opp]
        ch[key] = challenge(users[creator], opps, opps, start, ctype=ctype, stake=stake,
                            start=(ctype != "duel"))
    key, creator, start, stake = LIVE_DUEL
    ch[key] = challenge(users[creator], [users["h"]], [users["h"]], start, stake=stake)
    key, creator, opp, start, target, stake = TEAM
    opps = [users[x] for x in opp]
    ch[key] = challenge(users[creator], opps, opps, start, ctype="team_goal", target=target, stake=stake, start=True)
    key, creator, stake = PENDING
    ch[key] = challenge(users[creator], [users["h"]], [], None, stake=stake)
    save_state(state)


def refresh(state):
    users = state["users"]
    for u in users.values():
        login(u)
        req("POST", "/rest/v1/rpc/accept_terms", {}, token=u["jwt"])
    posts = {}
    for k in USERS:
        plan = ingest(k, users[k], -6)
        posts[k] = decorate_posts(k, users[k], plan, only_new=True)
    if "--social" in sys.argv:
        social(users, posts, only_recent_days=2)


state = load_state()
if "--refresh" in sys.argv:
    refresh(state)
else:
    setup(state)
for u in state["users"].values():
    u.pop("jwt", None)
save_state(state)
print(f"\nHRDINA: {state['users']['h']['email']} / heslo ve {STATE}")
