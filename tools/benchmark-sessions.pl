#!/usr/bin/env perl
# Compare a working tree or checkout using a fixed, read-only backend fixture.
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use IO::Pty;
use IO::Select;
use Time::HiRes qw(time);
use Cwd qw(abs_path);
my $repo=abs_path($ARGV[0] // "$FindBin::Bin/..");
my $root=tempdir(CLEANUP=>1);
mkdir "$root/bin" or die $!;
open my $backend, '>', "$root/bin/codex-switcher" or die $!;
print {$backend} <<'SH';
#!/bin/bash
[[ $1 == sessions ]] || exit 99
printf '%s\n' "$*" >> "$BENCH_ROOT/calls"
while :; do
  sleep 0.08
  printf '%s\n' '{"schema_version":1,"observed_at":1,"sessions":[{"id":"pane:%1","pane":"%1","name":"Alpha","cwd":"/tmp","account":"personal","lifecycle":"live","activity":"busy","last_accessed":1000}]}'
  [[ $* == *--watch* ]] || break
  sleep 2
done
SH
close $backend;
chmod 0755, "$root/bin/codex-switcher";
open my $driver, '>', "$root/driver" or die $!;
print {$driver} <<'SH';
source "$1/init.bash"
PATH="$BENCH_ROOT/bin:/usr/bin:/bin"
printf -v benchmark_created '%(%s)T' -1
tmux() { [[ $1 == list-panes ]] || return 99; printf '%%1|%s\n' "$benchmark_created"; }
EZ_MENU_SWEEP_INTERVAL_MS=4000 EZ_MENU_SWEEP_HUE_STEP=70
EZ_MENU_ANIMATE_STARS=1 RANDOM=1967
# Prime the home screen before timing entry into Sessions.
ez_menu_define_items
printf 'BENCH_READY\n'
IFS= read -r key
ez_menu_choose 1 '' --screen-title 'Codex: Sessions' --refresh ez_codex_sessions_refresh -- Refresh
SH
close $driver;
$ENV{LC_ALL}='C'; $ENV{TERM}='xterm-256color'; $ENV{BENCH_ROOT}=$root;
my $pty=IO::Pty->new;
$pty->set_winsize(24,80,0,0);
my $pid=fork(); die $! unless defined $pid;
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
my $select=IO::Select->new($pty);
my $output='';
sub pump {
  for my $fd ($select->can_read(0.02)) {
    my $n=sysread($fd,my $chunk,65536);
    $output.=$chunk if $n;
  }
}
my $deadline=time+10;
while ($output !~ /BENCH_READY/ && time<$deadline) { pump() }
die 'fixture did not start' unless $output =~ /BENCH_READY/;
$output=''; my $started=time;
syswrite($pty,"\n");
while ($output !~ /Alpha/ && time<$deadline) { pump() }
die 'menu did not render' unless $output =~ /Alpha/;
my $startup=1000*(time-$started);
my $end=time+2.2;
while (time<$end) { pump() }
my $bytes=length $output;
my $labels=()=$output =~ /Alpha/g;
syswrite($pty,"\e");
while (waitpid($pid,1)==0) { pump() }
close $pty;
open my $calls, '<', "$root/calls" or die $!;
my @calls=<$calls>;
printf "startup_ms=%.1f output_bytes=%d option_paints=%d inventory_commands=%d\n",$startup,$bytes,$labels,scalar @calls;
