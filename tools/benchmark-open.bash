#!/usr/bin/env bash
# Real installed Switcher and tmux, with an isolated socket/home and fake Codex.
# The final interactive attach is stubbed. No user session is opened or changed.
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
backend=${BENCH_SWITCHER_BIN:-/mnt/user/live/packages/codex-switcher/bin/codex-switcher}
[[ -x $backend ]] || { printf 'Set BENCH_SWITCHER_BIN to the installed binary.\n' >&2; exit 1; }
test_root=$(mktemp -d /tmp/satellite-open.XXXXXX)
tmux_binary=$(command -v tmux)
socket=$test_root/tmux.sock
trap '"$tmux_binary" -S "$socket" kill-server 2>/dev/null || :; rm -rf -- "$test_root"' EXIT
unset TMUX TMUX_PANE
export TMUX="$socket,0,0"
mkdir -p "$test_root/bin" "$test_root/codex-home" "$test_root/state"
export LC_ALL=C CODEX_HOME=$test_root/codex-home CODEX_SWITCHER_HOME=$test_root/state
export BENCH_TMUX_BINARY=$tmux_binary BENCH_TMUX_SOCKET=$socket
cat > "$test_root/bin/tmux" <<'SH'
#!/bin/bash
exec "$BENCH_TMUX_BINARY" -S "$BENCH_TMUX_SOCKET" -f /dev/null "$@"
SH
chmod +x "$test_root/bin/tmux"
# A copied sleep has the process/argv name codex, without running actual Codex.
cp /bin/sleep "$test_root/bin/codex"
export PATH=$test_root/bin:$PATH
ln -s "$backend" "$test_root/bin/codex-switcher"
pane=$(tmux new-session -d -P -F '#{pane_id}' -s codex-benchmark -c "$test_root" "$test_root/bin/codex" 120)
for ((attempt=0;attempt<100;attempt++)); do
  [[ $(tmux display-message -p -t "$pane" '#{pane_current_command}') != codex ]] || break
  sleep 0.01
done
source "${1:-$cli_dir}/init.bash"
inventory=$(codex-switcher sessions --include-tmux)
key=$(jq -r --arg pane "$pane" '.sessions[] | select(.pane == $pane) | .id' <<< "$inventory")
[[ -n $key ]] || { printf 'Isolated fixture was not discovered.\n' >&2; exit 1; }
printf 'fixture_id_kind=%s (plain tmux is a handoff baseline only)\n' "${key%%:*}" >&2
printf 'stage,microseconds\n'
measure() {
  local stage=$1 start=${EPOCHREALTIME/./} end
  shift
  "$@" || { printf '%s: %s\n' "$stage" "${ez_switcher_error:-failed}" >&2; return 1; }
  end=${EPOCHREALTIME/./}
  printf '%s,%d\n' "$stage" "$((10#$end-10#$start))"
}
watch_pid='' watch_fd='' watch_errors='' watch_partial='' watch_snapshot=''
ez_switcher_watch_start
for ((attempt=0;attempt<100;attempt++)); do
  if ez_switcher_watch_read 0.05; then break; fi
done
measure watcher_shutdown ez_switcher_watch_close
for ((sample=0;sample<5;sample++)); do
  measure switcher_open ez_switcher_request 'select(.schema_version == 1)' open --session "$key"
  measure response_extract mapfile -d '' -t target < <(jq -jr '.session | [.tmux_session,.pane] | .[] | .+"\u0000"' <<< "$ez_switcher_json")
  tmux() {
    # Attach is a long-lived client; only measure preparation before that hop.
    [[ $1 == attach-session || $1 == switch-client ]] || command tmux "$@"
  }
  measure tmux_preparation ez_codex_attach "=${target[0]}" "${target[1]}"
done
