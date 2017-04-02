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
        return [ 200, [ 'Content-Type' => 'text/plain' ], [$env->{'psgix.cleanup'}] ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");
        ok($res->content, "We set psgix.cleanup");
    };

test_psgi
    app => sub {
        my $env = shift;
        return [ 200, [ 'Content-Type' => 'text/plain' ], [ref($env->{'psgix.cleanup.handlers'})] ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");
        cmp_ok($res->content, "eq", "ARRAY", "psgix.cleanup.handlers is an array");
    };

test_psgi
    app => sub {
        my $env = shift;
        return [ 200, [ 'Content-Type' => 'text/plain' ], [join "", @{$env->{'psgix.cleanup.handlers'}}] ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");
        cmp_ok($res->content, "eq", "", "..which is empty by default");
    };

my $content = "NO_CLEANUP";
test_psgi
    app => sub {
        my $env = shift;
        push @{$env->{'psgix.cleanup.handlers'}} => sub { $content .= "XXX" };
        push @{$env->{'psgix.cleanup.handlers'}} => sub { $content .= "YYY" };
        push @{$env->{'psgix.cleanup.handlers'}} => sub { $content .= "ZZZ" };
        return [ 200, [ 'Content-Type' => 'text/plain' ], [ $content ] ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");
        cmp_ok($res->content, "eq", "NO_CLEANUP", "By the time we run the cleanup handler we've already returned a response");

        my $responses;
        for (1..10) {
            my $res = $cb->(GET "/");
            $responses .= $res->content;
        }
        like($responses, qr/$_/, "The response contains '$_' indicating the cleanup handlers were run") for qw(XXX YYY ZZZ);
    };

done_testing;
