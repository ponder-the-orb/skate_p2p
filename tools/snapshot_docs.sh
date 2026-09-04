#!/usr/bin/env bash
# Regenerates the Claude Project knowledge file from the repo's docs.
# Run at every milestone close (docs/ARCHITECT.md §5), then upload the
# output to the skate_p2p Project, replacing the previous snapshot.
#
# Usage:  tools/snapshot_docs.sh > project_snapshot.md
set -euo pipefail
cd "$(dirname "$0")/.."

echo "# skate_p2p — Project knowledge snapshot"
echo
echo "Generated $(date -u +%Y-%m-%d) from commit $(git rev-parse --short HEAD) on branch $(git rev-parse --abbrev-ref HEAD)."
echo "Tags: $(git tag | tr '\n' ' ')"
echo
echo "> **The repo is canonical.** This file is a convenience for a fresh chat"
echo "> window. If anything here disagrees with the repo, the repo wins —"
echo "> clone it and certify per docs/ARCHITECT.md §2 before trusting this."
echo

for f in CLAUDE.md GEMINI.md docs/ARCHITECT.md docs/WORKFLOW.md docs/ROADMAP.md \
         docs/STRATEGY.md docs/DEV_SETUP.md docs/ARCHITECTURE.md docs/PROTOCOL.md; do
  if [ -f "$f" ]; then
    echo
    echo "=============================================================================="
    echo "=== $f"
    echo "=============================================================================="
    echo
    cat "$f"
  fi
done

echo
echo "=============================================================================="
echo "=== Latest reports"
echo "=============================================================================="
ls -1t reports/*.md 2>/dev/null | head -3 | while read -r r; do
  echo; echo "--- $r"; cat "$r"
done
