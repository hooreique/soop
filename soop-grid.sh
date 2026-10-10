#!/usr/bin/env bash
set -euo pipefail

readonly SERVICE_GRACE_SECONDS=60

usage() {
  cat <<'EOF'
Usage: soop-grid [--status | --stop] [--parent-pid PID] [--ready-file PATH]

  --status          Report whether the private launcher owns a localhost listener
  --stop            Stop every Wine process in the private SOOP prefix
  --parent-pid PID  Stop when PID exits (used by the integrated SOOP app)
  --ready-file PATH Write readiness to PATH (used by the integrated SOOP app)
  --help            Show this help
EOF
}

launcher_pids() {
  local proc arg entry matched
  for proc in /proc/[0-9]*; do
    [[ -r "$proc/cmdline" && -r "$proc/environ" ]] || continue
    matched=0
    while IFS= read -r -d '' arg; do
      case "$arg" in
        */SOOPLiveLauncher.exe|SOOPLiveLauncher.exe) matched=1 ;;
      esac
    done <"$proc/cmdline" 2>/dev/null || continue
    ((matched)) || continue
    while IFS= read -r -d '' entry; do
      if [[ "$entry" == "WINEPREFIX=$prefix" ]]; then
        printf '%s\n' "${proc##*/}"
        break
      fi
    done <"$proc/environ" 2>/dev/null || true
  done
}

