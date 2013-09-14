use strict;
use Test::TCP;
use IO::Socket::INET;
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

        my $request = HTTP::Request->new(
            HEAD => '/', [ Host => 'localhost' ]
        );
        $request->protocol('HTTP/1.1');

        $socket->send($request->as_string("\r\n"));
        $socket->shutdown(1);

        my $data;
        while ($socket->connected) {
            my $buf;
            $socket->recv($buf, 1024);
            $data .= $buf;
        }

        my $res = HTTP::Response->parse($data);

        is $res->content, '';
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->auto(port => $port, host => '127.0.0.1');

        $server->run(sub { return [ 200, [], [] ] });
    }
);

done_testing;
