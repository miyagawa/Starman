package Plack::Handler::Starman;
use strict;
use Starman::Server;

sub new {
    my $class = shift;
    bless { @_ }, $class;
}

sub run {
    my($self, $app) = @_;

    if ($ENV{SERVER_STARTER_PORT}) {
        require Net::Server::SS::PreFork;
        @Starman::Server::ISA = qw(Net::Server::SS::PreFork); # Yikes.
    }

    my %nsa;
    while (my($key, $value) = each %$self) {
        $key =~ s/^net_server_// or next;
        $nsa{$key} = $value;
    }
    $self->{net_server_args} = \%nsa if %nsa;

    Starman::Server->new->run($app, {%$self});
}

1;

__END__

=head1 NAME

Plack::Handler::Starman - Plack adapter for Starman

=head1 SYNOPSIS

  plackup -s Starman

=head1 DESCRIPTION

This handler exists for the C<plackup> compatibility. Essentially,
C<plackup -s Starman> is equivalent to C<starman --preload-app>,
because the C<starman> executable delay loads the application by
default. See L<starman> for more details.

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Starman>

=cut


