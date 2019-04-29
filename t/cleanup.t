use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

$Plack::Test::Impl = 'Server';
$ENV{PLACK_SERVER} = 'Starman';

my $cleanup_called = 0;
my $SLEEP          = 1;
test_psgi
    app => sub {
        my $env = shift;
        push @{ $env->{'psgix.cleanup.handlers'} }, sub {
            sleep $SLEEP;
            # tracked per-pid
            $cleanup_called++;
        };
        return [
            200,
            [ 'Content-Type' => 'text/plain' ],
            [ "$cleanup_called/" . time ]
        ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");

        my $received = time;
        my ($cleaned_up, $returned) = split '/' => $res->content;
        ok !$cleaned_up, 'response returned pre-cleanup';
        cmp_ok $received, '<', $returned + 1,
            "returned without sleeping";

        # hit all (default 5) workers thrice more
        # making sure we get 1+1+1 and not 1+2+3
        $cb->(GET "/") for (1..15);
        sleep $SLEEP;

        ($cleaned_up, $returned) = split( '/' => $cb->(GET '/')->content);
        like $cleaned_up, qr/^[34]$/, 'cleanups not re-called';
    };

done_testing;
