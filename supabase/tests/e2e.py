import datetime, json, secrets, sys, urllib.request, urllib.error, zoneinfo
# E2E test proti Supabase projektu. Vytvoří 2 testovací uživatele, projde
# pozvánku, souboj, ingest, RLS a na konci uživatele smaže.
# Spuštění:
#   supabase projects api-keys --project-ref tlespfcbqzddddhjsieu -o json > /tmp/keys.json
#   python3 -I supabase/tests/e2e.py /tmp/keys.json && rm /tmp/keys.json
KEYS = json.load(open(sys.argv[1]))
KEYS = KEYS if isinstance(KEYS, list) else KEYS["keys"]
ANON = next(k["api_key"] for k in KEYS if k["name"] == "anon")
SERVICE = next(k["api_key"] for k in KEYS if k["name"] == "service_role")
BASE = "https://tlespfcbqzddddhjsieu.supabase.co"

ok_count = 0
fail_count = 0


def req(method, path, body=None, token=None, apikey=ANON, extra=None):
    h = {"apikey": apikey, "Content-Type": "application/json", "Authorization": f"Bearer {token or apikey}"}
    h.update(extra or {})
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r) as resp:
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


def check(name, cond, detail=""):
    global ok_count, fail_count
    if cond:
        ok_count += 1
        print(f"OK   {name}")
    else:
        fail_count += 1
        print(f"FAIL {name} {detail}")


