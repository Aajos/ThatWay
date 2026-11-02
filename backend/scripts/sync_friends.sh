#!/usr/bin/env bash
# The friends API is one tested module (backend/lambda/friends) deployed as five Lambdas. Each function directory holds an
# identical index.mjs and a copy of core.mjs so it can be zipped on its own. Run this after editing friends/core.mjs.
#   backend/scripts/sync_friends.sh          copy
#   backend/scripts/sync_friends.sh --check  exit 1 if any copy has drifted (used before a commit)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../lambda" && pwd)"
status=0
for fn in friendsSearch friendsRequest friendsRespond friendsList friendsRemove; do
  for f in index.mjs core.mjs; do
    if [ "${1:-}" = "--check" ]; then
      cmp -s "$ROOT/friends/$f" "$ROOT/$fn/$f" || { echo "drifted: $fn/$f"; status=1; }
    else
      cp "$ROOT/friends/$f" "$ROOT/$fn/$f"
    fi
  done
done
[ "${1:-}" = "--check" ] && { [ $status = 0 ] && echo "friends copies in step"; exit $status; }
echo "synced friends/{index,core}.mjs into the five function directories"
