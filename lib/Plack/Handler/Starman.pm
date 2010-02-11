package Plack::Handler::Starman;
use strict;
use HTTP::Server::Starman::Server;

sub new {
    my $class = shift;
    bless { @_ }, $class;
}

sub run {
    my($self, $app) = @_;

    if ($ENV{SERVER_STARTER_PORT}) {
        require Net::Server::SS::PreFork;
        @HTTP::Server::Starman::Server::ISA = qw(Net::Server::SS::PreFork); # Yikes.
    }

    HTTP::Server::Starman::Server->new->run($app, {%$self});
}

1;

__END__

=head1 NAME

Plack::Handler::Starman - Plack adapter for Starman

=head1 SYNOPSIS

  plackup -s Starman

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Starman>

=cut


