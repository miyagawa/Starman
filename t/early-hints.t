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

        my $req_string = join("\r\n", "GET / HTTP/1.1", "Host: localhost", "", "");

        $socket->send($req_string);
        $socket->shutdown(SHUT_WR);

        my $data = "";
        while ($socket->connected) {
            my $buf;
            $socket->recv($buf, 1024);
            $data .= $buf;
        }

        my @lines = split /\r\n/, $data;

        is $lines[0], "HTTP/1.1 103 Early Hints";
        is $lines[1], "Link: </style.css>; rel=preload";
        is $lines[2], "";
        is $lines[3], "HTTP/1.1 200 OK";

    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->auto(port => $port, host => '127.0.0.1');

        $server->run(sub {
            my $env = shift;
            $env->{'psgix.informational'}->( 103, [
                "Link" => "</style.css>; rel=preload"
            ] );
            return [ 200,  [ 'Content-Type', 'text/plain' ], ["ok"] ]
        });
    }
);

done_testing;
