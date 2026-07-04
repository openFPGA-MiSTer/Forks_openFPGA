# Forks_openFPGA

Orchestrator for the **openFPGA-MiSTer** org: a fleet of forked openFPGA (Analogue
Pocket) cores kept automatically updated to their upstream **MiSTer** RTL.

Same operating policy as [MiSTer-DB9/Forks_MiSTer](https://github.com/MiSTer-DB9):
scheduled auto-sync on two channels (stable and unstable), failure logging to Telegram,
central config, and a template propagated to every fork.

## Why this is not a plain `git merge` (like DB9 is)

DB9 forks are direct forks of `MiSTer-devel/<Core>_MiSTer`, so MiSTer is a git remote
and each sync is a 3-way `git merge` (rerere replays recurring conflict resolutions).

openFPGA cores are different: the MiSTer core is a **vendored, transformed copy** inside
the port tree (CRLF to LF normalized, path-reorged, hand-patched). There is no MiSTer git
history in the tree, so "update to MiSTer" is a **vendoring refresh**, not a merge. The
right tool is **[Copybara](https://github.com/google/copybara)**: pull MiSTer, apply
transforms, reapply the fork's local patches, open a PR. The role of `git rerere` is
served by Copybara's `patch.apply`. A patch that stops applying (upstream changed that
region) is the failure signal that fires Telegram, and a human refreshes the `.patch`.

## Scope

Only cores that vendor the MiSTer RTL **verbatim** can be auto-synced:

| Core | Upstream MiSTer | Vendored path | Notes |
|------|-----------------|---------------|-------|
| NES  | `NES_MiSTer`  | `rtl/upstream/` | LF sources, 4 patches (agg23's proven config) |
| SNES | `SNES_MiSTer` | `rtl/`          | CRLF sources (CR-strip), 7 patches, fork-owned excludes |

Out of scope: **SMS, GBA, GBC**, which are restructured LLM-assisted ports with no 1:1
file mapping or recorded MiSTer provenance. They would have to be re-vendored verbatim
first.

## Layout

```
Forks.ini                       # fleet config, one [<Core>] section per fork
cores/<Core>/
  copy.bara.sky                 # per-core Copybara config (dual: unstable + stable)
  upstream_patches/*.patch      # fork-local deltas reapplied on top of upstream
fork_ci_template/.github/
  notify_error.sh               # Telegram alert (from DB9)
  workflows/upstream.yml        # spoke workflow (podman copybara + Telegram on failure)
.github/
  sync_dispatch.sh              # resolve upstream ref per channel, dispatch each fork
  setup_cicd.sh                 # materialize template + per-core config into each fork
  workflows/
    sync_unstable.yml           # cron 06,18 UTC, dispatch --unstable (MiSTer HEAD)
    sync_stable.yml             # cron 18 UTC, dispatch --stable (latest release commit)
    setup_cicd.yml              # on push, propagate to forks
```

## Channels

- **unstable**: tracks MiSTer `master` HEAD. Copybara ref left empty (defaults to HEAD).
- **stable**: tracks the latest MiSTer release commit (last commit touching `releases/`).
  The dispatcher resolves it and passes it as the Copybara source ref.

Each produces its own PR branch on the fork (`vendor/upstream-sync` and
`vendor/upstream-sync-stable`); a maintainer reviews and merges.

## Secrets (org-level)

| Secret | Used by | Purpose |
|--------|---------|---------|
| `REPOSITORY_DISPATCH_TOKEN` | hub | run workflows on the forks; propagate CI |
| `CUSTOM_GH_TOKEN`           | fork | checkout and open PRs that may touch `.github/` |
| `TELEGRAM_BOT_TOKEN`        | fork | failure alerts |
| `TELEGRAM_CHAT_ID`          | fork | failure alert destination |

## Onboarding a new verbatim core

1. Add a `[<Core>]` section to `Forks.ini` and to `SYNCING_FORKS`.
2. Author `cores/<Core>/copy.bara.sky` and `upstream_patches/` (classify each vendored
   file as verbatim, drift, fork-owned-exclude, or patch, following the SNES config).
3. Push; `setup_cicd.yml` materializes it into the fork.
4. Trigger `upstream.yml` on the fork (`workflow_dispatch`) and review the first PR.
