use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use File::Temp qw(tempdir);
use Test::More;

# CVE-2026-115823: responses to HEAD, and 1xx/204/304 responses, must not
# carry a body, or the bytes are read as the start of the next response.

my $dir = tempdir(CLEANUP => 1);

{
    package MarkerBody;
    sub new { my($class, $name) = @_; bless { name => $name, lines => [ "HEL", "LO" ] }, $class }
    sub _mark { open my $fh, '>', "$dir/$_[0]{name}.$_[1]" or die $!; close $fh }
    sub getline { my $self = shift; $self->_mark('getline'); shift @{ $self->{lines} } }
    sub close { $_[0]->_mark('close') }
}

my $app = sub {
    my $env = shift;
    my $path = $env->{PATH_INFO};
    my($status) = $path =~ m{/(\d{3})} ? $1 : 200;

    if ($path =~ m{^/stream}) {
        return sub {
            my $writer = shift->([ $status, [ 'Content-Type' => 'text/plain', ($path =~ /cl/ ? ('Content-Length' => 5) : ()) ] ]);
            $writer->write("HEL");
            $writer->write("LO");
            $writer->close;
        };
    }
    if ($path =~ m{^/te-only}) {
        return [ $status, [ 'Content-Type' => 'text/plain', 'Transfer-Encoding' => 'chunked' ], [ "HELLO" ] ];
    }
    if ($path =~ m{^/te}) {
        return [ $status, [ 'Content-Type' => 'text/plain', 'Content-Length' => 5, 'Transfer-Encoding' => 'chunked' ], [ "HELLO" ] ];
    }
    if ($path =~ m{^/object/(\w+)}) {
        return [ $status, [ 'Content-Type' => 'text/plain', 'Content-Length' => 5 ], MarkerBody->new($1) ];
    }
    if ($path =~ m{^/nocl}) {
        return [ $status, [ 'Content-Type' => 'text/plain' ], [ "HELLO" ] ];
    }
    return [ $status, [ 'Content-Type' => 'text/plain', 'Content-Length' => 5 ], [ "HELLO" ] ];
};

my $next = "GET /next HTTP/1.1\r\nHost: localhost\r\n\r\n";

with_starman($app, sub {
    my $port = shift;
    my $res;

    my @cases = (
        [ HEAD => '/' ],
        [ HEAD => '/nocl' ],
        [ HEAD => '/stream' ],
        [ HEAD => '/stream-cl' ],
        [ HEAD => '/te' ],
        [ HEAD => '/te-only' ],
        [ HEAD => '/object/head' ],
        [ GET  => '/204' ],
        [ GET  => '/304' ],
        [ GET  => '/nocl/204' ],
        [ GET  => '/stream/204' ],
        [ GET  => '/stream/304' ],
        [ GET  => '/te/204' ],
        [ GET  => '/te-only/304' ],
        [ GET  => '/object/s204/204' ],
        [ GET  => '/103' ],
        [ GET  => '/te/103' ],
    );

    for my $case (@cases) {
        my($method, $path) = @$case;
        $res = raw_request($port, "$method $path HTTP/1.1\r\nHost: localhost\r\n\r\n$next");
        my($first, $rest) = split /\r\n\r\n/, $res, 2;
        $rest = '' unless defined $rest;
        like $first, qr{\AHTTP/1\.1 \d{3} }, "$method $path: response";
        like $rest, qr{\AHTTP/1\.1 200 OK\r\n}, "$method $path: no body bytes before the next response";
        like $rest, qr{\r\n\r\nHELLO\z}, "$method $path: the next response is intact";

        # RFC 9112 6.1 and RFC 9110 8.6
        if ($path =~ m{/(?:1\d\d|204)$}) {
            unlike $first, qr/^(?:Content-Length|Transfer-Encoding):/mi, "$method $path: no Content-Length or Transfer-Encoding";
        }
    }

    $res = raw_request($port, "GET /304 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
    like $res, qr/^Content-Length: 5\r$/m, '304 keeps the Content-Length supplied by the app';

    $res = raw_request($port, "HEAD / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
    like $res, qr/^Content-Length: 5\r$/m, 'HEAD keeps the Content-Length supplied by the app';

    ok -e "$dir/head.close", 'HEAD: body object is closed';
    ok !-e "$dir/head.getline", 'HEAD: body object is not read';
    ok -e "$dir/s204.close", '204: body object is closed';
    ok !-e "$dir/s204.getline", '204: body object is not read';
});

done_testing;
