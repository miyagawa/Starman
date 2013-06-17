use strict;
use warnings;

#this is stolen from Plack::Test::Server
# it was stolen because I need to pass %args to the Starman server
use Carp;
use HTTP::Request;
use HTTP::Response;
use Test::TCP;
use Plack::Loader;
use Plack::LWPish;

use Test::More;

sub test_psgi {
    my %args = @_;

    my $client = delete $args{client} or croak "client test code needed";
    my $app    = delete $args{app}    or croak "app needed";
    my $ua     = delete $args{ua} || Plack::LWPish->new;

    test_tcp(
        client => sub {
            my $port = shift;
            my $cb = sub {
                my $req = shift;
                $req->uri->scheme('http');
                $req->uri->host($args{host} || '127.0.0.1');
                $req->uri->port($port);
                return $ua->request($req);
            };
            $client->($cb);
        },
        server => $args{server} || sub {
            my $port = shift;
            my $server = Plack::Loader->auto(port => $port, host => ($args{host} || '127.0.0.1'), %args);
            $server->run($app);
            exit;
        },
    );
}
#end theft

$ENV{PLACK_SERVER} = 'Starman';
my $app = sub {
    my $env = shift;
    my $body;
    my $clen = $env->{CONTENT_LENGTH};
    while ($clen > 0) {
        $env->{'psgi.input'}->read(my $buf, $clen) or last;
        $clen -= length $buf;
        $body .= $buf;
    }
    return [ 200, [ 'Content-Type', 'text/plain', 'X-Content-Length', $env->{CONTENT_LENGTH} ], [ $body ] ];
};

test_psgi(
    'app' => $app,
    'client' => sub {
        my $cb = shift;

        my $req = HTTP::Request->new(POST => "http://localhost/");
        $req->content(1 x 15);

        my $res = $cb->($req);
        
        diag 'no limit-request-body';
        ok $res->is_success, 'request is success';
        is $res->header('X-Content-Length'), 15, 'correct X-Content-Length header';
    },
);

test_psgi(
    'app' => $app,
    'limit_request_body' => 15,
    'client' => sub {
        my $cb = shift;

        my $req = HTTP::Request->new(POST => "http://localhost/");
        $req->content(1 x 15);

        my $res = $cb->($req);
        
        diag 'request within limit-request-body';
        ok $res->is_success, 'request is success';
        is $res->header('X-Content-Length'), 15, 'correct X-Content-Length header';
    },
);

test_psgi(
    'app' => $app,
    'limit_request_body' => 10,
    'client' => sub {
        my $cb = shift;

        my $req = HTTP::Request->new(POST => "http://localhost/");
        $req->content(1 x 15);

        my $res = $cb->($req);
        diag 'request over limit-request-body';
        ok !$res->is_success, 'request not successful';
        is $res->code, 413, 'correct error code';
        is $res->content, 'Request Entity Too Large', 'correct error message';
    },
);

done_testing;
