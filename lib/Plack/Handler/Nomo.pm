package Plack::Handler::Nomo;
use strict;
use Nomo::Server;

sub new {
    my $class = shift;
    bless { @_ }, $class;
}

sub run {
    my($self, $app) = @_;

    if ($ENV{SERVER_STARTER_PORT}) {
        require Net::Server::SS::PreFork;
        @Nomo::Server::ISA = qw(Net::Server::SS::PreFork); # Yikes.
    }

    Nomo::Server->new->run($app, {%$self});
}

1;

__END__

=head1 NAME

Plack::Handler::Nomo - Plack adapter for Nomo

=head1 SYNOPSIS

  plackup -s Nomo

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Nomo>

=cut