tag = secrets.token_hex(3)
users = {}
try:
    # --- uživatelé ------------------------------------------------------
    for u in ("a", "b"):
        email = f"e2e-{u}-{tag}@example.test"
        pw = secrets.token_urlsafe(18)
        st, body = svc("POST", "/auth/v1/admin/users", {"email": email, "password": pw, "email_confirm": True})
        assert st == 200, (st, body)
        uid = body["id"]
        st, tok = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})
        assert st == 200, (st, tok)
        users[u] = {"id": uid, "jwt": tok["access_token"]}
    A, B = users["a"], users["b"]
    print("users created")

    # bez profilu nic nevidí
    st, rows = req("GET", "/rest/v1/profiles?select=id", token=B["jwt"])
    check("B bez profilu nevidí profily", st == 200 and rows == [], rows)

    # bootstrap A (zakladatel bez pozvánky)
    st, _ = svc("POST", "/rest/v1/profiles", {"id": A["id"], "username": f"e2e_a_{tag}", "display_name": "E2E A"})
    check("bootstrap profil A", st == 201, _)
    svc("POST", "/rest/v1/user_stats", {"user_id": A["id"]})

    # pozvánka
    st, code = req("POST", "/rest/v1/rpc/create_invite", {}, token=A["jwt"])
    check("A vytvoří pozvánku", st == 200 and isinstance(code, str), code)
    redeem = {"p_code": code, "p_username": f"e2e_b_{tag}", "p_display_name": "E2E B"}
    st, err = req("POST", "/rest/v1/rpc/redeem_invite", redeem, token=B["jwt"])
    check("B bez souhlasu s podmínkami profil nezaloží", st >= 400 and "terms not accepted" in str(err), err)
    st, terms = req("POST", "/rest/v1/rpc/accept_terms", {}, token=B["jwt"])
    check("B souhlasí s podmínkami", st == 200 and terms.get("accepted") is True, terms)
    st, prof = req("POST", "/rest/v1/rpc/redeem_invite", redeem, token=B["jwt"])
    check("B uplatní pozvánku", st == 200, prof)
    st, fr = req("GET", "/rest/v1/friendships?select=status", token=B["jwt"])
    check("A a B jsou přátelé", fr == [{"status": "accepted"}], fr)

    # přímý zápis skóre z klienta nesmí projít
    st, _ = req("POST", "/rest/v1/nights", {"user_id": B["id"], "night_date": "2026-11-01",
                                            "sleep_start": "2026-10-31T22:00:00Z", "sleep_end": "2026-11-01T06:00:00Z",
                                            "total_sleep_min": 480, "score": 100}, token=B["jwt"])
    check("klient nemůže zapsat noc přímo", st in (401, 403), st)

    # souboj
    st, cid = req("POST", "/rest/v1/rpc/create_challenge",
                  {"p_type": "duel", "p_opponents": [B["id"]], "p_duration_days": 7, "p_stake": "prohraný platí pivo"},
                  token=A["jwt"])
    check("A vyzve B", st == 200, cid)
    st, _ = req("POST", "/rest/v1/rpc/respond_challenge", {"p_challenge": cid, "p_accept": True}, token=B["jwt"])
    check("B přijme", st in (200, 204), _)
    st, ch = req("GET", f"/rest/v1/challenges?id=eq.{cid}&select=status,start_date,end_date", token=A["jwt"])
    tomorrow = (datetime.datetime.now(zoneinfo.ZoneInfo("Europe/Prague")).date() + datetime.timedelta(days=1)).isoformat()
    check("souboj běží od zítřka", ch and ch[0]["status"] == "active" and ch[0]["start_date"] == tomorrow, ch)
    # posunout start do minulosti, ať jdou nahrát noci
    svc("PATCH", f"/rest/v1/challenges?id=eq.{cid}", {"start_date": "2026-11-04", "end_date": "2026-11-10"})

    # --- ingest ---------------------------------------------------------
    def seg(start, end, stage, src="Garmin Connect", ue=False, uid=None):
        return {"uuid": uid or secrets.token_hex(8), "start": start, "end": end, "stage": stage, "source": src,
                "userEntered": ue}

    def good_night(d_prev, d):  # 23:00–07:00 Praha
        return [
            seg(f"{d_prev}T22:00:00Z", f"{d_prev}T23:30:00Z", "core"),
            seg(f"{d_prev}T23:30:00Z", f"{d}T00:30:00Z", "deep"),
            seg(f"{d}T00:30:00Z", f"{d}T00:40:00Z", "awake"),
            seg(f"{d}T00:40:00Z", f"{d}T02:40:00Z", "core"),
            seg(f"{d}T02:40:00Z", f"{d}T04:10:00Z", "rem"),
            seg(f"{d}T04:10:00Z", f"{d}T06:00:00Z", "core"),
        ]

    hr_a = [{"t": f"2026-11-06T0{h}:00:00Z", "bpm": 52 + h} for h in range(0, 6)]
    payload_a = {
        "timezone": "Europe/Prague",
        "samples": good_night("2026-11-04", "2026-11-05") + good_night("2026-11-05", "2026-11-06") + [
            seg("2026-11-06T11:00:00Z", "2026-11-06T11:40:00Z", "core"),  # šlofík
            seg("2026-11-03T22:00:00Z", "2026-11-04T06:00:00Z", "core", ue=True),  # ruční záznam
        ],
        "heart_rate": hr_a,
    }
    st, res = req("POST", "/functions/v1/ingest-sleep", payload_a, token=A["jwt"])
    print("A ingest:", st, res)
    dates = [n["date"] for n in (res or {}).get("nights", [])]
    check("A: dvě noci, šlofík ani ruční záznam ne", st == 200 and dates == ["2026-11-05", "2026-11-06"], res)
    check("A: karty vytvořené", all(n["status"] == "created" for n in res["nights"]), res)
    check("A: série 2 noci", res["nights"][1].get("streak") == 2, res)

    # B: jen 11-06, krátká rozbitá noc (02:00–06:30)
    b_samples = []
    t = ["2026-11-06T01:00:00Z", "2026-11-06T01:40:00Z", "2026-11-06T01:50:00Z", "2026-11-06T03:00:00Z",
         "2026-11-06T03:15:00Z", "2026-11-06T05:30:00Z"]
    stages = ["core", "awake", "core", "awake", "rem"]
    for i, stg in enumerate(stages):
        b_samples.append(seg(t[i], t[i + 1], stg, src="Apple Watch"))
    st, res_b = req("POST", "/functions/v1/ingest-sleep", {"timezone": "Europe/Prague", "samples": b_samples},
                    token=B["jwt"])
    print("B ingest:", st, res_b)
    check("B: jedna noc", st == 200 and len(res_b["nights"]) == 1, res_b)
    a_score = res["nights"][1]["score"]
    b_score = res_b["nights"][0]["score"]
    check("A má lepší noc než B", a_score > b_score, (a_score, b_score))

    # --- RLS z pohledu přátel --------------------------------------------
    st, nights = req("GET", "/rest/v1/nights?select=user_id,night_date,score,score_breakdown&order=night_date",
                     token=B["jwt"])
    check("B vidí 3 noci (2× A, 1× B)", st == 200 and len(nights) == 3, nights)
    st, raw = req("GET", "/rest/v1/night_raw?select=night_id,segments", token=B["jwt"])
    check("B vidí hypnogram A", st == 200 and len(raw) == 3, len(raw) if isinstance(raw, list) else raw)
    st, scores = req("GET", f"/rest/v1/challenge_day_scores?challenge_id=eq.{cid}&select=user_id,day,score&order=day",
                     token=A["jwt"])
    check("skóre ve výzvě: A 2 dny, B 1 den", st == 200 and len(scores) == 3, scores)

    st, posts = req("GET", f"/rest/v1/posts?user_id=eq.{A['id']}&select=id,night_id&order=created_at", token=B["jwt"])
    post_id = posts[0]["id"]
    st, _ = req("POST", "/rest/v1/comments", {"post_id": post_id, "user_id": B["id"], "body": "spal jsi jak mimino"},
                token=B["jwt"])
    check("B komentuje kartu A", st == 201, _)
    st, _ = req("POST", "/rest/v1/reactions", {"post_id": post_id, "user_id": B["id"], "kind": "crown"}, token=B["jwt"])
    check("B reaguje", st == 201, _)
    st, _ = req("POST", "/rest/v1/reactions", {"post_id": post_id, "user_id": B["id"], "kind": "beer"}, token=B["jwt"])
    check("druhá reakce neprojde", st == 409, st)
    st, _ = req("PATCH", f"/rest/v1/posts?id=eq.{post_id}", {"title": "hack"}, token=B["jwt"],
                extra={"Prefer": "return=representation"})
    check("B nemůže upravit kartu A", st == 200 and _ == [], _)
    st, _ = req("PATCH", f"/rest/v1/posts?id=eq.{post_id}", {"title": "Spal jsem jak dřevo"}, token=A["jwt"],
                extra={"Prefer": "return=representation"})
    check("A upraví svou kartu", st == 200 and len(_) == 1, _)

    # zpětné nahrání jen šlofíku nepřepíše noc
    st, res2 = req("POST", "/functions/v1/ingest-sleep",
                   {"timezone": "Europe/Prague", "samples": [seg("2026-11-06T11:00:00Z", "2026-11-06T11:40:00Z", "core")]},
                   token=A["jwt"])
    check("šlofík nepřepíše hlavní noc", res2["nights"][0]["status"] == "kept_existing", res2)
    # opětovný upload stejné noci = update, ne nová karta
    st, res3 = req("POST", "/functions/v1/ingest-sleep", payload_a, token=A["jwt"])
    check("znovu nahraná noc = update", all(n["status"] == "updated" for n in res3["nights"]), res3)

    st, mma = req("GET", "/rest/v1/mma_records?select=*", token=A["jwt"])
    check("MMA zatím prázdná (výzva běží)", st == 200 and mma == [], mma)

    # --- notifikace (#9, #11) --------------------------------------------
    st, notes = req("GET", "/rest/v1/notifications?select=kind,read_at", token=A["jwt"])
    kinds = {n["kind"] for n in notes or []}
    check("A má notifikace o komentáři a reakci", st == 200 and {"comment", "reaction"} <= kinds, notes)
    st, notes_b = req("GET", "/rest/v1/notifications?select=user_id", token=B["jwt"])
    check("B nevidí notifikace A", st == 200 and all(n["user_id"] == B["id"] for n in notes_b), notes_b)
    st, n_read = req("POST", "/rest/v1/rpc/mark_notifications_read", {}, token=A["jwt"])
    st2, unread = req("GET", "/rest/v1/notifications?select=kind&read_at=is.null", token=A["jwt"])
    check("A označí vše přečtené", st == 200 and unread == [], (n_read, unread))
    st, prefs = req("POST", "/rest/v1/rpc/my_notification_prefs", {}, token=A["jwt"])
    check("výchozí nastavení notifikací: vše zapnuto", st == 200 and all(prefs.values()), prefs)
    st, prefs = req("POST", "/rest/v1/rpc/set_notification_prefs", {"p_prefs": {"reactions": False}}, token=A["jwt"])
    check("A vypne reakce", st == 200 and prefs["reactions"] is False and prefs["comments"] is True, prefs)
    st, _ = req("POST", "/rest/v1/rpc/set_notification_prefs", {"p_prefs": {"nesmysl": True}}, token=A["jwt"])
    check("neznámý klíč nastavení neprojde", st >= 400, st)

    # --- nahlášení a blokování (#6) ----------------------------------------
    st, comments = req("GET", f"/rest/v1/comments?post_id=eq.{post_id}&select=id", token=A["jwt"])
    comment_id = comments[0]["id"]
    st, rid = req("POST", "/rest/v1/rpc/report_content",
                  {"p_kind": "comment", "p_target": comment_id, "p_reason": "spam", "p_note": "e2e test"}, token=A["jwt"])
    check("A nahlásí komentář B", st == 200, rid)
    st, comments = req("GET", f"/rest/v1/comments?post_id=eq.{post_id}&select=id", token=A["jwt"])
    check("nahlášený komentář A už nevidí", st == 200 and comments == [], comments)
    st, _ = req("POST", "/rest/v1/rpc/report_content",
                {"p_kind": "comment", "p_target": comment_id, "p_reason": "spam"}, token=A["jwt"])
    check("podruhé nahlásit = stejné hlášení (idempotentní)", st == 200, (st, _))
    st, _ = req("GET", "/rest/v1/reports?select=id", token=A["jwt"])
    check("klient hlášení nečte", st in (401, 403) or _ == [], (st, _))
    st, _ = req("POST", "/rest/v1/rpc/block_user", {"p_user": B["id"]}, token=A["jwt"])
    check("A zablokuje B", st in (200, 204), _)
    st, fr = req("GET", "/rest/v1/friendships?select=status", token=B["jwt"])
    check("přátelství po bloku zrušené", fr == [], fr)
    st, _ = req("POST", "/rest/v1/rpc/send_friend_request", {"p_user": A["id"]}, token=B["jwt"])
    check("B nemůže poslat žádost", st >= 400, (st, _))
    st, _ = req("POST", "/rest/v1/comments", {"post_id": post_id, "user_id": B["id"], "body": "jsem tu zas"},
                token=B["jwt"])
    check("B nemůže komentovat kartu A", st >= 400, (st, _))
    st, exp = req("POST", "/rest/v1/rpc/export_my_data", {}, token=A["jwt"])
    check("export: bloky, hlášení bez snapshotu, notifikace, nastavení",
          st == 200 and len(exp["blocks"]) == 1 and len(exp["reports_filed"]) == 1
          and "snapshot" not in exp["reports_filed"][0] and len(exp["notifications"]) >= 2
          and exp["notification_prefs"]["reactions"] is False,
          {k: exp.get(k) for k in ("blocks", "reports_filed", "notification_prefs")} if isinstance(exp, dict) else exp)

    print("\nA breakdown 11-06:", next(n for n in nights if n["user_id"] == A["id"] and n["night_date"] == "2026-11-06"))
    print("B breakdown 11-06:", next(n for n in nights if n["user_id"] == B["id"]))
finally:
    if "a" in users:  # hlášení přežije smazání hlásícího (reporter_id → null), tak ho uklidit
        svc("DELETE", f"/rest/v1/reports?reporter_id=eq.{users['a']['id']}")
    for u in users.values():
        st, _ = svc("DELETE", f"/auth/v1/admin/users/{u['id']}")
        print("cleanup user", st)
    st, left = svc("GET", "/rest/v1/profiles?select=id")
    print("profiles left:", left)
    st, left = svc("GET", "/rest/v1/reports?select=id&note=eq.e2e%20test")
    print("e2e reports left:", left)
    st, left = svc("GET", "/rest/v1/challenges?select=id")
    print("challenges left:", left)
    print(f"\n{ok_count} ok, {fail_count} fail")
