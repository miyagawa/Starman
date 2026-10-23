use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Test::More;

my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    my $res = "$env->{PATH_INFO}:$body";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

my $chunked_body = "5\r\nHELLO\r\n0\r\n\r\n";

with_starman($app, sub {
    my $port = shift;

    my %expect = (
        'gzip, chunked'    => 501,
        'gzip'             => 400,
        'chunked, gzip'    => 400,
        'chunked, chunked' => 400,
        'identity'         => 400,
        'chunked;foo=bar'  => 400,
        ''                 => 400,
    );
    for my $te (sort keys %expect) {
        my($res, $eof) = raw_request($port,
            "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: $te\r\nContent-Length: 3\r\n\r\n"
          . "$chunked_body",
            keep_open => 1, timeout => 3);
        like $res, qr{\AHTTP/1\.1 $expect{$te} }, "Transfer-Encoding '$te' is rejected with $expect{$te}";
        unlike $res, qr{/a:}, "Transfer-Encoding '$te' does not dispatch the app";
        like $res, qr/^Connection: close\r$/m, "Transfer-Encoding '$te' closes the connection";
        ok $eof, "... and the server closes it";
    }

    my $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n$chunked_body");
    like $res, qr{\AHTTP/1\.1 400 }, 'duplicate Transfer-Encoding: chunked headers are rejected';

    $res = raw_request($port,
        "POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\nContent-Length: 15\r\n\r\n$chunked_body");
    like $res, qr{\AHTTP/1\.0 400 }, 'Transfer-Encoding in an HTTP/1.0 request is rejected';
    unlike $res, qr{/a:}, '... without dispatching the app';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: Chunked \r\nConnection: close\r\n\r\n$chunked_body");
    like $res, qr{\r\n\r\n/a:HELLO\z}, 'Transfer-Encoding is case-insensitive and whitespace-trimmed';

    my $eof;
    ($res, $eof) = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nContent-Length: 3\r\n\r\n$chunked_body"
      . "GET /b HTTP/1.1\r\nHost: localhost\r\n\r\n",
        keep_open => 1, timeout => 3);
    like $res, qr{\r\n\r\n/a:HELLO\z}, 'Transfer-Encoding overrides Content-Length';
    like $res, qr/^Connection: close\r$/m, '... and the connection is closed after the response';
    ok $eof, '... by the server';
    unlike $res, qr{/b:}, '... so no further request is read from it';
});

done_testing;
