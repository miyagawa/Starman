use strict;
use warnings;

use Plack::Test;
use HTTP::Request;
use Test::More;

{

    package Starman::Server;

    # override so we can mangle the HTTP request
    use subs 'sysread';

    *Starman::Server::sysread = sub {
        my $read = CORE::sysread( $_[0], $_[1], $_[2] );
        $_[1] =~ s/\r\n/\n/g;

        return $read;
    };

}

$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Starman';

my $app = sub {
    my $env = shift;
    return sub {
        my $response = shift;
        my $writer = $response->( [ 200, [ 'Content-Type', 'text/plain' ] ] );
        $writer->close;
    }
};

test_psgi $app, sub {
    my $cb = shift;

    my $req = HTTP::Request->new( GET => "http://localhost/" );

    my $res = $cb->($req);
    is $res->code, 200;

};

done_testing;
