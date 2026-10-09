#!/usr/bin/env bash
# Real tmux, isolated socket and fake Codex only; never touches user sessions.
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d /tmp/satellite-launch.XXXXXX)
socket=$test_root/tmux.sock
tmux_binary=$(command -v tmux)
trap '"$tmux_binary" -S "$socket" kill-server 2>/dev/null || :; rm -rf -- "$test_root"' EXIT
unset TMUX TMUX_PANE
export LC_ALL=C
tmux() { "$tmux_binary" -S "$socket" -f /dev/null "$@"; }
trap 'tmux list-panes -a -F "#{session_name} #{pane_id} #{pane_dead} #{pane_dead_status} #{pane_start_command}"; tmux capture-pane -p -t codex-failed: -S -100 2>/dev/null || :' ERR
mkdir -p "$test_root/bin with spaces" "$test_root/project with spaces;\$(literal)"
cat > "$test_root/bin with spaces/codex" <<'SH'
#!/bin/sh
printf '%s\n' "$$" "$PWD" "$PATH" "${CODEX_HOME-unset}" "${CODEX_SWITCHER_HOME-unset}" "$@" "$TERM" > launch.txt
printf 'FAKE_CODEX_STARTUP_FAILURE\n'
exit 42
SH
chmod +x "$test_root/bin with spaces/codex"
# Seed stale server values before setting the caller's environment.
CODEX_HOME=stale CODEX_SWITCHER_HOME=stale tmux new-session -d -s fixture /bin/sleep 120
tmux set-option -g default-terminal satellite-missing-terminfo
source "$cli_dir/init.bash"
PATH="$test_root/bin with spaces:$PATH"
export CODEX_HOME="$test_root/home with spaces;\$(literal)"
export CODEX_SWITCHER_HOME="$test_root/switcher with spaces;\$(literal)"
ez_codex_field() {
  if [[ $1 == 'Session name' ]]; then printf '%s' "$test_name"
  else printf '%s' "$test_root/project with spaces;\$(literal)"; fi
}
# Check the created pane instead of attaching a real terminal.
ez_codex_attach() { created_id=$1; }
test_name=failed
ez_codex_new
for ((attempt=0;attempt<100;attempt++)); do
  [[ $(tmux display-message -p -t "$created_id:" '#{pane_dead}') == 1 ]] && break
  sleep 0.02
done
[[ $(tmux display-message -p -t "$created_id:" '#{pane_dead_status}') == 42 ]]
[[ $(tmux capture-pane -p -t "$created_id:" -S -100) == *FAKE_CODEX_STARTUP_FAILURE* ]]
mapfile -t launch < "$test_root/project with spaces;\$(literal)/launch.txt"
[[ ${launch[0]} == "$(tmux display-message -p -t "$created_id:" '#{pane_pid}')" ]]
[[ ${launch[1]} == "$test_root/project with spaces;\$(literal)" ]]
[[ ${launch[2]} == "$PATH" && ${launch[3]} == "$CODEX_HOME" && ${launch[4]} == "$CODEX_SWITCHER_HOME" ]]
[[ ${launch[5]} == --dangerously-bypass-approvals-and-sandbox && ${launch[6]} == xterm-256color && ${#launch[@]} == 7 ]]
ez_codex_scan
[[ ${ez_codex_names[*]} == failed ]]
printf 'PASS failed launch preserves diagnostics, pane PID, directory, flags and current configuration homes\n'
unset CODEX_HOME CODEX_SWITCHER_HOME
tmux set-option -g default-terminal xterm
test_name=unset
ez_codex_new
for ((attempt=0;attempt<100;attempt++)); do
  [[ $(tmux display-message -p -t "$created_id:" '#{pane_dead}') == 1 ]] && break
  sleep 0.02
done
mapfile -t launch < "$test_root/project with spaces;\$(literal)/launch.txt"
[[ ${launch[3]} == unset && ${launch[4]} == unset ]]
[[ ${launch[6]} == xterm ]]
printf 'PASS unset homes clear stale settings and supported terminal types stay unchanged\n'
# Normal successful exits should still remove the session.
printf '#!/bin/sh\nexit 0\n' > "$test_root/bin with spaces/codex"
test_name=success
ez_codex_new
for ((attempt=0;attempt<100;attempt++)); do
  tmux has-session -t "$created_id" 2>/dev/null || break
  sleep 0.02
done
! tmux has-session -t "$created_id" 2>/dev/null
printf 'PASS successful Codex exit closes normally\n'
