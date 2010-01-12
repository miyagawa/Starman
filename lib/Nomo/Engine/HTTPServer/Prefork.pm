package Nomo::Engine::HTTPServer::Prefork;
use strict;

sub wrap {
    my($class, $cb, $opts) = @_;
    $opts->{parent} = "HTTP::Server::PSGI::Prefork";
    $cb->($opts);
}

1;
