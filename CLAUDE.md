# skate_p2p — Claude Code standing orders

Read `GEMINI.md` at the repo root before doing anything — it is your
standing orders (shared by all Programmer seats). Then read the docs it
points to. Additions specific to this seat:

- Work on the branch named in the ticket. NEVER commit or push to `main`.
- Run `flutter analyze && flutter test` before EVERY commit. A commit
  with failing checks is a broken commit, even mid-ticket.
- Node relay changes: run `node skate_signaling_server/test/rooms_smoke.js`
  before committing server work.
- End every session with the five-line report from `docs/WORKFLOW.md §4`,
  including the GitHub compare/PR link.
