#!/usr/bin/env perl
# Key-to-visible-selection latency; no backend, jobs, or live tmux sessions.
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
open my $driver, '>', "$root/driver" or die $!;
print {$driver} <<'SH';
source "$1/init.bash"
EZ_MENU_TITLE=SATELLITE EZ_MENU_ANIMATE_STARS=1 RANDOM=1967
banner=$(ez_menu_banner)
ez_menu_choose 0 "$banner" --accent-suffix 1 ' (Example)' -- \
  'Option0' 'Option1 (Example)' 'Option2' 'Option3'
SH
close $driver;
$ENV{LC_ALL}='C'; $ENV{TERM}='xterm-256color';
my $pty=IO::Pty->new;
$pty->set_winsize($ENV{BENCH_ROWS} // 24,$ENV{BENCH_COLS} // 80,0,0);
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
my $reader=IO::Select->new($pty);
my $output='';
sub pump {
  for my $fd ($reader->can_read(0.002)) {
    my $n=sysread($fd,my $chunk,65536);
    $output.=$chunk if $n;
  }
}
sub selected {
  my ($index)=@_;
  my $end=time+10;
  while (time<$end) {
    return if $output =~ /\e\[1mOption$index/;
    pump();
  }
  die "Selection $index did not render\n".substr($output,-1000);
}
selected(0);
my $origin=time;
print "elapsed_ms,selection_ms,bytes\n";
for my $step (1..70) {
  my $target=$origin+$step*0.1;
  pump() while time<$target;
  $output='';
  my $start=time;
  syswrite($pty,"\e[B");
  selected($step%4);
  printf "%.1f,%.3f,%d\n",1000*($start-$origin),1000*(time-$start),length($output);
}
syswrite($pty,"\n");
waitpid($pid,0);
