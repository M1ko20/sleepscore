#!/usr/bin/env python3
"""Testovací noci pro dev účty – posílá je přes ingest-sleep jako telefon.

  python3 -I supabase/tests/seed_dev.py adam@sleepscore.test:HESLO jakub@sleepscore.test:HESLO

Klíč: publishable z env SUPABASE_KEY (nebo pevně níže – je veřejný).
Vygeneruje 7 nocí na uživatele (deterministicky podle e-mailu), u starších nocí název,
komentář a tagy, a mezi uživateli reakce a komentáře. Dnešní noc nechá bez názvu.
"""
import json, os, random, sys, uuid, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

URL = "https://tlespfcbqzddddhjsieu.supabase.co"
KEY = os.environ.get("SUPABASE_KEY", "sb_publishable_NnhwZ0_QgLrxu_p5jturoQ_M3r1T-dA")
TZ = ZoneInfo("Europe/Prague")
NIGHTS = 7


def req(method, path, body=None, token=None, prefer=None):
    headers = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def login(email, password):
    st, d = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": password})
    assert st == 200, d
    return d["access_token"], d["user"]["id"]


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def make_night(rng, wake_date, style):
    """Úseky fází a tep pro jednu noc končící ráno wake_date."""
    bed_base = {"early": 22.6, "normal": 23.2, "late": 0.6}[style]
    hour = bed_base + rng.uniform(-0.5, 0.5)
    day = wake_date - timedelta(days=1) if hour >= 12 or hour > 20 else wake_date
    if hour < 12:
        day = wake_date
    start = datetime(day.year, day.month, day.day, tzinfo=TZ) + timedelta(hours=hour % 24)
    total_min = rng.uniform(*{"early": (440, 520), "normal": (400, 480), "late": (300, 390)}[style])

    segs, t, cycle = [], start, 0
    end = start + timedelta(minutes=total_min)
    while t < end:
        frac = (t - start) / (end - start)
        deep = max(0.0, rng.uniform(25, 40) * (1 - frac * 1.3))
        rem = rng.uniform(8, 15) + frac * rng.uniform(15, 30)
        core = rng.uniform(35, 55)
        plan = [("core", core * 0.5), ("deep", deep), ("core", core * 0.5), ("rem", rem)]
        if cycle > 0 and rng.random() < 0.45:
            plan.insert(0, ("awake", rng.uniform(1.5, 6)))
        for stage, minutes in plan:
            if minutes < 1 or t >= end:
                continue
            s_end = min(end, t + timedelta(minutes=minutes))
            segs.append({"uuid": str(uuid.uuid4()), "start": iso(t), "end": iso(s_end),
                         "stage": stage, "source": "Garmin Connect", "userEntered": False})
            t = s_end
        cycle += 1

    hr, base = [], rng.uniform(50, 58)
    stage_at = lambda x: next((s["stage"] for s in segs if s["start"] <= iso(x) < s["end"]), "core")
    x = start
    while x < end:
        bump = {"deep": -4, "core": 0, "rem": 3, "awake": 9}[stage_at(x)]
        hr.append({"t": iso(x), "bpm": round(base + bump + rng.uniform(-2, 2))})
        x += timedelta(minutes=2)
    return segs, hr


TITLES = [
    ("Spal jsem jak dřevo", "Konečně normální noc.", ["evening_workout"]),
    ("Narozeniny", "Nebudu to rozebírat.", ["alcohol", "late_meal"]),
    ("Kafe ve čtyři byla chyba", None, ["late_coffee"]),
    ("Netflix vyhrál", "Ještě jeden díl. A ještě jeden.", ["phone_in_bed"]),
    (None, "Malá se budila dvakrát.", ["kid"]),
    ("Klasika", None, []),
]


def main(users):
    today = datetime.now(TZ).date()
    accounts = []
    for spec in users:
        email, password = spec.split(":", 1)
        token, uid = login(email, password)
        rng = random.Random(email)
        samples, hr = [], []
        for i in range(NIGHTS, 0, -1):
            wake = today - timedelta(days=i - 1)
            style = rng.choices(["early", "normal", "late"], [2, 5, 1])[0]
            s, h = make_night(rng, wake, style)
            samples += s
            hr += h
        st, res = req("POST", "/functions/v1/ingest-sleep",
                      {"timezone": "Europe/Prague", "samples": samples, "heart_rate": hr}, token)
        assert st == 200, res
        print(email, [(n["date"], n.get("score"), n["status"]) for n in res["nights"]])
        accounts.append((email, token, uid, rng))

    # Názvy, komentáře a tagy (vlastní karty, mimo dnešní noc).
    posts_by_user = {}
    for email, token, uid, rng in accounts:
        st, posts = req("GET", f"/rest/v1/posts?select=id,night_id,night:nights(night_date)&user_id=eq.{uid}&kind=eq.night", token=token)
        assert st == 200, posts
        posts_by_user[uid] = posts
        for p in posts:
            if p["night"]["night_date"] == today.isoformat():
                continue
            title, body, tags = rng.choice(TITLES)
            req("PATCH", f"/rest/v1/posts?id=eq.{p['id']}", {"title": title, "body": body}, token)
            req("DELETE", f"/rest/v1/night_tags?night_id=eq.{p['night_id']}", token=token)
            for tag in tags:
                req("POST", "/rest/v1/night_tags", {"night_id": p["night_id"], "tag": tag}, token)

    # Reakce a komentáře na karty ostatních.
    lines = ["Tohle je skóre?", "Pivo vyhrálo, co.", "Respekt.", "Zítra tě porazím.", "Spíš víc než já, nefér."]
    for email, token, uid, rng in accounts:
        for other_uid, posts in posts_by_user.items():
            if other_uid == uid:
                continue
            for p in posts:
                if rng.random() < 0.8:
                    req("POST", "/rest/v1/reactions?on_conflict=post_id,user_id",
                        {"post_id": p["id"], "user_id": uid, "kind": rng.choice(["sleeper", "zombie", "beer", "coffee", "crown"])},
                        token, prefer="resolution=merge-duplicates")
                if rng.random() < 0.4:
                    req("POST", "/rest/v1/comments", {"post_id": p["id"], "user_id": uid, "body": rng.choice(lines)}, token)
    print("hotovo")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
