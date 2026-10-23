use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Test::More;

# Empty lines before a request line are ignored (RFC 9112 section 2.2),
# and each request is parsed and dispatched exactly once, with both the
# XS and the pure-Perl HTTP::Parser::XS backends.

my $app = sub {
    my $env = shift;
    my $res = "[$env->{REQUEST_METHOD} $env->{PATH_INFO}]";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res, 'X-Backend' => $HTTP::Parser::XS::BACKEND ], [ $res ] ];
};

for my $backend (qw(xs pp)) {
    local $ENV{PERL_HTTP_PARSER_XS} = $backend;
    with_starman($app, sub {
        my $port = shift;

        my $res = raw_request($port, "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
        like $res, qr/^X-Backend: $backend\r$/m, "$backend: server uses the $backend parser";

        $res = raw_request($port,
            "\r\n\r\nPOST /charge HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n");
        my $count = () = $res =~ /\[POST \/charge\]/g;
        is $count, 1, "$backend: request after empty lines is dispatched exactly once";

        $res = raw_request($port, "\r\n\r\n");
        unlike $res, qr/\[/, "$backend: empty lines alone are not dispatched";

        $res = raw_request($port,
            "GET /a HTTP/1.1\r\nHost: localhost\r\n\r\n\r\nGET /b HTTP/1.1\r\nHost: localhost\r\n\r\n");
        like $res, qr/\[GET \/a\].*\[GET \/b\]/s, "$backend: CRLF between pipelined requests is ignored";
        $count = () = $res =~ /\[GET/g;
        is $count, 2, "$backend: ... and each request is dispatched once";
    });
}

done_testing;
