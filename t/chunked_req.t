use strict;
use Plack::Test;
use File::ShareDir;
use HTTP::Request;
use Test::More;
use Digest::MD5;

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

test_psgi $app, sub {
    my $cb = shift;

    open my $fh, "<:raw", $file;
    local $/ = \1024;

    my $req = HTTP::Request->new(POST => "http://localhost/");
    $req->content(sub { scalar <$fh> });

    my $res = $cb->($req);

    is $res->header('X-Content-Length'), 79838;
    is Digest::MD5::md5_hex($res->content), '983726ae0e4ce5081bef5fb2b7216950';
};

done_testing;
