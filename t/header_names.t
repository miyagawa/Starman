use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Test::More;

# Header field names must be tokens followed directly by ":", and only the
# exact names Content-Length and Transfer-Encoding may frame the body.
# Otherwise the parser normalizes names a front end does not recognize,
# e.g. "Content-Length : 5" or "Transfer_Encoding: chunked".

my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    my $res = "[$env->{PATH_INFO}:$body]";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

my $next = "GET /smuggled HTTP/1.1\r\nHost: localhost\r\n\r\n";

for my $backend (qw(xs pp)) {
    local $ENV{PERL_HTTP_PARSER_XS} = $backend;
    with_starman($app, sub {
        my $port = shift;

        my @bad = (
            "Content-Length : 5",
            "Content-Length\t: 5",
            "Content_Length: 5",
            "Transfer_Encoding: chunked",
            "transfer_encoding: chunked",
            "X-Foo: a\r\n folded",
            "X-Foo: a\r\n\tfolded",
            "Bad\x01Name: 1",
            "Bad Name: 1",
            ": no-name",
        );
        for my $field (@bad) {
            (my $desc = $field) =~ s/([^\x20-\x7e])/sprintf '\\x%02x', ord $1/ge;
            my $res = raw_request($port,
                "POST /a HTTP/1.1\r\nHost: localhost\r\n$field\r\n\r\n0\r\n\r\n$next");
            like $res, qr{\AHTTP/1\.[01] 400 }, "$backend: '$desc' is rejected";
            unlike $res, qr/\[/, "$backend: '$desc' does not dispatch the app";
        }

        my $res = raw_request($port,
            "POST /a HTTP/1.1\r\nHost: localhost\r\nX-Foo_Bar: 1\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc");
        like $res, qr{\r\n\r\n\[/a:abc\]\z}, "$backend: other names with an underscore are accepted";

        $res = raw_request($port,
            "POST /a HTTP/1.1\r\nHost: localhost\r\ncontent-length:3\r\nConnection: close\r\n\r\nabc");
        like $res, qr{\r\n\r\n\[/a:abc\]\z}, "$backend: lowercase name without space after the colon is accepted";
    });
}

done_testing;
