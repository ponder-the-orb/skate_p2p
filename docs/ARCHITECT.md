# skate_p2p — Running the Architect seat

**Purpose.** This file makes the Architect seat portable. Any capable model —
or a human — should be able to sit down with this repo and run the seat
correctly within fifteen minutes. Nothing about how this project is run may
live only in a chat window or a vendor's memory feature. **The repo is the
memory.**

**Owner:** the current Architect, whoever that is. Implementers propose changes
to this file in reports; they do not edit it.

---

## 1. What the seat does (and doesn't)

Four jobs:

1. **Own the law** — `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`,
   `docs/ROADMAP.md`, and this file. Decisions are ADRs: never deleted, only
   superseded.
2. **Write tickets** (§3). A ticket is the complete context an implementer
   needs; if the implementer has to guess, the ticket failed.
3. **Review every PR** before the Producer merges (§4).
4. **Close milestones** with certification, not ceremony (§5).

Not the seat's job: implementing (resist writing code beyond a surgical
snippet to unblock a stuck human), and deciding *whether*. The division of
authority is one line: **the Architect decides what and why, the Programmer
decides how (inside the ticket), the Producer decides whether.**

---

## 2. New window: the first fifteen minutes

1. **Clone.** `git clone https://github.com/ponder-the-orb/skate_p2p.git`
   If git asks for a username, the repo is private — ask the Producer to flip
   it public for the review window. Never accept pasted files as a substitute
   for a clone (snippets alongside a question are fine).
2. **Read, in order:** `CLAUDE.md` → `GEMINI.md` → `docs/ARCHITECTURE.md` →
   `docs/PROTOCOL.md` → `docs/ROADMAP.md` → `docs/WORKFLOW.md` → this file →
   the newest files in `reports/` and `tickets/` → `CHANGELOG.md [Unreleased]`.
3. **Certify the board** — ask git, not the summary:
   ```bash
   git log --oneline -n 5
   git tag
   tail -3 GEMINI.md                      # the "Current focus" line
   for b in $(git branch -r | grep -v HEAD | sed 's|origin/||'); do
     echo "$b: $(git log --oneline main..origin/$b | wc -l) unmerged commits"
   done
   git ls-remote origin 'refs/pull/*' | tail -4   # highest PR number
   ```
4. **Reconcile.** Where the memory/summary disagrees with git, git wins.
   Correct the summary out loud.
5. **State the board back** to the Producer in five lines before doing
   anything else.

---

## 3. Tickets

Template — copy it exactly; every section exists for a reason:

```
TICKET M<n>-T<n.m> — <title>
GOAL: one or two sentences. Outcome, not activity.
BRANCH: m<n>/<slug> — push, open PR, never touch main.
FILES: every file allowed to change. Mark "new". List the tests.
SPEC: the doc sections this implements (PROTOCOL §x, ARCHITECTURE §y, ADR-nnn).
NOTES (Architect rulings): every decision the implementer would otherwise
  have to guess. If a question could come back as BLOCKED, answer it here.
ACCEPTANCE: executable where possible — byte fixtures, exact test names,
  "rooms_smoke.js green" — plus the Producer's manual pass, spelled out.
OUT OF SCOPE: what must show ZERO diff.
IF IT BALLOONS: the seam to split at, and what DONE-PARTIAL looks like.
```

Rules of thumb:

- **Spec before ticket.** If the work needs a wire or rule change, edit
  `PROTOCOL.md` / `ARCHITECTURE.md` first, have the Producer commit it, then
  write the ticket against the *committed* spec (PROTOCOL §8 change control).
- **Rulings live in NOTES.** The implementer never improvises design. The
  cost of a missing ruling is a BLOCKED report or a wrong guess — both cost
  more than the sentence would have.
- **Lean on purpose.** The seat pays tokens to read every line. Teaching the
  Producer belongs in chat, not in the ticket.
- **One session's work.** If you can't picture it finishing in one
  implementation session, split it now, not later.
- **Name the trap.** Every ticket has the one place it will crash (a copyWith
  null, a camera lifecycle, a keyring, a stale base). Say it out loud.
- **Tickets are files.** `tickets/M<n>-T<n.m>.md`, committed before the
  session. The entire prompt to the seat is: *Work tickets/<id>.md*. This
  is how "I pasted the wrong ticket" became impossible.

---

## 4. Review

Every PR, every time, in this order. Never skip a step because the report
looks good — the two worst incidents in this repo were reports that looked
good.

1. **Fresh clone**, check out the branch.
2. **Commits:** `git log --oneline main..<branch>` — conventional messages;
   count matches the report.
3. **Footprint:** `git diff --stat main...<branch>` — must match the report's
   CHANGED line to the digit. Any extra file needs a ruling.
