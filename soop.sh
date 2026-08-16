#!@bash@
set -euo pipefail

export PATH="@runtimePath@${PATH:+:$PATH}"

readonly SITE_URL="https://www.sooplive.com/"
readonly GRID_BIN="@gridBin@"
readonly CHROMIUM_BIN="@chromiumBin@"

usage() {
  cat <<'EOF'
Usage: soop

Starts the SOOP viewer grid agent and opens SOOP in a dedicated Chromium app.
Only one integrated SOOP instance may run at a time.
EOF
}

if (($# > 0)); then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'soop: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

: "${HOME:?soop requires HOME to be set}"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
data_root="$data_home/soop"
profile_dir="$data_root/chromium"
cache_dir="$cache_home/soop/chromium"
runtime_root="${XDG_RUNTIME_DIR:-$data_root/runtime}/soop"

umask 077
mkdir -p "$profile_dir" "$cache_dir" "$runtime_root"

exec 8>"$runtime_root/app.lock"
if ! flock -n 8; then
  printf 'SOOP is already running.\n'
  exit 0
fi

if "$GRID_BIN" --status >/dev/null 2>&1; then
  printf 'soop: a standalone SOOP grid session is already running.\n' >&2
  exit 1
fi

grid_pid=""
browser_job_pid=""
grid_owned=0
ready_file="$runtime_root/grid-ready.$$"
rm -f "$ready_file"

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM HUP
  rm -f "$ready_file"

  if [[ -n "$browser_job_pid" ]]; then
    kill -TERM "$browser_job_pid" 2>/dev/null || true
    wait "$browser_job_pid" 2>/dev/null || true
  fi

  if [[ -n "$grid_pid" ]]; then
    kill -TERM "$grid_pid" 2>/dev/null || true
    wait "$grid_pid" 2>/dev/null || true
  fi

  if ((grid_owned)) && ! "$GRID_BIN" --stop >/dev/null 2>&1; then
    printf 'soop: the grid agent did not stop cleanly.\n' >&2
    exit_status=1
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP

"$GRID_BIN" \
  --parent-pid "$$" \
  --ready-file "$ready_file" \
  8>&- &
grid_pid=$!

grid_ready=0
for _ in {1..900}; do
  if [[ "$(jobs -pr)" != "$grid_pid" ]]; then
    wait "$grid_pid" 2>/dev/null || true
    grid_pid=""
    break
  fi
  if [[ -f "$ready_file" ]]; then
    ready_pid=""
    read -r ready_pid <"$ready_file" || true
    if [[ "$ready_pid" == "$grid_pid" ]]; then
      grid_ready=1
      grid_owned=1
      break
    fi
  fi
  sleep 0.1
done

if ((!grid_ready)); then
  printf 'soop: the grid agent did not become ready.\n' >&2
  exit 1
fi

run_browser() {
  local owner_pid="$1"
  local chromium_pid=""

  # shellcheck disable=SC2329 # Invoked by the EXIT trap in this subprocess.
  cleanup_browser() {
    local browser_status=$?
    trap - EXIT INT TERM HUP

    if [[ -n "$chromium_pid" ]]; then
      kill -TERM "$chromium_pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$chromium_pid" 2>/dev/null || true
      wait "$chromium_pid" 2>/dev/null || true
    fi

    exit "$browser_status"
  }

  trap cleanup_browser EXIT
  trap 'exit 0' INT TERM HUP

  "$CHROMIUM_BIN" \
    --user-data-dir="$profile_dir" \
    --disk-cache-dir="$cache_dir" \
    --app="$SITE_URL" \
    --class=SOOP \
    --disable-background-mode \
    --no-first-run \
    --no-default-browser-check \
    8>&- &
  chromium_pid=$!

  while [[ "$(jobs -pr)" == "$chromium_pid" ]]; do
    if ! kill -0 "$owner_pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done

  set +e
  wait "$chromium_pid"
  browser_status=$?
  set -e
  chromium_pid=""
  return "$browser_status"
}

# This subprocess keeps app.lock until Chromium is gone if the parent is killed.
run_browser "$$" &
browser_job_pid=$!

finished_pid=""
set +e
wait -n -p finished_pid "$browser_job_pid" "$grid_pid"
wait_status=$?
set -e

if [[ "$finished_pid" == "$browser_job_pid" ]]; then
  browser_job_pid=""
else
  grid_pid=""
  printf 'soop: the grid agent stopped while the app was open.\n' >&2
  wait_status=1
fi

exit "$wait_status"
