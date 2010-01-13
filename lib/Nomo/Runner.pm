package Nomo::Runner;
use strict;
use Plack::Runner;
use Getopt::Long;

my $pidfile;

sub run {
    my $class = shift;

    local @ARGV = @_;

    my $pid;
    my $daemonize;

    Getopt::Long::Configure("no_ignore_case", "pass_through");
    GetOptions(
        "pid=s",       \$pid,
        "D|daemonize", \$daemonize,
    );

    daemonize()     if $daemonize;
    write_pid($pid) if $pid;

    Plack::Runner->run(@ARGV);
}

sub _fork_or_die {
    my $pid = fork;
    die "Unable to fork" unless defined $pid;
    exit 0 if $pid;
}

sub daemonize {
    require POSIX;

    _fork_or_die;
    POSIX::setsid() or die "Can't detach: $!";

    # Fork again to ensure that daemon never reacquires a control terminal
    _fork_or_die;

    open STDIN, "</dev/null";
    open STDOUT, ">/dev/null";
    open STDERR, ">&STDOUT";

#    chdir "/";
    umask 0;
}

sub write_pid {
    my $file = shift;

    open my $fh, ">", $file or die "$file: $!";
    print $fh $$, "\n";

    $pidfile = $file;
    $SIG{INT} = $SIG{TERM} = sub { unlink $file; exit 0 };
}

END {
    unlink $pidfile if $pidfile;
}

1;
