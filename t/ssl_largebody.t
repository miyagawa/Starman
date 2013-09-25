use strict;
use Test::More;
use Test::Requires { 'LWP::Protocol::https' => 6 };
use Test::TCP;
use LWP::UserAgent;
use FindBin '$Bin';
use Starman::Server;

# https://github.com/miyagawa/Starman/issues/78

my $host       = 'localhost';
my $ca_cert    = "$Bin/ssl_ca.pem";
my $server_pem = "$Bin/ssl_key.pem";
my $body = 'x'x32*1024; # > 16KB

my ($success, $status, $content);

test_tcp(
    client => sub {
        my $port = shift;

        my $ua = LWP::UserAgent->new(
            timeout  => 2,
            ssl_opts => {
                verify_hostname => 1,
                SSL_ca_file     => $ca_cert,
            },
        );

        my $res = $ua->get("https://$host:$port");
        $success = $res->is_success;
        $status  = $res->status_line;
        $content = $res->decoded_content;
    },
    server => sub {
        my $port = shift;
        Starman::Server->new->run(
            sub { [ 200, [], [$body] ] },
            {
                host     => $host,
                port     => $port,
                ssl      => 1,
                ssl_key  => $server_pem,
                ssl_cert => $server_pem,
            },
        );
    }
);

ok $success, 'HTTPS connection succeeded';
diag $status if not $success;
is $content, $body;

done_testing;
