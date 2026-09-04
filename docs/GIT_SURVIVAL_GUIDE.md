+------------------------------------------------------------------------------+
|   S K A T E _ P 2 P   ::   G I T   S U R V I V A L   G U I D E               |
|                              v1.2 - The Camper Edition                       |
+------------------------------------------------------------------------------+

================================================================================
[ 1 ] THE DAILY WORKFLOW (PACK & SHIP)
================================================================================
When you've finished writing code and want to save a permanent snapshot:

> git status
  Check the board. Shows modified/new files (Red = Unpacked, Green = Packed).

> git diff
  Read every line BEFORE you stage anything. This is the step that catches
  "wait, why is a Flutter template file showing up in here" before it's
  too late to matter.

> git add <specific files>
  The Loading Dock - but load it BY HAND. Stage only what you meant to
  change. Avoid 'git add .' until you've actually read 'git status' and
  know exactly what's sitting in the pile. 'git add .' doesn't ask
  questions - it just grabs everything, including stray junk you never
  meant to commit.

> git diff --cached
  Read it AGAIN, now that it's staged. This is your last checkpoint
  before it becomes permanent history. Never skip this one.

> git commit -m "feat: short description of what you built"
  The Permanent Box. Locks the staged files into local history.

> git push origin <branch-name>
  The Delivery. Uploads your saved local commits up to GitHub.

================================================================================
[ 2 ] BRANCHING - HOW THIS STUDIO ACTUALLY SHIPS
================================================================================
Your own WORKFLOW.md says: one branch per milestone, PR into main,
Producer (that's you) clicks merge. Nothing lands on main without your
click. M0/M1 skipped this for speed - M2 is the big one, so use it:

> git checkout -b m2/protocol-v1
  New branch, switches you onto it immediately. main stays untouched.

  ... write code, commit as you go, same as Section 1 ...

> git push origin m2/protocol-v1
  Uploads the BRANCH, not main.

> [ on GitHub: click "Compare & pull request" ]
  This creates the PR. Paste the compare link to the Architect for review.

> [ on GitHub: click "Merge pull request" ]
  Only after you get a "merge" from review. This is the one and only
  door that lets code into main.

Generic branch commands, for reference:
> git checkout main            : back to the sacred timeline
> git branch -a                : list every branch, local + remote
> git merge feature/name       : merges locally - skip this for team work,
                                  use the GitHub PR button above instead

================================================================================
[ 3 ] HISTORY & AUDITING
================================================================================
> git log --oneline            : compact timeline, one line per commit
> git log -n 5                 : just the last 5 commits
> git diff                     : unstaged changes vs. the last commit
> git diff --cached            : STAGED changes vs. the last commit -
                                  the command you run right before every
                                  single commit, no exceptions

================================================================================
[ 4 ] THE VIM TRAP (IF YOU FORGET '-m' ON COMMIT)
================================================================================
If you type 'git commit' without '-m', Git opens Vim. Don't panic:
  1. Press  [ i ]    -> Enters -- INSERT -- mode.
  2. Type your commit message.
  3. Press  [ Esc ]  -> Exits insert mode.
  4. Type   [ :wq ]  -> (colon, w, q) Writes and Quits. Press [ ENTER ].

================================================================================
[ 5 ] EMERGENCY PANIC BUTTONS
================================================================================
> git restore --staged <file>  : UN-STAGE one file. Edits stay on disk,
                                  totally safe.
> git reset HEAD~1             : UNDO the last commit. Your edits come
                                  back as staged changes - nothing is lost.
> git restore .                : DISCARD unsaved edits to tracked files.
                                  Actually destructive - this one deletes
                                  real work, no undo.
> git clean -fd                : DELETE untracked new files/folders.
                                  'git restore .' does NOT touch these -
                                  you need this separately. Even more
                                  dangerous than the above; it doesn't ask
                                  twice. Run 'git clean -nd' first (dry
                                  run) to see what it WOULD delete.
> git stash                    : "I'm not done, but I need to switch
                                  branches right now." Shelves your edits,
                                  working tree goes clean.
> git stash pop                : Brings the shelved edits back.


> git checkout <branch>
 -- <file>                     : grabs one file from another branch, no merging involved.)

================================================================================
[ 6 ] NEW REPO / REMOTE SETUP (ONE-TIME)
================================================================================
> git init                     : turn a plain folder into a git repo
> git remote add origin <url>  : point a local repo at a GitHub repo
> git clone <url>               : download an existing repo + full history

================================================================================
[ 7 ] SCARS - THINGS THAT ACTUALLY BIT US IN skate_p2p
================================================================================
- skate_signaling_server had its OWN .git folder inside it. Git silently
  recorded it as a submodule POINTER instead of real files. Every commit
  after that looked totally normal locally but pushed nothing - the
  server code lived only on one laptop for two whole tickets.
  Lesson: a folder with a .git inside it is a trap. 'git status' will
  not warn you. Check for stray .git folders before you ever commit a
  new directory.

- 'git add .' once staged a Flutter-generated test/widget_test.dart
  that had nothing to do with this project - it would've broken CI
  the moment we set it up.
  Lesson: this is exactly why Section 1 now makes you read
  'git diff --cached' before every commit. It's the only step that
  actually catches this kind of thing.

- The repo went public for a code review, and an old commit (a large
  stray file) stayed fully visible in history even after a later
  commit "removed" it.
  Lesson: deleting a file in a new commit does NOT erase it from
  history - anyone can still dig it out of an old commit. If anything
  sensitive ever lands in a commit, that's a bigger problem than a
  normal revert, and it's worth asking before pushing again.

- v0.4.0 got tagged while m2/polish sat unmerged — the ceremony (tag,
  docs flip) ran ahead of the substance (the merge). Lesson: a milestone
  is not closed until `git log main..<branch>` prints NOTHING for every
  branch of that milestone. Tags celebrate merges; they don't replace them.
