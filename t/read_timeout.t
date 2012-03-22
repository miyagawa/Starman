use Test::TCP;
use FindBin;
use Test::More;
use IO::Socket ':crlf';
use Time::HiRes qw(tv_interval gettimeofday);

for my $timeout (qw(1 2 5)) {
    my $s = Test::TCP->new(
        code => sub {
            my $port = shift;
            exec "$^X bin/starman --read-timeout=$timeout --port $port --workers=1 $FindBin::Bin/rand.psgi";
        },
    );

    my $port = $s->port;
    my $sock = IO::Socket::INET->new("localhost:$port");
    my $t0 = [gettimeofday];
    print $sock "GET /incomplete_headers HTTP/1.0$CRLF";
    my $nr = read $sock, my $response, 1024;
    my $iv = tv_interval($t0);
    is $response, '', 'no data back';
    if ($!) {
        skip 2, "I/O error";
    }
    ok(defined($nr) && $nr == 0, 'no data back');
    my $error_margin = sprintf "%.3f", abs($iv - $timeout) / $iv;
    my $is_close = $error_margin < 0.05 ? 1 : 0;
    ok $is_close, "timeout roughly $timeout ($error_margin)";
}

done_testing;
