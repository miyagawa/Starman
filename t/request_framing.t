use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Starman::Server;
use Test::More;

# Each request body must be read exactly, leaving the bytes that follow
# it for the next request.

my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    my $res = "[$env->{REQUEST_METHOD} $env->{PATH_INFO}:" . (defined $env->{CONTENT_LENGTH} ? $env->{CONTENT_LENGTH} : '') . ":$body]";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

my $get_b = "GET /b HTTP/1.1\r\nHost: localhost\r\n\r\n";

with_starman($app, sub {
    my $port = shift;

    my $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n\r\nabc"
      . "POST /b HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n\r\nxyz");
    like $res, qr/\[POST \/a:3:abc\]/, 'Content-Length body is read exactly';
    like $res, qr/\[POST \/b:3:xyz\]/, '... and the pipelined POST that follows is dispatched';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n$get_b");
    like $res, qr/\[POST \/a:3:abc\]/, 'chunked body is read';
    like $res, qr/\[GET \/b::\]/, '... and the pipelined GET after the terminator is dispatched';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\nX-Trailer: 1\r\nY: 2\r\n\r\n"
      . "POST /b HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n\r\nxyz");
    like $res, qr/\[POST \/a:3:abc\]/, 'chunked body with trailers is read';
    like $res, qr/\[POST \/b:3:xyz\]/, '... trailers are consumed and the next request is dispatched';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n0\r\n\r\n");
    like $res, qr/\[POST \/a:0:\]/, 'empty chunked body has CONTENT_LENGTH 0';

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n"
      . ("X-Trailer: " . ("x" x 100) . "\r\n") x 200 . "\r\n");
    like $res, qr{\AHTTP/1\.1 400 }, 'oversized trailer section is rejected';
    unlike $res, qr/\[POST/, '... without dispatching the app';

    my %truncated = (
        'Content-Length body'    => "Content-Length: 10\r\n\r\nabc",
        'chunk data'             => "Transfer-Encoding: chunked\r\n\r\na\r\nabc",
        'chunk size line'        => "Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n1",
        'chunk CRLF'             => "Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r",
        'trailer section'        => "Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\nX: 1\r\n",
        'last chunk'             => "Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n",
    );
    for my $what (sort keys %truncated) {
        $res = raw_request($port, "POST /a HTTP/1.1\r\nHost: localhost\r\n$truncated{$what}");
        like $res, qr{\AHTTP/1\.1 400 }, "EOF in the $what is an error";
        unlike $res, qr/\[POST/, "EOF in the $what does not dispatch the app";
    }

    $res = raw_request($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabcXY0\r\n\r\n");
    like $res, qr{\AHTTP/1\.1 400 }, 'chunk data not followed by CRLF is rejected';
});

# Feed the same request split at every byte boundary
{
    package FeedHandle;
    sub TIEHANDLE { my($class, @data) = @_; bless [ @data ], $class }
    sub READ {
        my $self = shift;
        return 0 unless @$self;
        $_[0] = shift @$self;
        return length $_[0];
    }
}

my $body = "5\r\nHELLO\r\n6;x=y\r\n WORLD\r\n0\r\nX-T: v\r\n\r\n";
my $next = "GET /next HTTP/1.1\r\n";
my $input = $body . $next;

my @cases = map { [ substr($input, 0, $_), substr($input, $_) ] } 0 .. length($input) - 1;
push @cases, [ split //, $input ];

for my $case (@cases) {
    my @pieces = grep length, @$case;
    tie *SOCK, 'FeedHandle', @pieces;
    my $server = bless {
        client => { inputbuf => '' },
        server => { client => \*SOCK },
    }, 'Starman::Server';

    my $env = { REQUEST_METHOD => 'POST', HTTP_TRANSFER_ENCODING => 'chunked' };
    my $status = $server->_prepare_env($env);
    my $desc = join '|', map { (my $s = $_) =~ s/\r/\\r/g; $s =~ s/\n/\\n/g; $s } @pieces;

    ok !$status, "segmented input is accepted: $desc" or next;
    my $got = '';
    $env->{'psgi.input'}->read($got, 8192);
    my $leftover = $server->{client}{inputbuf};
    while (defined(my $more = shift @{ tied *SOCK })) { $leftover .= $more }
    is "$got|$env->{CONTENT_LENGTH}|$leftover", "HELLO WORLD|11|$next", "... body and leftover are exact: $desc";
    untie *SOCK;
}

done_testing;
