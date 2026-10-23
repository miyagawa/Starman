use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Test::More;

# CVE-2026-115817: reading the request body must be limited by a total
# deadline (body_timeout), not only the request headers.

my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    sleep 2 if $env->{PATH_INFO} eq '/slow';
    my $res = "$env->{PATH_INFO}:$body";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

with_starman($app, sub {
    my $port = shift;

    my($res, $eof) = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\nabc",
        keep_open => 1, timeout => 4);
    like $res, qr{\AHTTP/1\.1 408 }, 'stalled Content-Length body times out with 408';
    like $res, qr/^Connection: close\r$/m, '... and the connection is closed';
    ok $eof, '... by the server';
    unlike $res, qr{/a:}, '... without dispatching the app';

    # One byte every 0.3 seconds never trips a per-read idle timeout
    ($res, $eof) = raw_request($port,
        [ "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n", ("x") x 5 ],
        pause => 0.3, keep_open => 1, timeout => 4);
    like $res, qr{\AHTTP/1\.1 408 }, 'trickled Content-Length body times out with 408';
    ok $eof, '... and the server closes the connection';

    ($res, $eof) = raw_request($port,
        [ "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n", ("1\r\nx\r\n") x 5 ],
        pause => 0.3, keep_open => 1, timeout => 4);
    like $res, qr{\AHTTP/1\.1 408 }, 'trickled chunked body times out with 408';
    ok $eof, '... and the server closes the connection';

    $res = raw_request($port,
        "POST /slow HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc",
        timeout => 5);
    like $res, qr{\AHTTP/1\.1 200 .*\r\n\r\n/slow:abc\z}s, 'the app itself is not limited by body_timeout';

    $res = raw_request($port,
        [ "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\nConnection: close\r\n\r\n", "a", "b", "c" ],
        pause => 0.1);
    like $res, qr{\r\n\r\n/a:abc\z}, 'a body that arrives in time is read';
}, body_timeout => 1);

done_testing;
