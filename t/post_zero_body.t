use strict;
use Plack::Test;
use File::ShareDir;
use HTTP::Request;
use Test::More;
use Digest::MD5;
use LWP::UserAgent;

$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Starman';

my $file = File::ShareDir::dist_dir('Plack') . "/baybridge.jpg";

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


my $ua = LWP::UserAgent->new;
$ua->timeout(5);

test_psgi
	app => $app, 
	client => sub {
		my $cb = shift;

		my $req = HTTP::Request->new(POST => "http://localhost/");
		$req->content("0");

		my $res = $cb->($req);

		is $res->header('X-Content-Length'), 1;
		is Digest::MD5::md5_hex($res->content), 'cfcd208495d565ef66e7dff9f98764da';
	},
	ua => $ua;

done_testing;
