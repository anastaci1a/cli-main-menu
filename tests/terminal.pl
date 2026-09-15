use strict;
use FindBin;
$ENV{EZ_CLI_BASHRC} //= "$FindBin::Bin/../../../.bashrc";
use warnings;
use IO::Pty;
use IO::Select;
use Time::HiRes qw(time sleep);
$ENV{LC_ALL}='C';
$ENV{TERM}='xterm-256color';
my ($pty, $pid, $buf, $selector);
sub start_case {
  my ($mode) = @_;
  $pty = IO::Pty->new;
  $pty->set_winsize($mode eq "many" ? 12 : 24,80,0,0);
  $pid = fork();
  die 'fork failed' unless defined $pid;
  if (!$pid) {
    $pty->make_slave_controlling_terminal;
    my $slave = $pty->slave;
    open STDIN, '<&', $slave or die $!;
    open STDOUT, '>&', $slave or die $!;
    open STDERR, '>&', $slave or die $!;
    close $pty;
    exec 'bash', '--noprofile', '--norc', '-i', "$FindBin::Bin/fixtures/terminal.bash", $mode;
    die $!;
  }
  $pty->close_slave;
  $selector=IO::Select->new($pty);
  $buf='';
}
sub pump {
  my ($seconds)=@_;
  my $end=time+$seconds;
  while (time < $end) {
    for my $fh ($selector->can_read(0.05)) {
      my $bytes=sysread($fh,my $chunk,65536);
      return unless $bytes;
      $buf.=$chunk;
    }
  }
}
sub expect {
  my ($pattern,$label)=@_;
  my $end=time+5;
  while ($buf !~ $pattern && time<$end) {pump(0.05)}
  die "FAIL $label\n$buf\n" unless $buf =~ $pattern;
}
sub send_keys { syswrite($pty,$_[0]); pump(0.15); }
sub plain { my $text=shift; $text =~ s/\e\[[0-9;?]*[A-Za-z]//g; return $text; }
sub finish {
  expect(qr/TEST_DONE/,'finished');
  waitpid($pid,0);
  die "child failed: $?\n$buf" if $?;
  close $pty;
}
start_case('chooser');
expect(qr/Up\/Down: move/,'initial menu');
die 'selected option is not bold' unless $buf =~ /\e\[1mOne/;
my @before=($buf =~ /(\d\d:\d\d:\d\d)/g);
my $idle_marker=length $buf;
pump(2.2);
my $idle_output=substr($buf,$idle_marker);
die 'clock tick repainted or cleared the whole menu' if $idle_output =~ /\e\[H|\e\[2[JK]/;
die 'animated foreground painted the original pink underlay' if $buf =~ /\e\[38;5;177m/;
my @after=($buf =~ /(\d\d:\d\d:\d\d)/g);
die 'clock did not advance' unless @after>1 && $after[-1] ne $before[0];
my $animation_marker=length $buf;
# Include the first sweep; updates must arrive between full clock redraws.
pump(3.0);
my $animation_output=substr($buf,$animation_marker);
die 'missing-focus recovery repaint was lost' unless $animation_output =~ /\e\[H/;
die 'recovery repaint restored the original title color' if $animation_output =~ /\e\[38;5;177m/;
my @overlay_frames=split /\e\[0m/, $animation_output;
my $moving_frames=grep {/\e\[\d+;\d+H\e\[38;2;/} @overlay_frames;
die 'star animation did not produce intermediate frames' unless $moving_frames > 10;
send_keys("\e[B");
expect(qr/\e\[1mTwo/,'down highlights second option');
send_keys("\n");
expect(qr/SELECTED=1 STATUS=0/,'enter chooses second');
die 'cursor not restored' unless $buf =~ /\e\[\?25h/;
finish();
print "PASS arrow selection, bold styling, live seconds, cursor cleanup\n";
print "PASS clock updates avoid full redraws and original-color underlays\n";
start_case('static');
expect(qr/Up\/Down: move/,'static fallback menu');
die 'static mode emitted an animation overlay' if $buf =~ /\e\[\d+;\d+H\e\[38;2;/;
send_keys("\e[A\n");
expect(qr/SELECTED=2 STATUS=0/,'static navigation');
finish();
print "PASS animation frames and opt-out with static navigation\n";
start_case('chooser');
expect(qr/Up\/Down: move/,'menu');
send_keys("\eOA\n");
expect(qr/SELECTED=2 STATUS=0/,'application arrow wraps upward');
finish();
start_case('chooser');
expect(qr/Up\/Down: move/,'menu');
send_keys("\e");
expect(qr/SELECTED= STATUS=130/,'escape cancels');
finish();
print "PASS arrow wrap and Escape\n";
start_case('many');
expect(qr/1-5 of 30/,'scroll window');
send_keys("\e[A\n");
expect(qr/SELECTED=29 STATUS=0/,'scroll wraps to last option');
finish();
print "PASS scrolling long menus\n";
start_case('menu');
expect(qr/Start Codex/,'dynamic start label');
send_keys("\e[B\n");
expect(qr/Start directory/,'directory prompt');
send_keys("/this-directory-does-not-exist\n");
expect(qr/Enter an existing, accessible directory/,'reject invalid directory');
send_keys("/tmp\n");
expect(qr/CREATED:<new-session><-A><-s><codex><-c><\/tmp><codex --dangerously-bypass-approvals-and-sandbox>/,'launch arguments');
finish();
print "PASS Codex directory validation and session launch\n";
start_case('foreground');
expect(qr/SHELL JOBS/,'jobs menu');
expect(qr/Stopped/,'stopped job listed');
send_keys("\n");
expect(qr/Switch to job/,'job actions');
send_keys("\n");
expect(qr/JOB_RESUMED_SUCCESSFULLY/,'foreground resume');
finish();
print "PASS foregrounding a stopped job in the calling shell\n";
start_case('jobs');
expect(qr/Terminate all jobs/,'all jobs action');
send_keys("\n");
expect(qr/Switch to job/,'job actions');
send_keys("\e[B\n");
expect(qr/Termination requested for job %1/,'individual termination');
pump(0.3);
# Select the penultimate action even if a terminating job is still listed.
send_keys("\e[A\e[A\n");
expect(qr/Termination requested for job %2/,'terminate remaining jobs');
pump(0.3);
# A final redraw may briefly include a terminating process; Escape returns.
send_keys("\e");
finish();
print "PASS individual and all-job termination\n";
$ENV{TEST_SESSION}='present';
start_case('menu');
expect(qr/Resume Codex/,'resume label');
send_keys("\e[B\n");
expect(qr/ATTACHED_CODEX/,'resume action');
finish();
delete $ENV{TEST_SESSION};
print "PASS existing Codex session resume\n";
start_case('chooser');
expect(qr/Up\/Down: move/,'menu before interrupt');
send_keys("\x03");
expect(qr/\e\[\?25h/,'cursor restored on Ctrl-C');
waitpid($pid,0);
close $pty;
print "PASS Ctrl-C cleanup\n";
start_case('chooser');
expect(qr/Ctrl-L: redraw/,'redraw hint');
die 'alternate screen missing' unless $buf =~ /\e\[\?1049h/;
die 'focus reporting missing' unless $buf =~ /\e\[\?1004h/;
die 'premature screen cleanup' if $buf =~ /\e\[\?1049l/;
send_keys("\e[B");
expect(qr/\e\[1mTwo/,'selected before focus changes');
my $marker=length $buf;
send_keys("\e[O\e[I");
my $focus_output=substr($buf,$marker);
die 'focus-in did not repaint from home' unless $focus_output =~ /\e\[H.*\e\[1mTwo/s;
$marker=length $buf;
send_keys("\x0c");
die 'Ctrl-L did not repaint' unless substr($buf,$marker) =~ /\e\[H/;
$marker=length $buf;
$pty->set_winsize(12,36,0,0);
pump(1.3);
my $small_output=substr($buf,$marker);
die 'resize did not use compact title' unless plain($small_output) =~ /SATELLITE/;
die 'resize lost selection' unless $small_output =~ /\e\[1mTwo/;
die 'narrow screen still contains block title' if plain($small_output) =~ /#####  ###/;
$marker=length $buf;
$pty->set_winsize(24,80,0,0);
pump(1.3);
my $large_output=substr($buf,$marker);
die 'enlarging did not restore block title' unless plain($large_output) =~ /#####  ###/;
die 'enlarging lost selection' unless $large_output =~ /\e\[1mTwo/;
die 'relative vertical cursor movement remains' if $buf =~ /\e\[\d+[AB]/;
send_keys("\n");
expect(qr/SELECTED=1 STATUS=0/,'selection after focus and resize');
finish();
my $enters=()=$buf =~ /\e\[\?1049h/g;
my $exits=()=$buf =~ /\e\[\?1049l/g;
die "unbalanced alternate screen lifecycle: $enters/$exits" unless $enters==1 && $exits==1;
die 'focus mode not disabled' unless $buf =~ /\e\[\?1004l/;
print "PASS focus-in, Ctrl-L, shrink/grow resize, preserved selection, and alternate-screen cleanup\n";
