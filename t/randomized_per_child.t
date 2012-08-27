use strict;
use warnings;
use Test::TCP;
use LWP::UserAgent;
use FindBin;
use Test::More;
use File::Temp qw/tempfile/;

my $max = 5;
my $min = 3;
local $ENV{STARMAN_DEBUG} = 1;

my ($error_fh , $error_log) = tempfile(CLEANUP=>0);
close $error_fh;

my $s = Test::TCP->new(
    code => sub {
        my $port = shift;
        open STDERR, '>>', $error_log;
        exec "$^X bin/starman --port $port --max-requests=$max --min-requests=$min --workers=1 '$FindBin::Bin/rand.psgi'";
    },
);

my $ua = LWP::UserAgent->new;
for (1..100) {
    $ua->get("http://localhost:" . $s->port);
}

open( my $fh, $error_log) or die $!;
my ($req_min, $req_max) = ($min, $max);
my $n;
while ( my $log = <$fh> ) {
    if ( $log =~ m!Child leaving \((\d+)\)! ) {
        $n = $1;
        $min = $n
            if $n < $req_min;
        $max = $n
            if $n > $req_max;
    }
}

ok $n;
is $req_min, $min, "min";
is $req_max, $max, "max";
unlink $error_log;
done_testing();


