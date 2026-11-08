# Shared helpers for the Sunshine tile scripts in this folder (steam-tv, heroic-tv). Sourced, not run.
# Same approach as Quiver's quiver-tv (~/QuiverLauncher/quiver-launcher/tools/launch/quiver-tv), which these follow:
# each tile records what it started under the pid of the Sunshine it runs under, so the couch and bed instances only
# ever close what their own tile started.
#
# The sourcing script sets TILE_STATE (its state folder) and TILE_NAME (for the log) first.

mkdir -p "$TILE_STATE"
log() { echo "$(date '+%F %T') $*" >>"$TILE_STATE/tv.log"; }

# /proc/PID/stat after the name: 1 state, 2 parent, 4 session, 20 start time (clock ticks since boot). Pid and start
# time together name one process for good, since pids get reused.
stat_field() {
  local s n=$2
  s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  s=${s##*) }; set -f; set -- $s; set +f
  echo "${!n}"
}
alive() { local s; s=$(stat_field "$1" 1) && [[ $s != [ZX] ]]; }

# The Sunshine this runs under: the nearest one up the process tree. Else the parent (tests, or by hand).
# TILE_OWNER overrides it (tests).
owner() {
  [[ -n ${TILE_OWNER:-} ]] && { echo "$TILE_OWNER"; return; }
  local p=$PPID
  while ((p > 1)); do
    [[ $(cat "/proc/$p/comm" 2>/dev/null) == sunshine ]] && { echo "$p"; return; }
    p=$(stat_field "$p" 2) || break
  done
  echo "$PPID"
}

# Forget tiles whose Sunshine has stopped: prune_tiles PREFIX
prune_tiles() {
  local f
  for f in "$TILE_STATE/$1".*; do [[ -e $f && ! -e /proc/${f##*.} ]] && rm -f "$f"; done
  return 0
}

names() { local p; for p in "$@"; do printf '%s(%s) ' "$(cat "/proc/$p/comm" 2>/dev/null)" "$p"; done; }

# All descendants of PID (not PID itself), from one ps snapshot.
descendants() {
  ps -u "$UID" -o pid=,ppid= | awk -v root="$1" '
    { kids[$2] = kids[$2] " " $1 }
    END { n = split(kids[root], q, " "); for (i = 1; i <= n; i++) { print q[i]; m = split(kids[q[i]], more, " ");
          for (j = 1; j <= m; j++) q[++n] = more[j] } }'
}

# Wine's own background programs. They hold nothing of the game's, and winedevice.exe ignores SIGTERM: waiting for
# them would make every Windows game's quit take the full grace time. They're stopped once the game itself has closed.
WINE_SERVICES=" wineserver winedevice.exe services.exe plugplay.exe svchost.exe rpcss.exe explorer.exe tabtip.exe xalia.exe conhost.exe winedbg "

# close SECONDS PID...: ask them to close, wait until they have, and force what's left after SECONDS.
close() {
  local secs=$1 i p; shift
  (($#)) || return 0
  local -a wait_for=() left=()
  for p in "$@"; do [[ $WINE_SERVICES == *" $(cat "/proc/$p/comm" 2>/dev/null) "* ]] || wait_for+=("$p"); done
  kill -TERM "$@" 2>/dev/null
  for ((i = 0; i < secs * 10; i++)); do
    left=()
    for p in "${wait_for[@]}"; do alive "$p" && left+=("$p"); done
    ((${#left[@]})) || break
    sleep 0.1
  done
  ((${#left[@]})) && log "  didn't close in ${secs}s, forced: $(names "${left[@]}")"
  left=()
  for p in "$@"; do alive "$p" && left+=("$p"); done
  ((${#left[@]})) && kill -KILL "${left[@]}" 2>/dev/null
  return 0
}
