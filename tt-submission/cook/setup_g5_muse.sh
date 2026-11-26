#!/usr/bin/env bash
# setup_g5_muse.sh — one-shot setup for the sha256-miner closure cook on
# the owner's Dell G5 SE 5505 (bare-metal Ubuntu). _muse, 2026-11-26.
#
# AUTHOR: Ember (Muse), executing agent
# AUTHORITY: Branden Algozino's request of 2026-11-26: "make a script to
#   get it set up on my G5 and then put it on GitHub."
# EVIDENCE: the cook package beside this script (config_cook_muse.json,
#   run_cook.sh, README_muse.md) and the LibreLane 3.0.17 package source
#   in Ember's sandbox venv, specifically:
#   - librelane/__main__.py: the container image a LibreLane 3.0.17
#     install uses for itself is ghcr.io/librelane/librelane:3.0.17
#     (the ":{__version__}" default, LIBRELANE_IMAGE_OVERRIDE aside).
#   - librelane/pdk_hashes.yaml: the sky130 PDK revision LibreLane
#     3.0.17 pins is 8afc8346a57fe1ab7934ba5a6056ea8b43078e71.
#   - librelane/flows/cli.py: with the default --ciel-pdk, a run named
#     "--pdk sky130A" fetches that pinned PDK via ciel if it is missing.
# REQUESTED_ACTION: On the G5, once this repo is cloned (this script
#   clones it for you if it is not — see below):
#     bash ~/sha256-miner/tt-submission/cook/setup_g5_muse.sh
#     bash ~/sha256-miner/tt-submission/cook/setup_g5_muse.sh --cook
#   The first form sets everything up, smoke-checks it, and prints the
#   cook command. The second also runs the cook straight after a fully
#   passing smoke check. Safe to re-run either way.
#
# ROUTE, AND WHY (the one place this script could be wrong, stated):
#   A pip install of LibreLane does NOT bundle the OpenROAD binary —
#   Ember's sandbox is the standing proof (LibreLane 3.0.17 and the PDK
#   present, no OpenROAD obtainable there). OpenROAD therefore comes
#   from the official container image named above, which is also the
#   route run_cook.sh probes for. Two consequences, handled below:
#   - run_cook.sh names the image ":latest". This script pulls the
#     pinned ":3.0.17" and locally tags it as ":latest", so the cook
#     runs exactly the version config_cook_muse.json was checked
#     against. The tag is local-only, and the script says so out loud
#     when it applies it.
#   - The host also gets a pip venv (~/librelane-venv) with the same
#     pinned LibreLane, used to pre-fetch the pinned sky130 PDK via
#     ciel and for version checks. Note the container cook downloads
#     the PDK inside the container on each run (run_cook.sh mounts
#     only the design tree); the host copy stays on disk for
#     inspection and for any future native route.
#
# This script never touches wallet material: the public repo contains
# no wallet directory (it is gitignored and was never committed) and
# nothing here reads, writes or references one. No purchases, no
# shuttle or foundry submissions, no accounts — setup only.

set -euo pipefail

LIBRELANE_VERSION="3.0.17"
IMAGE_PINNED="ghcr.io/librelane/librelane:${LIBRELANE_VERSION}"
IMAGE_LATEST="ghcr.io/librelane/librelane:latest"
SKY130_REV="8afc8346a57fe1ab7934ba5a6056ea8b43078e71"
REPO_URL="https://github.com/softnessasastrength/sha256-miner.git"
CLONE_DIR="${HOME}/sha256-miner"
VENV_DIR="${HOME}/librelane-venv"
COOK_DIR_REL="tt-submission/cook"

RUN_COOK=0
case "${1:-}" in
  "") ;;
  --cook) RUN_COOK=1 ;;
  *) echo "usage: bash setup_g5_muse.sh [--cook]" >&2; exit 2 ;;
esac

say()  { printf '\n== %s ==\n' "$*"; }
note() { printf '   %s\n' "$*"; }
warn() { printf '   WARNING: %s\n' "$*" >&2; }

# ---------------------------------------------------------------- machine
say "Machine check"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  note "OS: ${PRETTY_NAME:-unknown}"
  if [ "${ID:-}" != "ubuntu" ]; then
    warn "this script was written for Ubuntu; proceeding anyway"
  fi
else
  warn "cannot read /etc/os-release; proceeding anyway"
fi

MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
MEM_GB=$(( MEM_KB / 1024 / 1024 ))
note "RAM: ${MEM_GB} GB"
if [ "$MEM_GB" -lt 16 ]; then
  warn "less than 16 GB RAM — the cook may swap or run out of memory"
fi

