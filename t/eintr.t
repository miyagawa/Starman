use strict;
use Starman::Server;
use Plack::Test;
use HTTP::Request;
use Test::More;
use File::Temp qw(tempfile);
use Time::HiRes qw(sleep);

my $fh = tempfile;
$fh->autoflush(1);

# When a child handles our request, write it's pid to the temp file
{
    no warnings 'redefine';
    my $old_process_request = \&Starman::Server::process_request;
    *Starman::Server::process_request = sub {
        seek $fh, 0, 0;
        print $fh $$;
        goto &$old_process_request;
    };
}

$Plack::Test::Impl = "Server";
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

test_psgi $app, sub {
    my $cb = shift;

    my $c = 0;

    my $req = HTTP::Request->new(POST => "http://localhost/");
    $req->content(sub {
        $c++;

        # Send some chunked content
        return "abcde" if $c == 1;

        # Child should be processing request, get pid
        seek $fh, 0, 0;
        sysread $fh, my $pid, 100;

        # Ensure child is waiting on a sysread
        sleep 0.1;

        kill 'HUP', $pid if $pid;

        # Ensure child received HUP before sending more data
        sleep 0.1;

        # Now send it some more content
        return "abcde" if $c <= 5;

        return undef;
    });

    my $res = $cb->($req);

    # We should have got 5 x 5 bytes or 25 bytes total
    is $res->header('X-Content-Length'), 25;
};

done_testing;
