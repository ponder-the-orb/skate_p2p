# skate_p2p — Dev setup & the two-device loop

Everything you need to run, test, and field-test the game, written down so
it survives a new laptop, a new seat, or a bad night. Seeds the M4 README.

---

## Prerequisites

- Flutter SDK (Dart ≥ 3.13 per `pubspec.yaml`) · Android SDK + `adb`
- Node.js ≥ 18 (relay) · `npm install` inside `skate_signaling_server/`
- `gh` (GitHub CLI) — optional but lets the Programmer seat open PRs
- Claude Code (the Programmer seat) — see `CLAUDE.md`

## Run the relay

```bash
cd skate_signaling_server
node server.js                 # listens on 0.0.0.0:8080
PORT=9000 node server.js       # env-overridable port
GRACE_MS=200 node server.js    # shorten reconnect grace (tests use this)
```

The relay is a dumb binary forwarder (`docs/PROTOCOL.md`). It never parses
game payloads. Hosting notes for production live under M4 in `ROADMAP.md`.

## Run the client

```bash
flutter run -d linux           # desktop client — handy second player on the dev box
flutter run -d <phone-serial>  # phone over USB
```

The relay address is `relayUrl` in `lib/main.dart`, default
`ws://127.0.0.1:8080`, and it is chosen per build with
`--dart-define=RELAY_URL=...` — never by editing source:

```bash
flutter run -d <phone-serial> --dart-define=RELAY_URL=ws://<laptop-ip>:8080
flutter build apk --dart-define=RELAY_URL=wss://relay.example.com
```

The value is baked in at compile time, so the flag goes on every `flutter
run` **and** every `flutter build` — changing it means stopping the app and
rerunning with the new value. Without the flag a phone reaches the dev relay
only through an adb tunnel (next section).

## Phones and the adb tunnel — the rule that bites

```bash
adb devices                                    # get serials
adb -s <serial> reverse tcp:8080 tcp:8080      # PER DEVICE, PER CONNECTION
```

`adb reverse` makes `127.0.0.1:8080` *on the phone* reach port 8080 *on the
laptop*. It is **not** set-and-forget: it dies every time the phone
reconnects (cable unplugged, wireless debugging drops, phone sleeps). Miss it
and the app's `127.0.0.1` points at the phone itself — the symptom is "the
server is broken" when it isn't. Re-run it before every session.

Note: the camera plugin does not support Linux desktop, so the desktop
client never shows the Record entry. That is by design (ADR-008 ticket
T3.4), not a bug.

## Two real phones, zero dollars

| Situation | What works |
|---|---|
| Home wifi is a public/isolated network (devices can't see each other) | **Phone hotspot.** Phone A hotspots; laptop and phone B join it. That's a private LAN you carry everywhere; isolation gone, no cables. Point clients at the laptop's hotspot IP via `--dart-define=RELAY_URL=ws://<laptop-ip>:8080`. |
| Normal home LAN (e.g., at a friend's) | Skip adb entirely: run the relay on the laptop, point both phones at its LAN IP. Installing builds still needs a cable or wireless adb, one phone at a time. |
| Wireless debugging pairs but "can't reach the server" | You didn't re-run `adb reverse` for that connection — or you're on a LAN and should use the IP instead. |
| After M4-T4.3 (relay deployed to a free tier over `wss://`) | Phones connect from anywhere. The cable's only job is installing builds. |

## Tests

```bash
flutter analyze && flutter test                    # the Producer runs this before EVERY merge
dart format --output=none --set-exit-if-changed .  # format gate
node skate_signaling_server/test/rooms_smoke.js    # self-contained: spawns its own relay on 8129 with GRACE_MS=200
```

The engine test file is the rulebook — read `test/game_engine_test.dart` to
learn the game. Widget tests drive a real `AppState` through its public
handlers; no mocks, no test-only setters (by ruling).

## GitHub CLI on a minimal Linux box (Void)

The default `gh auth login` stores its token in a system keyring; on a
keyring-less box the save silently fails and every new session looks logged
out. Also no browser auto-opens. The login that sticks:

```bash
gh auth login --insecure-storage
# GitHub.com → SSH → Login with a web browser
# It prints a one-time code and WAITS. Open github.com/login/device yourself
# (any device, your phone is fine), enter the code, then wait for
# "Logged in as ponder-the-orb" before closing anything.
gh auth status && gh pr list --state all --limit 3   # proof
```

Token sits in plain text in `~/.config/gh/hosts.yml` — acceptable on a
single-user laptop. Never paste a token into any chat, mine or the seat's
(`WORKFLOW.md §7`). SSH keys handle git push/pull; the gh token handles the
API (PRs). Two separate systems.

## Manual acceptance passes (the lines automation can't run)

**Core game (M2):** create/join → named and unnamed tricks → letters land on
the right player, including across a role swap → gameOver text correct on
both phones → both tap REMATCH → fresh game, roles flipped → kill one app
mid-game → the other lands in the lobby.

**Reconnect grace (M3-T3.3):** kill an app mid-game → survivor shows the
countdown → relaunch, rejoin the code → the identical game returns (letters,
roles, trick). Separate run: let the 120 s expire → survivor lands in the
lobby.

**Clips (M3-T3.4):** during your attempt, Record → replay → Share to a real
messenger → the challenge line arrives on the other phone → Delete removes it
from My clips → deny camera permission once and confirm the friendly
"Camera unavailable" state → the Linux build runs with no Record entry.

## Claude Code session preflight

```bash
git checkout main && git pull    # branch from truth
git status                       # clean?
cat tickets/<id>.md              # right ticket?
claude                           # then: "Work tickets/<id>.md"
```

A fresh `claude` launch is a fresh session. `claude --continue` reopens the
last one (transcripts survive closed terminals). Answer approval prompts with
eyes on them — that is the one moment the seat needs your judgment.