DISK_KB="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
DISK_GB=$(( DISK_KB / 1024 / 1024 ))
note "Free disk on the home volume: ${DISK_GB} GB"
if [ "$DISK_GB" -lt 30 ]; then
  warn "less than 30 GB free — image, PDK and run outputs need room"
fi

# ------------------------------------------------------------ apt prereqs
say "Prerequisites (apt)"
MISSING=()
command -v git     >/dev/null 2>&1 || MISSING+=(git)
command -v curl    >/dev/null 2>&1 || MISSING+=(curl)
command -v python3 >/dev/null 2>&1 || MISSING+=(python3)
python3 -m venv --help >/dev/null 2>&1 || MISSING+=(python3-venv)
if [ "${#MISSING[@]}" -gt 0 ]; then
  note "installing: ${MISSING[*]}"
  sudo apt-get update
  sudo apt-get install -y "${MISSING[@]}"
else
  note "git, curl, python3 and python3-venv already present"
fi

# ----------------------------------------------------------------- docker
say "Docker (the OpenROAD route)"
NEED_RELOGIN=0
if ! command -v docker >/dev/null 2>&1; then
  note "docker not found — installing docker.io"
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker || warn "could not start the docker service"
fi
CURRENT_USER="$(id -un)"
if ! id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx docker; then
  note "adding ${CURRENT_USER} to the docker group"
  sudo usermod -aG docker "$CURRENT_USER"
  NEED_RELOGIN=1
fi
docker info >/dev/null 2>&1 || sudo systemctl start docker || true
if ! docker info >/dev/null 2>&1; then
  if [ "$NEED_RELOGIN" -eq 1 ]; then
    say "One step needs you"
    note "You were just added to the docker group, and that only takes"
    note "effect at your next login. Log out and back in (or reboot),"
    note "then re-run this script — it picks up where it left off."
    exit 0
  fi
  warn "docker is installed but the daemon is not answering."
  warn "check: sudo systemctl status docker — then re-run this script."
  exit 1
fi
note "docker is up: $(docker --version)"

# -------------------------------------------------------------- repository
say "Repository"
if [ -d "${CLONE_DIR}/.git" ]; then
  note "clone already at ${CLONE_DIR} — pulling"
  git -C "$CLONE_DIR" pull --ff-only
elif [ -e "$CLONE_DIR" ]; then
  warn "${CLONE_DIR} exists but is not a git clone — refusing to touch it."
  warn "move it aside and re-run, or clone the repo there yourself."
  exit 1
else
  git clone "$REPO_URL" "$CLONE_DIR"
fi

# ------------------------------------------------- LibreLane venv + ciel
say "LibreLane ${LIBRELANE_VERSION} (pip venv — PDK and version checks)"
if [ -x "${VENV_DIR}/bin/librelane" ] \
  && "${VENV_DIR}/bin/librelane" --version 2>/dev/null | grep -q "v${LIBRELANE_VERSION}"; then
  note "venv already has LibreLane ${LIBRELANE_VERSION} — skipping install"
else
  python3 -m venv "$VENV_DIR"
  "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
  "${VENV_DIR}/bin/pip" install "librelane==${LIBRELANE_VERSION}"
fi
"${VENV_DIR}/bin/librelane" --version | head -1

say "sky130 PDK (ciel, pinned revision)"
ENABLED="$("${VENV_DIR}/bin/ciel" output --pdk sky130 2>/dev/null || true)"
if [ "$ENABLED" = "$SKY130_REV" ]; then
  note "pinned revision already enabled: ${SKY130_REV}"
else
  if ! "${VENV_DIR}/bin/ciel" enable --pdk sky130 "$SKY130_REV"; then
    warn "could not enable the pinned revision ${SKY130_REV}"
    FALLBACK_REV="$("${VENV_DIR}/bin/ciel" ls-remote --pdk sky130 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1 || true)"
    if [ -n "$FALLBACK_REV" ] && [ "$FALLBACK_REV" != "$SKY130_REV" ]; then
      warn "falling back to the newest listed revision: ${FALLBACK_REV}"
      "${VENV_DIR}/bin/ciel" enable --pdk sky130 "$FALLBACK_REV" || \
        warn "fallback enable also failed — LibreLane will fetch the PDK itself at cook time"
    else
      warn "no fallback revision found — LibreLane will fetch the PDK itself at cook time"
    fi
  fi
  ENABLED="$("${VENV_DIR}/bin/ciel" output --pdk sky130 2>/dev/null || true)"
fi
if [ -n "$ENABLED" ]; then
  note "ciel reports enabled sky130 version: ${ENABLED}"
else
  warn "ciel reports no enabled sky130 version"
fi

