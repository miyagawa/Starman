package RawHTTP;
use strict;
use warnings;
use base 'Exporter';
use IO::Socket::INET;
use IO::Select;
use Test::TCP;
use Plack::Loader;
use Time::HiRes ();

our @EXPORT = qw(with_starman raw_request parser_backends);

# HTTP::Parser::XS backends to test with: the default one, and the
# pure-Perl one too if this version of HTTP::Parser::XS has it. The
# returned values are for $ENV{PERL_HTTP_PARSER_XS}.
sub parser_backends {
    my @backends = ('');
    push @backends, 'pp' if grep { !ref && -e "$_/HTTP/Parser/XS/PP.pm" } @INC;
    return @backends;
}

# Run $client->($port) against a Starman server listening on 127.0.0.1
sub with_starman {
    my($app, $client, %args) = @_;
    test_tcp(
        client => $client,
        server => sub {
            my $port = shift;
            my $server = Plack::Loader->load('Starman', port => $port, host => '127.0.0.1', workers => 1, %args);
            $server->run($app);
        },
    );
}

# Send raw bytes (a string, or an arrayref of segments written with a
# short pause between them) and return everything the server sends back
# until it closes the connection or $opt{timeout} seconds pass. In list
# context, also return whether the server closed the connection.
# With keep_open, our side is not shut down, so a close is the server's.
sub raw_request {
    my($port, $data, %opt) = @_;
    my $timeout = $opt{timeout} || 5;

    my $sock = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Failed to connect: $!";

    my @segments = ref $data ? @$data : ($data);
    for my $seg (@segments) {
        local $SIG{PIPE} = 'IGNORE';
        my $off = 0;
        while ($off < length $seg) {
            my $n = syswrite $sock, $seg, length($seg) - $off, $off;
            last unless $n;
            $off += $n;
        }
        Time::HiRes::sleep($opt{pause} || 0.05) if @segments > 1;
    }
    $sock->shutdown(1) unless $opt{keep_open};

    my $sel = IO::Select->new($sock);
    my $deadline = Time::HiRes::time() + $timeout;
    my $res = '';
    my $eof = 0;
    while ((my $left = $deadline - Time::HiRes::time()) > 0) {
        last unless $sel->can_read($left);
        my $n = sysread $sock, my $buf, 65536;
        unless ($n) {
            $eof = 1;
            last;
        }
        $res .= $buf;
    }
    return wantarray ? ($res, $eof) : $res;
}

1;
