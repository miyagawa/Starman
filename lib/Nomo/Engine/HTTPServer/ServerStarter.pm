package Nomo::Engine::HTTPServer::ServerStarter;
use strict;
use Server::Starter;

sub wrap {
    my($class, $cb, $opts) = @_;

    my ($hostport, $fd) = %{Server::Starter::server_ports()};
    if ($hostport =~ /(.*):(\d+)/) {
        $opts->{host} = $1;
        $opts->{port} = $2;
    } else {
        $opts->{port} = $hostport;
    }

    my $server = $cb->(%$opts);

    $server->{listen_sock} = IO::Socket::INET->new(
        Proto => 'tcp',
    ) or die "failed to create socket:$!";

    $server->{listen_sock}->fdopen($fd, 'w')
        or die "failed to bind to listening socket:$!";

    $server;
}

1;
