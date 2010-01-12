package Nomo::Engine::HTTPServer::ControlFreak;
use strict;

sub wrap {
    my($class, $cb, $options) = @_;

    my $server = $cb->($options);

    open my $socket, "<&=0"
        or die "Cannot open stdin: $!";
    bless $socket, "IO::Socket::INET";
    $server->{listen_sock} = $socket;

    $server;
}

1;
