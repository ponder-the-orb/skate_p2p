# skate_p2p — Strategy notes

**Audience:** the Producer, future collaborators, and anyone the Producer
pitches. Not law — `ARCHITECTURE.md` is law. This is the *reasoning* that
used to live only in chat, written down so it survives windows, models, and
vendors. Snapshot: 2026-09-02.

---

## What this is

A pocket referee for S.K.A.T.E. Two phones, anywhere, one join code; the app
tracks letters, role swaps, rematches, and survives a dropped connection.

The question every reviewer will ask: *why not just play over Discord?*
Answer: **Discord is where the trash talk lives; skate_p2p is where the score
lives.** Messengers are pipes. The app is the referee and the record — and
later the ladder, the spot map, and the matchmaker. Nobody's group chat does
that.

## Who it's for

Skaters who already play S.K.A.T.E. and already talk to each other. First
wedge: two friends, two phones, a five-digit code. Later wedge: the public
feed (see *Challenge mode*). The demographic is laid-back and allergic to
tourists; authenticity beats polish, but jank is unforgivable.

## The growth loop — why clips are local (ADR-008)

The wire cannot carry video (255-byte payloads, a dumb relay), and video
infrastructure costs money and moderation surface. So clips record and replay
**locally** and leave through the **system share sheet** with a challenge
line. Every shared clip is an advertisement that lands exactly where skaters
already talk. Zero infrastructure. Every player is the marketing department.

**Challenge mode** (parking lot) is this same loop pointed at a public feed:
someone posts a trick, forty strangers post attempts, letters accumulate in
public. Different topology from the 1v1 relay game; same share-sheet brick.

## The server: carrier now, introducer later

Today the relay **carries** every byte between phones — cheap at small scale,
free-tier hosting. ADR-005 turns it into a **signaling server**: phones ask it
"who's in room 41235?", it brokers a WebRTC handshake, then the phones talk
directly. Game events and clips ride phone-to-phone over data channels; the
server pays for introductions only. The one bandwidth cost that scales with
users is the TURN fallback for networks that block direct connections.

The file has been named `signaling_server` since day one. The name was a
prophecy.

## Ranked, honestly

A recorded clip **cannot prove one attempt** — you can't prove a negative
(no off-camera tries). No server spend fixes that; it's epistemology, not
infrastructure. So:

- **Casual stays honor-system on purpose** (ARCHITECTURE §5). That's what
  S.K.A.T.E. between friends *is*. Skate culture polices fake footage
  publicly; lean on it.
- **Ranked has exactly one honest form: the live-witnessed attempt.** Camera
  on, opponent watching, clock running. That needs WebRTC media streams plus
  the attempt timer promoted from advisory to enforced — *in ranked only*.
  Two things already built become load-bearing.

## Money sequence

**Ship → the loop runs → receipts → raise → fund WebRTC, ranked, spots.**
Crowdfunding and angels respond to a demo and an audience; the share loop
manufactures the audience. The launch pays for the raise, not the reverse.

Current burn: one Max subscription (Architect chat + Programmer seat), $0
hosting (free tier), a small Google API balance as fallback. Servers are the
wrong axis for investment right now; engineering time toward ADR-005 is the
right one.

## Moat

Not the code — an agent swarm can clone code in an afternoon. The moat is:
the product **exists and is field-tested** (most ideas die of non-execution);
**scene authenticity** in a culture that smells outsiders instantly; and
**community banked per week** once shipped. Velocity is the moat. The vision
is written into the repo where git timestamps it — nobody gets to say they
thought of it first.

## Non-goals (v1)

Accounts, persistence/history, matchmaking beyond codes, anti-cheat,
spectators, in-app video delivery, ranked.

## Numbers to watch once shipped

Matches completed per week · clips shared per match · rejoin success rate ·
share of games reaching a rematch · installs attributable to shared clips.
