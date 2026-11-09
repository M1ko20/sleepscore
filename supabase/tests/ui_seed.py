import datetime, json, secrets, sys, urllib.request, urllib.error, zoneinfo
# Dočasná data pro UI testy (issue #13) v produkci. Vytvoří 4 testovací uživatele
# (ui-…@example.test), přátelství přes pozvánku, noci přes ingest-sleep, komentáře,
# reakce a výzvy. Přihlášení a ID zapíše do <state.json> (scratchpad, NE do gitu).
#
#   supabase projects api-keys --project-ref tlespfcbqzddddhjsieu -o json > <scratch>/keys.json
#   python3 -I supabase/tests/ui_seed.py <scratch>/keys.json <scratch>/ui_state.json
#   ... UI testy ...
#   python3 -I supabase/tests/ui_seed.py <scratch>/keys.json <scratch>/ui_state.json --cleanup
#   rm <scratch>/keys.json
#
# Uživatelé:
#   A „UI Anna“  – přihlášená v appce (zakladatelka, pozve B, C, D)
#   B „UI Bára“  – komentuje a reaguje na kartu A, vyzve A na souboj se sázkou; kamarádka C
#   C „UI Cyril“ – reaguje na kartu A (sloučená notifikace); A komentuje a reaguje na jeho kartu
#   D „UI Dan“   – založí skupinovou výzvu (A, C), spustí ji a smaže si účet (creator_id = null)
# --cleanup smaže výzvy, hlášení (reporter = testovací uživatel) a uživatele; navíc
# pro jistotu všechny účty ui-*@example.test.
KEYS = json.load(open(sys.argv[1]))
KEYS = KEYS if isinstance(KEYS, list) else KEYS["keys"]
ANON = next(k["api_key"] for k in KEYS if k["name"] == "anon")
SERVICE = next(k["api_key"] for k in KEYS if k["name"] == "service_role")
BASE = "https://tlespfcbqzddddhjsieu.supabase.co"
STATE = sys.argv[2]
TZ = zoneinfo.ZoneInfo("Europe/Prague")


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


def ok(name, st, body, good=(200, 201, 204)):
    if st not in good:
        raise SystemExit(f"FAIL {name}: {st} {body}")
    print(f"ok   {name}")
    return body


def save(state):
    with open(STATE, "w") as f:
        json.dump(state, f, indent=2)


def cleanup():
    try:
        state = json.load(open(STATE))
    except Exception:
        state = {"users": {}, "challenges": []}
    ids = [u["id"] for u in state.get("users", {}).values()]
    if ids:
        st, _ = svc("DELETE", f"/rest/v1/reports?reporter_id=in.({','.join(ids)})")
        print("reports deleted", st)
    for cid in state.get("challenges", []):
        st, _ = svc("DELETE", f"/rest/v1/challenges?id=eq.{cid}")
        print("challenge deleted", st)
    for u in state.get("users", {}).values():
        st, _ = svc("DELETE", f"/auth/v1/admin/users/{u['id']}")
        print("user deleted", u["email"], st)
    # pojistka: cokoliv ui-*@example.test, co zbylo
    st, body = svc("GET", "/auth/v1/admin/users?per_page=1000")
    left = [u for u in (body or {}).get("users", []) if (u.get("email") or "").startswith("ui-")
            and u["email"].endswith("@example.test")]
    for u in left:
        svc("DELETE", f"/rest/v1/reports?reporter_id=eq.{u['id']}")
        st, _ = svc("DELETE", f"/auth/v1/admin/users/{u['id']}")
        print("leftover user deleted", u["email"], st)
    st, body = svc("GET", "/auth/v1/admin/users?per_page=1000")
    n = sum(1 for u in (body or {}).get("users", []) if (u.get("email") or "").endswith("@example.test"))
    print("example.test users left:", n)
    if ids:
        st, rest = svc("GET", f"/rest/v1/reports?select=id&reporter_id=in.({','.join(ids)})")
        print("reports left:", rest)
    if state.get("challenges"):
        st, rest = svc("GET", f"/rest/v1/challenges?select=id&id=in.({','.join(state['challenges'])})")
        print("challenges left:", rest)


