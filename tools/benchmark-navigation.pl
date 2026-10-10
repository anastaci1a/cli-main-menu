#!/usr/bin/env perl
# End-to-end menu transitions using an isolated, deliberately slow backend.
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use IO::Pty;
use IO::Select;
use Time::HiRes qw(time);
my $repo=abs_path($ARGV[0] // "$FindBin::Bin/..");
my $root=tempdir(CLEANUP=>1);
mkdir "$root/bin" or die $!;
open my $backend, '>', "$root/bin/codex-switcher" or die $!;
print {$backend} <<'SH';
#!/bin/bash
printf '%s\n' "$*" >> "$BENCH_ROOT/calls"
case $1 in
  sessions)
    while :; do
      sleep "${BENCH_BACKEND_DELAY:-0.4}"
      printf '%s\n' '{"schema_version":1,"observed_at":1,"sessions":[{"id":"pane:%1","pane":"%1","name":"codex-Alpha","cwd":"/tmp","account":"personal","lifecycle":"live","activity":"busy","last_accessed":1000}]}'
      [[ $* == *--watch* ]] || break
      sleep 0.5
    done ;;
  status) printf '%s\n' '{"schema_version":1,"daemon":{"running":true},"accounts":[{"name":"personal","enabled":true,"eligible":true}]}' ;;
  *) exit 99 ;;
esac
SH
close $backend;
chmod 0755, "$root/bin/codex-switcher";
open my $driver, '>', "$root/driver" or die $!;
print {$driver} <<'SH';
source "$1/init.bash"
PATH="$BENCH_ROOT/bin:/usr/bin:/bin"
TMUX=''
tmux() { [[ $1 == list-panes ]] || return 1; printf '%%1|100\n'; }
EZ_MENU_TITLE=SATELLITE EZ_MENU_ANIMATE_STARS=1
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_HUE_STEP=70 RANDOM=1967
ez_select
printf 'BENCH_DONE\n'
SH
close $driver;
$ENV{LC_ALL}='C'; $ENV{TERM}='xterm-256color'; $ENV{BENCH_ROOT}=$root;
my $pty=IO::Pty->new;
$pty->set_winsize($ENV{BENCH_ROWS} // 24,$ENV{BENCH_COLS} // 80,0,0);
my $started=time;
my $pid=fork(); die $! unless defined $pid;
END { local $?; if ($pid && waitpid($pid,1)==0) { kill 'TERM',$pid; waitpid($pid,0); } }
if (!$pid) {
  $pty->make_slave_controlling_terminal;
  my $slave=$pty->slave;
  open STDIN, '<&', $slave or die $!;
  open STDOUT, '>&', $slave or die $!;
  open STDERR, '>&', $slave or die $!;
  close $pty;
  exec 'bash','--noprofile','--norc',"$root/driver",$repo;
  die $!;
}
$pty->close_slave;
my $selector=IO::Select->new($pty);
my $output='';
sub pump {
  for my $fd ($selector->can_read(0.01)) {
    my $n=sysread($fd,my $chunk,65536);
    $output.=$chunk if $n;
  }
}
sub expect {
  my ($pattern)=@_;
  my $deadline=time+10;
  while (time<$deadline) {
    (my $plain=$output) =~ s/\e\[[0-9;?]*[A-Za-z]//g;
    return if $plain =~ $pattern || $output =~ $pattern;
    pump();
  }
  die "Menu did not reach $pattern\n".substr($output,-1000);
}
sub transition {
  my ($label,$keys,$pattern)=@_;
  $output=''; my $start=time;
  syswrite($pty,$keys);
  expect($pattern);
  printf "%s_ms=%.1f\n",$label,1000*(time-$start);
}
expect(qr/Codex: Sessions/);
printf "initial_home_ms=%.1f\n",1000*(time-$started);
# Let the old two-second snapshot window expire, as when browsing the home menu.
my $idle_until=time+3.2;
while (time<$idle_until) { pump() }
syswrite($pty,"\e[B\e[B");
$output=''; expect(qr/\e\[1mCodex:.*\e\[1mSessions/s);
transition('sessions',"\n",qr/Alpha.*Session Manager/s);
transition('sessions_to_home',"\e",qr/New Terminal/);
transition('sessions_reopen',"\n",qr/Alpha.*Session Manager/s);
transition('name_field',"\n",qr/Session name/);
syswrite($pty,'benchmark-project');
$output=''; expect(qr/benchmark-project/);
transition('path_picker',"\n",qr/Start directory/);
transition('account_picker',"\n",qr/Choose Account/);
transition('accounts_to_sessions',"\e",qr/Session Manager/);
transition('return_home',"\e",qr/New Terminal/);
transition('exit',"\e",qr/BENCH_DONE/);
waitpid($pid,0);
die "Menu failed: $?" if $?;
open my $calls, '<', "$root/calls" or die $!;
my @calls=<$calls>;
printf "inventory_commands=%d\n",scalar(grep { /^sessions / } @calls);
