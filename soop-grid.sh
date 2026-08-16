#!@bash@
set -euo pipefail

export PATH="@runtimePath@${PATH:+:$PATH}"

readonly CONTROL_PORT=21201
readonly PAYLOAD_DIR="@payloadDir@"
readonly RUNTIME_DIR="@runtimeDir@"
readonly SEED_VERSION="@seedVersion@"

usage() {
  cat <<'EOF'
Usage: soop-grid [--status | --stop] [--parent-pid PID] [--ready-file PATH]

  --status          Report whether the control service is listening on port 21201
  --stop            Stop every Wine process in the private SOOP prefix
  --parent-pid PID  Stop when PID exits (used by the integrated SOOP app)
  --ready-file PATH Write readiness to PATH (used by the integrated SOOP app)
  --help            Show this help
EOF
}

agent_running() {
  [[ -n "$(ss -H -ltn "sport = :$CONTROL_PORT" 2>/dev/null)" ]]
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

if [[ "$mode" == status ]]; then
  if agent_running; then
    printf 'SOOP grid agent is listening on port %d.\n' "$CONTROL_PORT"
    exit 0
  fi
  printf 'SOOP grid agent is not running.\n'
  exit 1
fi

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

export WINEPREFIX="$prefix"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mfc71,mfc71u,msvcp71,msvcr71=n;winemenubuilder.exe=d"

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
    printf 'soop-grid: port %d is still in use by another process.\n' \
      "$CONTROL_PORT" >&2
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
  printf 'soop-grid: port %d is already in use.\n' "$CONTROL_PORT" >&2
  exit 1
fi

mkdir -p "$data_root" "$state_root"

wine_pid=""

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM HUP

  if [[ -n "$ready_file" ]]; then
    rm -f "$ready_file"
  fi

  printf 'Stopping the SOOP grid agent...\n'
  stop_wine || true
  if [[ -n "$wine_pid" ]]; then
    for _ in {1..100}; do
      if [[ "$(jobs -pr)" != "$wine_pid" ]]; then
        break
      fi
      sleep 0.05
    done
    if [[ "$(jobs -pr)" == "$wine_pid" ]]; then
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
    printf 'soop-grid: port %d did not close cleanly.\n' "$CONTROL_PORT" >&2
    exit_status=1
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP

session_should_stop() {
  if [[ -e "$stop_request" ]]; then
    return 0
  fi
  if [[ -n "$parent_pid" ]] && ! kill -0 "$parent_pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

if session_should_stop; then
  exit 0
fi

prefix_created=0
if [[ ! -d "$WINEPREFIX/drive_c/windows" ]]; then
  printf 'Initializing the private SOOP Wine prefix...\n'
  wineboot --init >>"$log_file" 2>&1
  prefix_created=1
fi

seed_changed=0
seed_marker="$app_dir/.nix-seed-version"
if [[ ! -f "$seed_marker" ]] || [[ "$(<"$seed_marker")" != "$SEED_VERSION" ]]; then
  seed_changed=1
fi

for required_file in \
  SOOPPackage.exe SOOPStreamer.exe NetControl.dll upnputil.dll SOOPLogUtil.dll; do
  if [[ ! -f "$app_dir/$required_file" ]]; then
    seed_changed=1
  fi
done

if ((seed_changed)); then
  mkdir -p "$app_dir"
  cp -f "$PAYLOAD_DIR/"* "$app_dir/"
  chmod u+rw "$app_dir/"*
  printf '%s\n' "$SEED_VERSION" >"$seed_marker"
fi

windows_runtime="$WINEPREFIX/drive_c/windows/syswow64"
mkdir -p "$windows_runtime"
for runtime_file in mfc71.dll mfc71u.dll msvcp71.dll msvcr71.dll; do
  if ((prefix_created || seed_changed)) || [[ ! -f "$windows_runtime/$runtime_file" ]]; then
    cp -f "$RUNTIME_DIR/$runtime_file" "$windows_runtime/$runtime_file"
    chmod u+rw "$windows_runtime/$runtime_file"
  fi
done

if session_should_stop; then
  exit 0
fi

# Keep the vendor updater in the writable XDG application directory.
windows_app_dir="$(winepath -w "$app_dir" 2>>"$log_file")"
wine reg add 'HKCU\Software\SOOP\Updater2' \
  /v Path /t REG_SZ /d "$windows_app_dir" /f >>"$log_file" 2>&1

if session_should_stop; then
  exit 0
fi

printf 'Starting the SOOP grid agent...\n'
wine "$app_dir/SOOPPackage.exe" >>"$log_file" 2>&1 9>&- &
wine_pid=$!

started=0
for _ in {1..300}; do
  if agent_running; then
    started=1
    break
  fi
  if [[ "$(jobs -pr)" != "$wine_pid" ]]; then
    break
  fi
  if session_should_stop; then
    exit 0
  fi
  sleep 0.1
done

if ((!started)); then
  printf 'soop-grid: the control service did not open port %d; see %s\n' \
    "$CONTROL_PORT" "$log_file" >&2
  exit 1
fi

if [[ -n "$ready_file" ]]; then
  printf '%s\n' "$$" >"$ready_file"
fi
printf 'SOOP grid agent is listening on port %d.\n' "$CONTROL_PORT"

while agent_running; do
  if session_should_stop; then
    break
  fi
  sleep 0.25
done