agent_running() {
  local line address owner pid ports=""
  local -a pids=()
  mapfile -t pids < <(launcher_pids)
  ((${#pids[@]})) || return 1
  while IFS= read -r line; do
    read -r _ _ _ address _ owner <<<"$line"
    case "$address" in
      127.*:*|\[::1\]:*) ;;
      *) continue ;;
    esac
    for pid in "${pids[@]}"; do
      if [[ "$owner" == *"pid=$pid,"* ]]; then
        if [[ " $ports" != *" ${address##*:} "* ]]; then
          ports+="${address##*:} "
        fi
        break
      fi
    done
  done < <(ss -H -ltnp 2>/dev/null)
  detected_ports="${ports% }"
  [[ -n "$detected_ports" ]]
}

mode=run
parent_pid=""
ready_file=""

while (($# > 0)); do
  case "$1" in
    --status)
      mode=status
      ;;
    --stop)
      mode=stop
      ;;
    --parent-pid)
      if (($# < 2)) || [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
        printf 'soop-grid: --parent-pid requires a positive integer\n' >&2
        exit 2
      fi
      parent_pid="$2"
      shift
      ;;
    --ready-file)
      if (($# < 2)) || [[ "$2" != /* ]]; then
        printf 'soop-grid: --ready-file requires an absolute path\n' >&2
        exit 2
      fi
      ready_file="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'soop-grid: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

readonly PAYLOAD_DIR="${SOOP_GRID_PAYLOAD_DIR:?soop-grid requires SOOP_GRID_PAYLOAD_DIR to be set by the package wrapper}"
readonly SEED_VERSION="${SOOP_GRID_SEED_VERSION:?soop-grid requires SOOP_GRID_SEED_VERSION to be set by the package wrapper}"

: "${HOME:?soop-grid requires HOME to be set}"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
soop_root="$data_home/soop"
data_root="$soop_root/grid"
app_dir="$data_root/app"
prefix="$data_root/wineprefix"
state_root="$state_home/soop/grid"
log_file="$state_root/agent.log"
runtime_root="${XDG_RUNTIME_DIR:-$soop_root/runtime}/soop"
lock_file="$runtime_root/grid.lock"
stop_request="$runtime_root/grid.stop"
display_file="$runtime_root/xvfb-display.$$"

export WINEPREFIX="$prefix"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}winemenubuilder.exe=d"

detected_ports=""
if [[ "$mode" == status ]]; then
  if agent_running; then
    printf 'SOOP grid launcher listens on localhost ports: %s.\n' "$detected_ports"
    exit 0
  fi
  printf 'SOOP grid agent is not running.\n'
  exit 1
fi

umask 077
mkdir -p "$runtime_root"

stop_wine() {
  if [[ ! -d "$prefix" ]]; then
    return 0
  fi
  wineserver -k >/dev/null 2>&1 || true
  timeout 10 wineserver -w >/dev/null 2>&1
}

if [[ "$mode" == stop ]]; then
  exec 9>"$lock_file"
  if ! flock -n 9; then
    : >"$stop_request"
    stop_wine || true
    if ! flock -w 20 9; then
      printf 'soop-grid: timed out waiting for the active session to stop.\n' >&2
      exit 1
    fi
  fi

  stop_status=0
  stop_wine || stop_status=1
  rm -f "$stop_request"
  if agent_running; then
    printf 'soop-grid: private launcher is still listening: %s.\n' \
      "$detected_ports" >&2
    exit 1
  fi
  if ((stop_status)); then
    printf 'soop-grid: Wine processes did not stop within the timeout.\n' >&2
    exit 1
  fi
  printf 'SOOP grid agent is stopped.\n'
  exit 0
fi

exec 9>"$lock_file"
if ! flock -n 9; then
  printf 'soop-grid: another SOOP session is already active.\n' >&2
  exit 3
fi
rm -f "$stop_request"

if agent_running; then
  printf 'soop-grid: private launcher is already listening: %s.\n' "$detected_ports" >&2
  exit 1
fi

mkdir -p "$data_root" "$state_root"

wine_pid=""
xvfb_pid=""

child_is_running() {
  local child_pid="$1"
  local running_pid

  while read -r running_pid; do
    if [[ "$running_pid" == "$child_pid" ]]; then
      return 0
    fi
  done < <(jobs -pr)
  return 1
}

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM HUP

  if [[ -n "$ready_file" ]]; then
    rm -f "$ready_file"
  fi
  rm -f "$display_file"

  printf 'Stopping the SOOP grid agent...\n'
  stop_wine || true
  if [[ -n "$wine_pid" ]]; then
    for _ in {1..100}; do
      if ! child_is_running "$wine_pid"; then
        break
      fi
      sleep 0.05
    done
    if child_is_running "$wine_pid"; then
      kill -KILL "$wine_pid" 2>/dev/null || true
    fi
    wait "$wine_pid" 2>/dev/null || true
  fi
  if ! stop_wine; then
    printf 'soop-grid: Wine processes did not stop within the timeout.\n' >&2
    exit_status=1
  fi

  for _ in {1..100}; do
    if ! agent_running; then
      break
    fi
    sleep 0.05
  done
  if agent_running; then
    printf 'soop-grid: launcher sockets did not close: %s.\n' "$detected_ports" >&2
    exit_status=1
  fi

  if [[ -n "$xvfb_pid" ]]; then
    kill -TERM "$xvfb_pid" 2>/dev/null || true
    wait "$xvfb_pid" 2>/dev/null || true
  fi

  rm -f "$stop_request"
  printf 'Session cleanup complete; exit status: %s\n' "$exit_status" >>"$log_file"
  exit "$exit_status"
}

trap cleanup EXIT
trap 'printf "Session received a termination signal.\n" >>"$log_file"; exit 0' INT TERM HUP

session_should_stop() {
  if [[ -e "$stop_request" ]]; then
    printf "Stop requested.\n" >>"$log_file"
    return 0
  fi
  if [[ -n "$parent_pid" ]] && ! kill -0 "$parent_pid" 2>/dev/null; then
    printf "Parent exited.\n" >>"$log_file"
    return 0
  fi
  return 1
}

if session_should_stop; then
  exit 0
fi

rm -f "$display_file"
exec 7>"$display_file"
Xvfb -displayfd 7 -screen 0 1024x768x24 -nolisten tcp >>"$log_file" 2>&1 9>&- &
xvfb_pid=$!
exec 7>&-

display_number=""
for _ in {1..100}; do
  if [[ -s "$display_file" ]]; then
    read -r display_number <"$display_file"
    break
  fi
  if ! child_is_running "$xvfb_pid"; then
    break
  fi
  sleep 0.05
done

if [[ ! "$display_number" =~ ^[0-9]+$ ]]; then
  printf 'soop-grid: the virtual display did not become ready; see %s\n' \
    "$log_file" | tee -a "$log_file" >&2
  exit 1
fi
export DISPLAY=":$display_number"
unset WAYLAND_DISPLAY

if [[ ! -d "$WINEPREFIX/drive_c/windows" ]]; then
  printf 'Initializing the private SOOP Wine prefix...\n'
  wineboot --init >>"$log_file" 2>&1 9>&-
fi

# Restore package-owned files regardless of the writable copy's version.
mkdir -p "$app_dir"
for source_file in "$PAYLOAD_DIR/"*; do
  target_file="$app_dir/${source_file##*/}"
  if ! cmp -s "$source_file" "$target_file"; then
    cp -f "$source_file" "$target_file"
    chmod u+rw "$target_file"
  fi
done
printf '%s\n' "$SEED_VERSION" >"$app_dir/.nix-seed-version"
printf '{}\n' >"$app_dir/config.json"

if session_should_stop; then
  exit 0
fi

printf 'Starting the SOOP grid agent...\n'
(cd "$app_dir" && exec wine ./SOOPLiveLauncher.exe) >>"$log_file" 2>&1 9>&- &
wine_pid=$!

started=0
for _ in {1..300}; do
  if agent_running; then
    started=1
    break
  fi
  if ! child_is_running "$wine_pid"; then
    break
  fi
  if session_should_stop; then
    exit 0
  fi
  sleep 0.1
done

if ((!started)); then
  printf 'soop-grid: launcher did not open a localhost socket (%s); see %s\n' \
    "$detected_ports" "$log_file" | tee -a "$log_file" >&2
  exit 1
fi

if [[ -n "$ready_file" ]]; then
  printf '%s\n' "$$" >"$ready_file"
fi
printf 'SOOP grid launcher listens on localhost ports: %s.\n' "$detected_ports"

printf "Launcher ready; localhost ports: %s\n" "$detected_ports" >>"$log_file"
missing_since=""
while true; do
  if session_should_stop; then
    break
  fi

  if agent_running; then
    if [[ -n "$missing_since" ]]; then
      printf "Launcher service recovered; ports: %s\n" "$detected_ports" >>"$log_file"
    fi
    missing_since=""
  else
    # Linux uptime is monotonic and expressed with two decimal places. Count
    # elapsed time so process/socket inspection does not lengthen the grace.
    read -r uptime _ </proc/uptime
    now_ticks=$((10#${uptime/./}))
    if [[ -z "$missing_since" ]]; then
      missing_since="$now_ticks"
      printf "Launcher process or localhost socket lost; starting 60-second grace.\n" >>"$log_file"
    elif ((now_ticks - missing_since >= SERVICE_GRACE_SECONDS * 100)); then
      printf 'Launcher process or socket absent for 60 seconds.\n' >>"$log_file"
      exit 1
    fi
  fi
  sleep 0.25
done
