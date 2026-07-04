#!/usr/bin/env bash
# Propagator: materialize the fork CI into every syncing fork.
# For each core in Forks.ini it pushes into the fork:
#   .github/notify_error.sh          (shared, from fork_ci_template)
#   .github/workflows/upstream.yml   (shared, from fork_ci_template)
#   .github/copy.bara.sky            (per-core, from cores/<Core>/)
#   .github/upstream_patches/*       (per-core, from cores/<Core>/upstream_patches/)
#
# Requires: gh (authenticated, workflow scope), git, python3. Env: GH_TOKEN.
# Pass --dry-run to build the payload locally without pushing.
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INI="$HERE/Forks.ini"
TEMPLATE="$HERE/fork_ci_template/.github"

cores_and_repos() {
  python3 - "$INI" <<'PY'
import configparser, sys
c = configparser.ConfigParser()
c.read(sys.argv[1])
for core in c["Forks"].get("SYNCING_FORKS", "").split():
    s = c[core]
    print(core, s["FORK_REPO"], s.get("MAIN_BRANCH", "master"))
PY
}

slug() { sed -E 's#^https://github.com/##; s/\.git$//' <<<"$1"; }

while read -r CORE FORK_REPO BRANCH; do
  [ -n "${CORE:-}" ] || continue
  SRC="$HERE/cores/$CORE"
  if [ ! -f "$SRC/copy.bara.sky" ]; then
    echo "[$CORE] cores/$CORE/copy.bara.sky missing; skipping" >&2
    continue
  fi
  WORK="$(mktemp -d)"
  echo "[$CORE] materializing into $(slug "$FORK_REPO")@$BRANCH"
  git clone --depth 1 --branch "$BRANCH" \
    "https://x-access-token:${GH_TOKEN}@github.com/$(slug "$FORK_REPO").git" "$WORK/repo" 2>/dev/null \
    || { echo "[$CORE] clone failed" >&2; rm -rf "$WORK"; continue; }

  DST="$WORK/repo/.github"
  mkdir -p "$DST/workflows" "$DST/upstream_patches"
  cp "$TEMPLATE/notify_error.sh"        "$DST/notify_error.sh"
  cp "$TEMPLATE/workflows/upstream.yml" "$DST/workflows/upstream.yml"
  cp "$SRC/copy.bara.sky"               "$DST/copy.bara.sky"
  rm -f "$DST"/upstream_patches/*.patch 2>/dev/null || true
  if compgen -G "$SRC/upstream_patches/*.patch" >/dev/null; then
    cp "$SRC"/upstream_patches/*.patch "$DST/upstream_patches/"
  fi

  ( cd "$WORK/repo"
    git add .github
    if git diff --cached --quiet; then
      echo "[$CORE] already up to date"
    elif [ "$DRY" = "1" ]; then
      echo "[$CORE] --dry-run: would commit:"; git diff --cached --stat
    else
      git -c user.name="openfpga-mister-bot" -c user.email="bot@openfpga-mister" \
        commit -m "BOT: sync fork CI/CD from Forks_openFPGA"
      git push origin "$BRANCH"
      echo "[$CORE] pushed"
    fi
  )
  rm -rf "$WORK"
done < <(cores_and_repos)
