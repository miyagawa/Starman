use strict;
use Test::TCP;
use IO::Socket::INET qw/ SHUT_WR /;
use HTTP::Request;
use HTTP::Response;
use Plack::Loader;
use Test::More;

$ENV{PLACK_SERVER} = 'Starman';

test_tcp(
    client => sub {
        my $port = shift;

        my $socket = IO::Socket::INET->new(
            PeerAddr => 'localhost',
            PeerPort => $port,
            Proto => 'tcp'
        ) or die "Failed to connect to server: $!";

        my $req_string = join("\r\n", "POST / HTTP/1.1", "Host: localhost", "Expect: 100-CONTINUE", "Content-Length: 0", "", "");

        $socket->send($req_string);
        $socket->shutdown(SHUT_WR);

        my $data = "";
        while ($socket->connected) {
            my $buf;
            $socket->recv($buf, 1024);
            $data .= $buf;
        }

        my @lines = split /\r\n/, $data;

        is $lines[0], "HTTP/1.1 100 Continue";
        is $lines[1], "";
        is $lines[2], "HTTP/1.1 200 OK";

    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->auto(port => $port, host => '127.0.0.1');

        $server->run(sub { return [ 200,  [ 'Content-Type', 'text/plain' ], ["ok"] ] });
    }
);

done_testing;
