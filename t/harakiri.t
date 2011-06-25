use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

$Plack::Test::Impl = 'Server';
$ENV{PLACK_SERVER} = 'Starman';

test_psgi
    app => sub {
        my $env = shift;
        return [ 200, [ 'Content-Type' => 'text/plain' ], [$$] ];
    },
    client => sub {
        my %seen_pid;
        my $cb = shift;
        for (1..23) {
            my $res = $cb->(GET "/");
            $seen_pid{$res->content}++;
        }
        cmp_ok(keys(%seen_pid), '<=', 5, 'In non-harakiri mode, pid is reused');
    };

test_psgi
    app => sub {
        my $env = shift;
        $env->{'psgix.harakiri.commit'} = 1;
        return [ 200, [ 'Content-Type' => 'text/plain' ], [$$] ];
    },
    client => sub {
        my %seen_pid;
        my $cb = shift;
        for (1..23) {
            my $res = $cb->(GET "/");
            $seen_pid{$res->content}++;
        }
        is keys(%seen_pid), 23, 'In Harakiri mode, each pid only used once';
    };

done_testing;
