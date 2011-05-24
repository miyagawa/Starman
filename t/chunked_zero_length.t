use strict;
use Plack::Test;
use HTTP::Request;
use Test::More;

$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Starman';

my $app = sub {
    my $env = shift;
    return sub {
        my $response = shift;
        my $writer = $response->([ 200, [ 'Content-Type', 'text/plain' ]]);
        $writer->write("Content");
        $writer->write("");
        $writer->write("Again");
        $writer->close;
    }
};

test_psgi $app, sub {
    my $cb = shift;

    my $req = HTTP::Request->new(GET => "http://localhost/");
    my $res = $cb->($req);

    is $res->content, "ContentAgain";
};

done_testing;
