use strict;
use Plack::Test;
use HTTP::Request;
use Test::More;
use IO::Socket qw(:crlf);

$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Starman';

my @app = (
    sub {
        my $env = shift;
        return sub {
            my $response = shift;
            my $writer = $response->([ 200, [ 'Content-Type', 'text/plain' ]]);
            $writer->write("This is the data in the first chunk${CRLF}");
            $writer->write("and this is the second one${CRLF}");
            $writer->write("con");
            $writer->write("sequence");
            $writer->close;
        }
    },
    sub {
        my $env = shift;
        return sub {
            my $response = shift;
            my $writer = $response->([
                200, [ 'Content-Type', 'text/plain', 'Transfer-Encoding', 'chunked' ]
            ]);
            $writer->write("25${CRLF}This is the data in the first chunk${CRLF}${CRLF}");
            $writer->write("1C${CRLF}and this is the second one${CRLF}${CRLF}");
            $writer->write("3${CRLF}con${CRLF}");
            $writer->write("8${CRLF}sequence${CRLF}");
            $writer->write("0${CRLF}${CRLF}");
            $writer->close;
        }
    },
);

for my $app (@app) {
    test_psgi $app, sub {
        my $cb = shift;

        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);

        is $res->content,
            "This is the data in the first chunk\r\n" .
            "and this is the second one\r\n" .
            "consequence";
    };
}

done_testing;
