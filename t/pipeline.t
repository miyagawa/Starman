use strict;

use Test::More;
use Scalar::Util qw(blessed);
use Plack::Util;

{
    package Starman::Server;

    # Override the sysread method enabling it to read a stream of packages
    # from an arrayref instead of an file handle:
    use subs qw(sysread alarm);

    *Starman::Server::sysread = sub {
        if (Scalar::Util::blessed($_[0]) && $_[0]->can("getline")) {
            die "EWOULDBLOCK\n" unless $_[0]->can_read();

            $_[1] = $_[0]->getline;
            return length $_[1];
        }

        return CORE::sysread($_[0], $_[1], $_[2]);
    };

    *Starman::Server::alarm = sub { 1 };
}

use Starman::Server;

# Override the _finalize_response to collect responses
local *Starman::Server::_finalize_response = sub {
    my ($self, $env, $res) = @_;

    $self->{results} ||= [];
    push @{ $self->{results} }, [$env, $res];
};

# Override IO::Select to pseudo support our connection type
*IO::Select::real_new = *IO::Select::new;
local *IO::Select::new = sub {
    return $_[1] if (blessed($_[1]) && $_[1]->can("can_read"));

    goto &IO::Select::real_new;
};


# The stream of requests
my $requests = 7;
my $stream   = [
    "GET /req1 HTTP/1.1\r\nHost: localhost\r\n\r\n",
    "PUT /req2 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\nOK",
    "GET /req3 HTTP/1.1\r\nHost: localhost\r\n\r\n",
    "PUT /req4 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\nOKGET /req5 HTTP/1.1\r\nHost: localhost\r\n\r\n",
    "PUT /req6 HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nOK0\r\nGET /req7 HTTP/1.1\r\nHost: localhost\r\n\r\n",
];

my $server = bless {
    server => {
        client => Plack::Util::inline_object(
            NS_proto  => sub { "Fake" },
            getline   => sub { shift @{ $stream } },
            can_read  => sub { @{ $stream } },
            connected => sub { 1 },
        ),  
    },
    client => {
        keepalive => 1,
    },
    options => {
        keepalive => 1,
    },
    app => sub {
        return [ 200, [], [ "OK" ] ];
    }
}, "Starman::Server";

$server->process_request();

my %processed;
for my $res ( @{ $server->{results} } ) {
    $processed{ $res->[0]->{PATH_INFO} }++;
}

for (1 .. $requests) {
    is( $processed{"/req$_"}, 1, "Request $_ processed once" );
}

done_testing;
