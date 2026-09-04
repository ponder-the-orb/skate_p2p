# skate_p2p — Claude Code standing orders

Read `GEMINI.md` at the repo root before doing anything — it is your
standing orders (shared by all Programmer seats). Then read the docs it
points to. Additions specific to this seat:

- **Branch from a freshly pulled `main`** (`git checkout main && git pull`
  first) unless the ticket names a different base. Never stack on another
  ticket branch on your own initiative; if you must, say so in FLAGS and set
  the PR base accordingly.
- Work on the branch named in the ticket. NEVER commit or push to `main`.
- Run `flutter analyze && flutter test` before EVERY commit. A commit with
  failing checks is a broken commit, even mid-ticket.
- Node relay changes: run `node skate_signaling_server/test/rooms_smoke.js`
  (self-contained) before committing server work.
- New dependencies need Producer approval. If a ticket's scope needs one it
  didn't list, stop and ask with options — never add it silently, never
  block silently.
- End every session with the five-line report from `docs/WORKFLOW.md §4`,
  including the PR link, and every judgment call listed under FLAGS.
- In addition to printing it, write the five-line report to
  `reports/<ticket-id>.md` and include it in the ticket's final commit.
  Reports live in the repo; clipboards lose things.
- Open the PR with `gh pr create` against `main`. If `gh` is unauthenticated,
  say so in FLAGS and provide the compare link.
