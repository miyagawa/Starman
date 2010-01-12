package Nomo::Engine::HTTPServer;
use strict;
use Plack::Util;
use HTTP::Parser::XS;

sub new {
    my($class, %opts) = @_;

    my $parent = $opts{parent} || "HTTP::Server::PSGI";
    Plack::Util::load_class($parent)->new(%opts);
}

1;
