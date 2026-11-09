# App Review – přístup a poznámky (#18)

## Demo účet
- E-mail: `review@bedrival.app`, heslo: `~/.bedrival/review_state.json` (mimo git, `users.r.password`). Vyplnit do App Store Connect → App Review Information → Sign-in required.
- Kód pozvánky pro nový účet přes Sign in with Apple: `review_invite_code` ve stejném souboru (nepoužitý kód od Alexe).
- Data: `supabase/tests/review_seed.py` (popis v hlavičce). **Před každým odesláním** spustit `--refresh` – dohraje noci do dneška a založí nový souboj, pokud starý skončil.
- Účty `@bedrival.app` nikdy nemazat (ui_seed/e2e mažou jen `@example.test` a vlastní testovací účty).
- Screenshoty průchodu: `SleepAppUITests/ReviewAccountTests` (`TEST_RUNNER_UITEST_LOGIN=review@bedrival.app:<heslo>`).

## Review notes (do App Store Connect, anglicky)
```
Bedrival is an invite-only social app for sleep: every morning your night from Apple Health
appears as a card that only your friends can see, they can react and comment, and friends
compete in 7-day sleep challenges.

DEMO ACCOUNT
Tap "Už mám účet" (I already have an account) → "Přihlásit e-mailem" (Sign in with email)
and use the credentials provided above. The account is pre-filled with 30 nights, friends,
comments, finished and running challenges, and a pending challenge invitation.
To create a new account with Sign in with Apple, use invite code: <KÓD>

APPLE HEALTH
The app only READS sleep analysis and heart rate recorded by a watch or ring (manual entries
are ignored). Data is used only to compute the sleep score shown to the user and their
friends. Nothing is used for advertising or shared with third parties. The demo account
already contains data, so you can review the app without a device; Health permission can be
declined.

The sleep score and insights are for entertainment and comparison with friends only. The app
is not a medical device and shows this in Settings → Privacy and under the insights.

CHALLENGES AND STAKES
Players can write a free-text stake (e.g. "loser buys a beer"). The app does not process,
hold or transfer any money or items; it only displays the text and lets the debtor mark it
as settled. There is no gambling or in-app purchase.

USER-GENERATED CONTENT
Users accept the Terms (zero tolerance for objectionable content) before creating a profile.
Report: "…" menu on a card, comment or profile → Nahlásit (Report).
Block: profile → "…" → Zablokovat (Block).
Reports are delivered to the developer immediately and handled within 24 hours.

ACCOUNT DELETION
Profile → Settings (gear) → Soukromí a moje data (Privacy) → Smazat účet (Delete account).

The app UI is in Czech.
```
