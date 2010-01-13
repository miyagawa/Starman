package Nomo::Engine::HTTPServer;
use strict;
use Plack::Util;
use HTTP::Parser::XS;
use HTTP::Server::PSGI;

sub new {
    my($class, %opts) = @_;
    HTTP::Server::PSGI->new(%opts);
}

1;