# ------------------------------------------------------------ docker image
say "Container image (pinned ${IMAGE_PINNED})"
docker pull "$IMAGE_PINNED"
PINNED_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE_PINNED")"
LATEST_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE_LATEST" 2>/dev/null || echo none)"
if [ "$PINNED_ID" != "$LATEST_ID" ]; then
  note "run_cook.sh names ${IMAGE_LATEST} — tagging the pinned"
  note "${LIBRELANE_VERSION} image under that name LOCALLY, so the cook"
  note "runs exactly the version the config was checked against."
  docker tag "$IMAGE_PINNED" "$IMAGE_LATEST"
else
  note "${IMAGE_LATEST} already resolves to the pinned image"
fi

# ------------------------------------------------------------- smoke check
say "Smoke check"
PASS=0
FAIL=0
check() { # check <label> <0=pass|1=fail> [detail]
  if [ "$2" -eq 0 ]; then
    note "PASS  $1${3:+ — $3}"
    PASS=$((PASS + 1))
  else
    note "FAIL  $1${3:+ — $3}"
    FAIL=$((FAIL + 1))
  fi
}

OUT="$(docker run --rm "$IMAGE_PINNED" librelane --version 2>/dev/null || true)"
if [ -z "$OUT" ]; then
  OUT="$(docker run --rm --entrypoint librelane "$IMAGE_PINNED" --version 2>/dev/null || true)"
fi
case "$OUT" in
  *"v${LIBRELANE_VERSION}"*) check "LibreLane in container" 0 "$(printf '%s' "$OUT" | head -1)" ;;
  *) check "LibreLane in container" 1 "no version string came back" ;;
esac

OUT="$(docker run --rm "$IMAGE_PINNED" openroad -version 2>/dev/null || true)"
if [ -z "$OUT" ]; then
  OUT="$(docker run --rm --entrypoint openroad "$IMAGE_PINNED" -version 2>/dev/null || true)"
fi
if [ -n "$OUT" ]; then
  check "OpenROAD in container" 0 "$(printf '%s' "$OUT" | head -1)"
else
  check "OpenROAD in container" 1 "openroad did not answer inside the image"
fi

if "${VENV_DIR}/bin/librelane" --version 2>/dev/null | grep -q "v${LIBRELANE_VERSION}"; then
  check "LibreLane in host venv" 0 "${VENV_DIR}"
else
  check "LibreLane in host venv" 1 "venv missing or wrong version"
fi

CIEL_HOME="$("${VENV_DIR}/bin/python" -c 'import ciel; print(ciel.get_ciel_home(None))' 2>/dev/null || echo "${HOME}/.ciel")"
PDK_DIR="$(find "$CIEL_HOME" -maxdepth 6 -type d -name sky130A 2>/dev/null | head -1 || true)"
if [ -n "$PDK_DIR" ] && [ -d "$PDK_DIR" ]; then
  check "sky130A PDK on host" 0 "$PDK_DIR"
else
  check "sky130A PDK on host" 1 "not found under ${CIEL_HOME}"
fi

if [ -f "${CLONE_DIR}/${COOK_DIR_REL}/run_cook.sh" ] \
  && [ -f "${CLONE_DIR}/${COOK_DIR_REL}/config_cook_muse.json" ]; then
  check "Cook package in clone" 0 "${CLONE_DIR}/${COOK_DIR_REL}"
else
  check "Cook package in clone" 1 "run_cook.sh or config missing in ${CLONE_DIR}/${COOK_DIR_REL}"
fi

# ---------------------------------------------------------------- summary
say "Summary"
note "smoke check: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  note "setup is INCOMPLETE — fix the FAIL lines above and re-run this"
  note "script; it is safe to re-run and skips what is already done."
  exit 1
fi
note "ready: repo at ${CLONE_DIR}"
note "ready: LibreLane ${LIBRELANE_VERSION} (venv ${VENV_DIR}, image ${IMAGE_PINNED})"
note "ready: sky130 PDK via ciel${ENABLED:+ (enabled version ${ENABLED})}"

if [ "$RUN_COOK" -eq 1 ]; then
  say "Running the cook"
  cd "${CLONE_DIR}/${COOK_DIR_REL}"
  RC=0
  bash run_cook.sh || RC=$?
  note "cook exit code: ${RC} — its full log is under ${COOK_DIR_REL}/logs/ in the clone"
  note "report the run exactly as it landed: final overflow, antenna and"
  note "setup/hold violation counts, GDS / DRC / LVS status, each stated plainly."
  exit "$RC"
fi

note "next command, when you want the cook:"
note "  cd ${CLONE_DIR}/${COOK_DIR_REL} && chmod +x run_cook.sh && ./run_cook.sh"
note "(or re-run this script with --cook and it runs right after the checks)"
