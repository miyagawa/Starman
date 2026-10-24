use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use RawHTTP;
use Starman::Server;
use IO::Socket::INET;
use IO::Select;
use Time::HiRes ();
use Test::More;

# CVE-2026-115817: with default settings, a client that stops sending
# the request body must not hold a worker for longer than read_timeout
# (5 seconds) between reads.

my $app = sub {
    my $env = shift;
    my $body = '';
    $env->{'psgi.input'}->read($body, 8192);
    my $res = "$env->{PATH_INFO}:$body";
    return [ 200, [ 'Content-Type' => 'text/plain', 'Content-Length' => length $res ], [ $res ] ];
};

sub stall {
    my($port, $req) = @_;
    my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp')
        or die "Failed to connect: $!";
    syswrite $sock, $req;
    return $sock;
}

sub read_all {
    my($sock, $timeout) = @_;
    my $sel = IO::Select->new($sock);
    my $deadline = Time::HiRes::time() + $timeout;
    my($res, $eof) = ('', 0);
    while ((my $left = $deadline - Time::HiRes::time()) > 0) {
        last unless $sel->can_read($left);
        my $n = sysread $sock, my $buf, 65536;
        unless ($n) { $eof = 1; last }
        $res .= $buf;
    }
    return ($res, $eof);
}

# Defaults: one worker, read_timeout 5, body_timeout 300
with_starman($app, sub {
    my $port = shift;

    my $stalled = stall($port,
        "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100000000000\r\n\r\nabc");
    Time::HiRes::sleep(0.2);

    my $res = raw_request($port, "GET /b HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", timeout => 9);
    like $res, qr{\r\n\r\n/b:\z}, 'a second client is served while a body is stalled';

    my($stalled_res, $eof) = read_all($stalled, 3);
    like $stalled_res, qr{\AHTTP/1\.1 408 }, 'the stalled body times out with 408';
    ok $eof, '... and the server closes the connection';
    unlike $stalled_res, qr{/a:}, '... without dispatching the app';
});

with_starman($app, sub {
    my $port = shift;

    for my $case (
        [ 'chunk data'      => "Transfer-Encoding: chunked\r\n\r\na\r\nabc" ],
        [ 'chunk size line' => "Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n" ],
        [ 'trailer section' => "Transfer-Encoding: chunked\r\n\r\n0\r\nX: 1\r\n" ],
        [ 'Content-Length body after some data' => "Content-Length: 10\r\n\r\nabc" ],
    ) {
        my($what, $req) = @$case;
        my($res, $eof) = raw_request($port, "POST /a HTTP/1.1\r\nHost: localhost\r\n$req",
            keep_open => 1, timeout => 4);
        like $res, qr{\AHTTP/1\.1 408 }, "stall in the $what times out after read_timeout";
        ok $eof, '... and the server closes the connection';
    }

    my $res = raw_request($port,
        [ "POST /a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\nConnection: close\r\n\r\n", "a", "b", "c" ],
        pause => 0.3);
    like $res, qr{\r\n\r\n/a:abc\z}, 'a body whose reads arrive within read_timeout is read';
}, read_timeout => 1);

# The deadlines must not be rounded to whole seconds: a body that arrives
# well within body_timeout must be read even if reading it crosses a
# second boundary.
{
    package SlowFeed;
    sub TIEHANDLE { my($class, @data) = @_; bless [ @data ], $class }
    sub READ {
        my $self = shift;
        return 0 unless @$self;
        Time::HiRes::sleep(0.1);
        $_[0] = shift @$self;
        return length $_[0];
    }
}

{
    tie *SOCK, 'SlowFeed', "a", "b", "c";
    my $server = bless {
        client  => { inputbuf => '' },
        server  => { client => \*SOCK },
        options => { read_timeout => 1, body_timeout => 1 },
    }, 'Starman::Server';

    # Start just before a second boundary
    my $now = Time::HiRes::time();
    Time::HiRes::sleep(int($now) + 1.95 - $now);

    my $status = eval { $server->_prepare_env({ REQUEST_METHOD => 'POST', CONTENT_LENGTH => 3 }) };
    alarm 0;
    is $@, '', 'a body read across a second boundary does not time out early';
    ok !$status, '... and is accepted';
    untie *SOCK;
}

done_testing;
