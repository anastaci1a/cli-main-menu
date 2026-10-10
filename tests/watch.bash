#!/usr/bin/env bash
set -euo pipefail
cli_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'ez_switcher_watch_close; rm -rf -- "$test_root"' EXIT
source "$cli_dir/init.bash"
mkdir "$test_root/bin"
cat > "$test_root/bin/codex-switcher" <<'SH'
#!/bin/bash
[[ $* == 'sessions --all --watch --interval 2' ]] || exit 9
printf '{"schema_version":1,"observed_at":1,"sessions":[]}'
sleep 0.1
printf '\n'
sleep 0.3
printf '{"schema_version":1,"observed_at":2,"sessions":[]}\n'
sleep 0.3
printf 'fixture stream ended\n' >&2
exit 7
SH
chmod +x "$test_root/bin/codex-switcher"
PATH="$test_root/bin:$PATH"
watch_pid='' watch_fd='' watch_errors='' watch_partial='' watch_snapshot=''
ez_switcher_watch_start
pid=$watch_pid
seen=0 disconnected=0
for ((i=0;i<100;i++)); do
  if ez_switcher_watch_read; then
    seen=$(jq -r '.observed_at' <<< "$ez_switcher_json")
  else
    status=$?
    if (( status == 2 )); then disconnected=1; break; fi
  fi
  sleep 0.02
done
[[ $seen == 2 && $disconnected == 1 && $ez_switcher_error == *'fixture stream ended'* ]]
[[ $(jq -r '.observed_at' <<< "$watch_snapshot") == 2 ]]
ez_switcher_watch_close
! kill -0 "$pid" 2>/dev/null
# Closing the screen stops only its watcher, including when the stream is idle.
printf '#!/bin/sh\nexec sleep 120\n' > "$test_root/bin/codex-switcher"
ez_switcher_watch_start
pid=$watch_pid
ez_switcher_watch_close
! kill -0 "$pid" 2>/dev/null
printf 'PASS partial watch snapshots, EOF/nonzero disconnection and owned-process cleanup\n'
