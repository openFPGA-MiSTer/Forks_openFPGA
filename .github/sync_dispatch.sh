#!/usr/bin/env bash
# Hub dispatcher: for every fork in Forks.ini [Forks] SYNCING_FORKS, resolve the
# upstream MiSTer ref for the requested channel and trigger the fork's
# upstream.yml workflow.
#
#   sync_dispatch.sh --unstable   # dispatch with MiSTer master HEAD (ref left empty)
#   sync_dispatch.sh --stable     # dispatch with the latest MiSTer release commit
#
# Requires: gh (authenticated with a token that can run workflows on the forks),
# python3. Env: GH_TOKEN.
set -euo pipefail

CHANNEL=""
case "${1:-}" in
  --unstable) CHANNEL="unstable" ;;
  --stable)   CHANNEL="stable" ;;
  *) echo "usage: $0 --unstable|--stable" >&2; exit 2 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INI="$HERE/Forks.ini"

# Emit "CORE FORK_REPO UPSTREAM_MISTER_REPO" per syncing fork.
read_forks() {
  python3 - "$INI" <<'PY'
import configparser, sys
c = configparser.ConfigParser()
c.read(sys.argv[1])
cores = c["Forks"].get("SYNCING_FORKS", "").split()
for core in cores:
    s = c[core]
    print(core, s["FORK_REPO"], s["UPSTREAM_MISTER_REPO"])
PY
}

# owner/name from a github URL
slug() { sed -E 's#^https://github.com/##; s/\.git$//' <<<"$1"; }

# Latest MiSTer release commit = last commit touching releases/.
latest_release_commit() {
  local up_slug="$1"
  gh api "repos/${up_slug}/commits?path=releases&per_page=1" --jq '.[0].sha' 2>/dev/null || true
}

while read -r CORE FORK_REPO UP_REPO; do
  [ -n "${CORE:-}" ] || continue
  FORK_SLUG="$(slug "$FORK_REPO")"
  UP_SLUG="$(slug "$UP_REPO")"
  REF=""
  if [ "$CHANNEL" = "stable" ]; then
    REF="$(latest_release_commit "$UP_SLUG")"
    if [ -z "$REF" ]; then
      echo "[$CORE] no release commit resolved for $UP_SLUG; skipping stable dispatch" >&2
      continue
    fi
  fi
  echo "[$CORE] dispatch $CHANNEL -> $FORK_SLUG (ref='${REF:-HEAD}')"
  gh workflow run upstream.yml -R "$FORK_SLUG" \
    -f "channel=$CHANNEL" -f "ref=$REF" \
    || echo "[$CORE] dispatch failed" >&2
done < <(read_forks)
