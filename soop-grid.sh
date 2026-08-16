#!@bash@
set -euo pipefail

export PATH="@runtimePath@${PATH:+:$PATH}"

readonly CONTROL_PORT=21201
readonly SITE_URL="https://www.sooplive.com/"
readonly PAYLOAD_DIR="@payloadDir@"
readonly RUNTIME_DIR="@runtimeDir@"
readonly SEED_VERSION="@seedVersion@"

usage() {
  cat <<'EOF'
Usage: soop-grid [--open] [--status]

  --open    Open SOOP in the default browser after starting the agent
  --status  Report whether the control service is listening on port 21201
  --help    Show this help
EOF
}

agent_running() {
  [[ -n "$(ss -H -ltn "sport = :$CONTROL_PORT" 2>/dev/null)" ]]
}

open_site() {
  if ! setsid --fork xdg-open "$SITE_URL" >/dev/null 2>&1 9>&-; then
    printf 'soop-grid: could not open %s\n' "$SITE_URL" >&2
  fi
}

open_after_start=0
status_only=0

while (($# > 0)); do
  case "$1" in
    --open)
      open_after_start=1
      ;;
    --status)
      status_only=1
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

if ((status_only)); then
  if agent_running; then
    printf 'SOOP grid agent is listening on port %d.\n' "$CONTROL_PORT"
    exit 0
  fi
  printf 'SOOP grid agent is not running.\n'
  exit 1
fi

if agent_running; then
  printf 'SOOP grid agent is already running on port %d.\n' "$CONTROL_PORT"
  if ((open_after_start)); then
    open_site
  fi
  exit 0
fi

: "${HOME:?soop-grid requires HOME to be set}"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
data_root="$data_home/soop-grid"
app_dir="$data_root/app"
export WINEPREFIX="$data_root/wineprefix"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mfc71,mfc71u,msvcp71,msvcr71=n;winemenubuilder.exe=d"

state_root="$state_home/soop-grid"
log_file="$state_root/agent.log"

umask 077
mkdir -p "$data_root" "$state_root"

exec 9>"$data_root/launch.lock"
flock 9

# Another invocation may have completed while this one waited for the lock.
if agent_running; then
  printf 'SOOP grid agent is already running on port %d.\n' "$CONTROL_PORT"
  if ((open_after_start)); then
    open_site
  fi
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

# Keep the vendor updater in the writable XDG application directory.
windows_app_dir="$(winepath -w "$app_dir" 2>>"$log_file")"
wine reg add 'HKCU\Software\SOOP\Updater2' \
  /v Path /t REG_SZ /d "$windows_app_dir" /f >>"$log_file" 2>&1

printf 'Starting the SOOP grid agent...\n'
setsid --fork wine "$app_dir/SOOPPackage.exe" >>"$log_file" 2>&1 9>&-

started=0
for _ in {1..200}; do
  if agent_running; then
    started=1
    break
  fi
  sleep 0.1
done

if ((!started)); then
  printf 'soop-grid: the control service did not open port %d; see %s\n' \
    "$CONTROL_PORT" "$log_file" >&2
  exit 1
fi

printf 'SOOP grid agent is listening on port %d.\n' "$CONTROL_PORT"
if ((open_after_start)); then
  open_site
fi
