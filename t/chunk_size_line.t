use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Time::HiRes ();
use Test::More;

my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    my $res = "$env->{PATH_INFO}:$body";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

my $head = "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n";

with_starman($app, sub {
    my $port = shift;

    # CVE-2026-115822: hex digits followed by LF+CRLF made the old
    # size-line regex backtrack quadratically.
    my $t0  = Time::HiRes::time();
    my $res = raw_request($port, $head . ("f" x 32768) . "\n\r\n");
    my $elapsed = Time::HiRes::time() - $t0;
    like $res, qr{\AHTTP/1\.1 400 }, 'long size line ending in LF+CRLF is rejected';
    cmp_ok $elapsed, '<', 1, '... quickly';
    unlike $res, qr{/a:}, '... without dispatching the app';

    # An unterminated size line must not be buffered forever
    my $eof;
    ($res, $eof) = raw_request($port, $head . ("f" x 8192), keep_open => 1, timeout => 3);
    like $res, qr{\AHTTP/1\.1 400 }, 'size line over the length limit is rejected without waiting for CRLF';
    ok $eof, '... and the server closes the connection';

    for my $line ("5 junk", "0x5", "-5", "+5", "", "5\r", "5;ext\rx", " 5", "fffffffffffffffffffff") {
        (my $esc = $line) =~ s/\r/\\r/g;
        $res = raw_request($port, $head . "$line\r\nHELLO\r\n0\r\n\r\n");
        like $res, qr{\AHTTP/1\.1 400 }, "size line '$esc' is rejected";
        unlike $res, qr{/a:}, "size line '$esc' does not dispatch the app";
    }

    for my $line ("5", "05", "000000000000000000000000005", "5;name=value", "5 ; name=\"quoted\"", "5;a;b=c") {
        $res = raw_request($port, $head . "$line\r\nHELLO\r\n0\r\n\r\n");
        like $res, qr{\AHTTP/1\.1 200 .*\r\n\r\n/a:HELLO\z}s, "size line '$line' is accepted";
    }

    $res = raw_request($port, [ $head . "5", "\r", "\nHEL", "LO\r\n0", "\r\n\r\n" ]);
    like $res, qr{\r\n\r\n/a:HELLO\z}, 'size line split across reads is parsed';
});

done_testing;
