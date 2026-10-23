use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Test::More;

my $app = sub {
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => 2 ], [ "OK" ] ];
};

my $field = "X-Big: " . ("a" x 1000) . "\r\n";

with_starman($app, sub {
    my $port = shift;

    my($res, $eof) = raw_request($port,
        "GET / HTTP/1.1\r\nHost: localhost\r\n" . $field x 200,
        keep_open => 1, timeout => 3);
    like $res, qr{\AHTTP/1\.[01] 431 }, 'unterminated oversized header is rejected without waiting for the end';
    like $res, qr/^Connection: close\r$/m, '... and the connection is closed';
    ok $eof, '... by the server';

    $res = raw_request($port,
        "GET / HTTP/1.1\r\nHost: localhost\r\n" . $field x 200 . "\r\n");
    like $res, qr{\AHTTP/1\.[01] 431 }, 'complete oversized header is rejected';
    unlike $res, qr/OK\z/, '... without dispatching the app';

    $res = raw_request($port,
        "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n" . $field x 60 . "\r\n");
    like $res, qr{\AHTTP/1\.1 200 .*\r\n\r\nOK\z}s, 'header under the limit is accepted';
}, read_timeout => 10);

done_testing;
