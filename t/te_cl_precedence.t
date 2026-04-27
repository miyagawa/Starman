use strict;
use warnings;
use Test::TCP;
use IO::Socket::INET qw/ SHUT_WR /;
use HTTP::Response;
use Plack::Loader;
use Test::More;

# RFC 7230 §3.3.3: when both Transfer-Encoding and Content-Length are
# present, Transfer-Encoding must override Content-Length.
test_tcp(
    client => sub {
        my $port = shift;

        my $socket = IO::Socket::INET->new(
            PeerAddr => 'localhost',
            PeerPort => $port,
            Proto    => 'tcp',
        ) or die "Failed to connect: $!";

        # Chunked body encodes "Hello World" (0xb = 11 bytes).
        # Content-Length: 5 is intentionally wrong — it must be ignored.
        my $chunked_body = "b\r\nHello World\r\n0\r\n\r\n";
        my $req = "POST / HTTP/1.1\r\n"
                . "Host: localhost\r\n"
                . "Transfer-Encoding: chunked\r\n"
                . "Content-Length: 5\r\n"
                . "\r\n"
                . $chunked_body;

        $socket->send($req);
        $socket->shutdown(SHUT_WR);

        my $response = '';
        while (1) {
            my $n = $socket->sysread(my $buf, 4096);
            last unless $n;
            $response .= $buf;
        }

        my $res = HTTP::Response->parse($response);
        is $res->content, 'Hello World',
            'Transfer-Encoding: chunked takes precedence over Content-Length';
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Starman', port => $port, host => '127.0.0.1');
        $server->run(sub {
            my $env = shift;
            my $body = '';
            $env->{'psgi.input'}->read($body, 8192);
            return [ 200, [ 'Content-Type', 'text/plain', 'Content-Length', length($body) ], [ $body ] ];
        });
    },
);

done_testing;