if "--cleanup" in sys.argv:
    cleanup()
    sys.exit(0)

tag = secrets.token_hex(3)
state = {"tag": tag, "users": {}, "challenges": []}
names = {"a": "UI Anna", "b": "UI Bára", "c": "UI Cyril", "d": "UI Dan"}
try:
    for u, name in names.items():
        email = f"ui-{u}-{tag}@example.test"
        pw = secrets.token_urlsafe(18)
        st, body = svc("POST", "/auth/v1/admin/users", {"email": email, "password": pw, "email_confirm": True})
        ok(f"user {u}", st, body)
        state["users"][u] = {"id": body["id"], "email": email, "password": pw,
                             "username": f"ui_{u}_{tag}", "name": name}
        save(state)
        st, tok = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})
        ok(f"token {u}", st, tok)
        state["users"][u]["jwt"] = tok["access_token"]
    U = state["users"]
    A, B, C, D = U["a"], U["b"], U["c"], U["d"]

    ok("profil A", *svc("POST", "/rest/v1/profiles", {"id": A["id"], "username": A["username"],
                                                        "display_name": A["name"], "timezone": "Europe/Prague"}))
    svc("POST", "/rest/v1/user_stats", {"user_id": A["id"]})
    for x in (B, C, D):
        st, code = req("POST", "/rest/v1/rpc/create_invite", {}, token=A["jwt"])
        ok("pozvánka", st, code)
        ok(f"podmínky {x['name']}", *req("POST", "/rest/v1/rpc/accept_terms", {}, token=x["jwt"]))
        ok(f"redeem {x['name']}", *req("POST", "/rest/v1/rpc/redeem_invite",
                                       {"p_code": code, "p_username": x["username"], "p_display_name": x["name"]},
                                       token=x["jwt"]))
    ok("B → C žádost", *req("POST", "/rest/v1/rpc/send_friend_request", {"p_user": C["id"]}, token=B["jwt"]))
    ok("C přijme B", *req("POST", "/rest/v1/rpc/respond_friend_request", {"p_user": B["id"], "p_accept": True},
                          token=C["jwt"]))
    ok("D → C žádost", *req("POST", "/rest/v1/rpc/send_friend_request", {"p_user": C["id"]}, token=D["jwt"]))
    ok("C přijme D", *req("POST", "/rest/v1/rpc/respond_friend_request", {"p_user": D["id"], "p_accept": True},
                          token=C["jwt"]))

    # --- noci: dvě poslední (končí včera a dnes ráno) ----------------------
    today = datetime.datetime.now(TZ).date()

    def seg(start, end, stage):
        return {"uuid": secrets.token_hex(8), "start": start, "end": end, "stage": stage,
                "source": "Apple Watch", "userEntered": False}

    def night(d, shift):  # usnutí ~23:00 Praha (+shift minut)
        p = d - datetime.timedelta(days=1)
        t0 = datetime.datetime(p.year, p.month, p.day, 22, 0, tzinfo=datetime.timezone.utc) \
            + datetime.timedelta(minutes=shift)
        pts = [0, 90, 150, 160, 280, 370, 480]
        stages = ["core", "deep", "awake", "core", "rem", "core"]
        iso = lambda m: (t0 + datetime.timedelta(minutes=m)).strftime("%Y-%m-%dT%H:%M:%SZ")
        return [seg(iso(pts[i]), iso(pts[i + 1]), s) for i, s in enumerate(stages)]

    for i, x in enumerate((A, B, C)):
        # C jen jednu noc → po nahlášení karty z feedu A zmizí úplně
        samples = (night(today - datetime.timedelta(days=1), 10 * i) if x is not C else []) + night(today, 10 * i)
        st, res = req("POST", "/functions/v1/ingest-sleep", {"timezone": "Europe/Prague", "samples": samples},
                      token=x["jwt"])
        ok(f"ingest {x['name']}: {[(n['date'], n['status']) for n in (res or {}).get('nights', [])]}", st, res)

    def latest_post(x, viewer):
        st, posts = req("GET", f"/rest/v1/posts?user_id=eq.{x['id']}&select=id,night:nights(night_date)",
                        token=viewer["jwt"])
        posts.sort(key=lambda p: p["night"]["night_date"], reverse=True)
        return posts[0]["id"]

    post_a = latest_post(A, B)
    post_c = latest_post(C, A)
    state["posts"] = {"a": post_a, "c": post_c}
    # --- výzvy ----------------------------------------------------------
    # D: skupinová (A, C), všichni přijmou, D spustí a smaže si účet → creator_id null
    st, gid = req("POST", "/rest/v1/rpc/create_challenge",
                  {"p_type": "free_for_all", "p_opponents": [A["id"], C["id"]], "p_duration_days": 7,
                   "p_stake": "poslední peče buchty"}, token=D["jwt"])
    ok("D založí skupinovou", st, gid)
    state["challenges"].append(gid)
    save(state)
    for x in (A, C):
        ok(f"{x['name']} přijme skupinovou",
           *req("POST", "/rest/v1/rpc/respond_challenge", {"p_challenge": gid, "p_accept": True}, token=x["jwt"]))
    ok("D spustí", *req("POST", "/rest/v1/rpc/start_challenge", {"p_challenge": gid}, token=D["jwt"]))
    ok("D smaže účet", *req("POST", "/rest/v1/rpc/delete_my_account", {}, token=D["jwt"]))
    st, ch = svc("GET", f"/rest/v1/challenges?id=eq.{gid}&select=status,creator_id")
    print("   skupinová po smazání D:", ch)
    del state["users"]["d"]
    save(state)
    # A si nepřečtené z D (pozvánka, start) označí, ať zvoneček ukazuje jen to podstatné
    ok("A: staré přečtené", *req("POST", "/rest/v1/rpc/mark_notifications_read", {}, token=A["jwt"]))

    # komentář a reakce na kartu A (nepřečtené → zvoneček), A u C (pro test blokovaného B)
    ok("B komentuje A", *req("POST", "/rest/v1/comments",
                             {"post_id": post_a, "user_id": B["id"], "body": "Bára byla u toho, chrápals"},
                             token=B["jwt"]))
    ok("B reaguje A", *req("POST", "/rest/v1/reactions", {"post_id": post_a, "user_id": B["id"], "kind": "zombie"},
                           token=B["jwt"]))
    ok("C reaguje A", *req("POST", "/rest/v1/reactions", {"post_id": post_a, "user_id": C["id"], "kind": "beer"},
                           token=C["jwt"]))
    ok("C komentuje sebe", *req("POST", "/rest/v1/comments",
                                {"post_id": post_c, "user_id": C["id"], "body": "Cyril sám sobě"}, token=C["jwt"]))
    ok("A komentuje C", *req("POST", "/rest/v1/comments",
                             {"post_id": post_c, "user_id": A["id"], "body": "Anna tu byla"}, token=A["jwt"]))
    ok("A reaguje C", *req("POST", "/rest/v1/reactions", {"post_id": post_c, "user_id": A["id"], "kind": "crown"},
                           token=A["jwt"]))

    # B vyzve A (sázka) → A přijme v UI
    st, did = req("POST", "/rest/v1/rpc/create_challenge",
                  {"p_type": "duel", "p_opponents": [A["id"]], "p_duration_days": 7,
                   "p_stake": "prohraná peče štrúdl"}, token=B["jwt"])
    ok("B vyzve A", st, did)
    state["challenges"].append(did)
    save(state)

    # notifikace u A
    st, notes = req("GET", "/rest/v1/notifications?select=kind,read_at,text:notification_text&order=created_at",
                    token=A["jwt"])
    for n in notes:
        print("   A notif:", n["kind"], "nové" if n["read_at"] is None else "přečtené", "|", n["text"])

    for u in state["users"].values():
        u.pop("jwt", None)
    save(state)
    print("seed hotový, tag", tag)
except BaseException:
    for u in state["users"].values():
        u.pop("jwt", None)
    save(state)
    print("seed selhal → úklid")
    cleanup()
    raise