4. **Forbidden paths** (from the ticket's OUT OF SCOPE):
   `git diff main...<branch> -- <paths>` must print nothing.
5. **Base drift:** `git diff --name-only $(git merge-base main <branch>)..main`
   — every file listed that the branch also touches is a merge conflict
   waiting. If non-empty, say so *before* the Producer clicks.
6. **Leaf-layer purity:** `grep -n "^import" lib/game/*.dart lib/media/*.dart`
   — `dart:core` / `dart:io` only, ever.
7. **Execute what you can.** `node skate_signaling_server/test/rooms_smoke.js`
   is self-contained (own relay on port 8129, `GRACE_MS=200`) — run it
   yourself. You cannot run Flutter; the Producer runs
   `flutter analyze && flutter test` before every merge, without exception.
8. **Read the risky files in full** (server, codec, state); grep the rest for
   the ticket's named traps.
9. **Rule on every FLAG explicitly** — approve, change, or defer. An
   unanswered flag is a decision made by accident.
10. **Format-only proof**, when a file "shouldn't have changed": compare
    `tr -d ' \t\n,' | md5sum` of both versions. Identical means `dart format`
    only.

Verdict vocabulary: **MERGE** · **MERGE after addendum** (one small specified
change on the same branch) · **CHANGE REQUESTS** (a list) · **BLOCKED**
(needs a spec decision first).

Then the Producer: runs the checks, **retargets the PR base to `main` if the
seat stacked it on another branch**, and clicks merge. Nothing lands on main
without that click.

---

## 5. Closing a milestone

Ceremony never precedes substance. In order:

1. **Certify:** `git log main..<branch>` prints nothing for *every* branch of
   the milestone.
   - After a rebase/squash merge, certify by content — `git diff
     origin/<branch> main -- <ticket FILES>` must be empty — then delete the
     branch; unswept rebase-merged branches read as unmerged forever.
2. **Manual acceptance** from `ROADMAP.md` passed on real devices.
3. **Close-out docs commit:** ADR amendments, CHANGELOG release section,
   survival-guide scars.
4. **Tag:** `git tag v0.<n>.0 && git push origin v0.<n>.0`
5. **Flip** the "Current focus" line in `GEMINI.md`.
6. **Sweep** merged branches; close zombie PRs (**close — never resolve** an
   old PR's conflicts; the stale text would overwrite current spec).
7. **Open a new Architect window** for the next milestone and regenerate the
   project snapshot: `tools/snapshot_docs.sh`.

*Tags celebrate merges; they don't replace them.* v0.4.0 was tagged while
T2.3 sat unmerged. That is why this list exists.

---

## 6. Rulings register (standing rulings that are not yet ADRs)

- **The spec wins.** If code and `PROTOCOL.md` disagree, the code is wrong —
  even when the Architect's own review missed it.
- **Facts on the wire, never conclusions** (ADR-003). Timers are advisory;
  a timeout never acts; turn state is derived.
- **Letters key to `playerId`**, never to a seat/role.
- **Explicit clear flags** for nullable state (`clearTrick: true`);
  `?? this.x` cannot express "clear it".
- **Leaf layers** (`lib/game`, `lib/media`) import `dart:core`/`dart:io`
  only. Platform bridges live one layer up and *inject* what the leaf needs.
- **Network-driven UI transitions** are phase-driven from the root widget;
  user-driven flows (record, replay) may use `Navigator`.
- **Zero engine diffs** unless the ticket names the engine.
- **New dependencies** need Producer approval, recorded in an ADR or the
  report; the rider governing *where* they're imported travels with it.
- **No room codes in shareable text** — rooms die; dead links are jank.
- **Server constants clients need are announced on the wire**
  (`graceSeconds`), never hardcoded on both sides.
- **Anyone holding a room code may claim a vacant graced seat** (trust
  model) — until ranked exists, which changes the trust model entirely.
- **Ranked requires live-witnessed attempts.** A recorded clip never proves
  one attempt; you cannot prove a negative.

---

## 7. Scars → rules (pipeline-level)

| Scar | Rule it produced |
|---|---|
| Server directory committed as a submodule pointer; only copy was one laptop | Check for stray `.git` folders before adding a directory |
| v0.4.0 tagged while T2.3 sat unmerged | §5 order: certify → tag, never the reverse |
| Two branches cut from a stale local main → surprise conflicts | Review step 5; CLAUDE.md "branch from freshly pulled main" |
| Reports lost to the clipboard, twice | `reports/<id>.md` committed with the ticket |
| Wrong ticket pasted from scrollback | Tickets are files; the prompt is a path |
| Approval prompt answered while alt-tabbed | Answer prompts with eyes on them, then tab away |
| "Replace the `connect` method" swallowed two other methods | Give a tired human whole files or exact anchors, never "replace X" |
| `git push.` → divergence → strategy prompt at midnight | `git pull --rebase` for local-only commits; `git config --global pull.rebase true` |

---

## 8. Producer session preflight (four lines, every session)

```bash
git checkout main && git pull      # branch from truth, not from yesterday
git status                         # clean? if not, stop and look
cat tickets/<id>.md                # is this the right ticket?
claude                             # Shift+Tab → manual mode to learn; auto mode is fine when tired
```
