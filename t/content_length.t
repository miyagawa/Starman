use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Test::More;

my $dispatched = 0;
my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    my $res = "$env->{PATH_INFO}:" . (defined $env->{CONTENT_LENGTH} ? $env->{CONTENT_LENGTH} : '') . ":$body";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

with_starman($app, sub {
    my $port = shift;

    for my $cl ('-5', '5abc', '+5', '5, 9', '5,9', '', '0x5', '1e3', '99999999999999999999') {
        my $res = raw_request($port,
            "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: $cl\r\n\r\n"
          . "HELLOGET /smuggled HTTP/1.1\r\nHost: localhost\r\n\r\n");
        like $res, qr{\AHTTP/1\.1 400 }, "Content-Length '$cl' is rejected with 400";
        unlike $res, qr{/a:|/smuggled}, "Content-Length '$cl' does not dispatch the app";
        like $res, qr/^Connection: close\r$/m, "Content-Length '$cl' closes the connection";
    }

    my $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\nContent-Length: 9\r\n\r\nHELLO");
    like $res, qr{\AHTTP/1\.1 400 }, 'conflicting duplicate Content-Length headers are rejected';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\nContent-Length: 5\r\nConnection: close\r\n\r\nHELLO");
    like $res, qr{\AHTTP/1\.1 200 .*\r\n\r\n/a:5:HELLO\z}s, 'identical duplicate Content-Length headers are accepted';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 005\r\nConnection: close\r\n\r\nHELLO");
    like $res, qr{\r\n\r\n/a:5:HELLO\z}, 'leading zeros are accepted and normalized';
});

done_testing;
