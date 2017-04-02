use strict;
use Test::More;
use Test::Requires { 'LWP::Protocol::https' => 6 };
use Test::TCP;
use LWP::UserAgent;
use FindBin '$Bin';
use Starman::Server;

use Test::MockModule;

my $module = Test::MockModule->new( 'Net::Server::PreFork' );

my @last_args;

$module->mock( 'run', sub {
               @last_args = @_;
               return;
});


Starman::Server->new()->run( 'Starman', {
                             listen => [
                                    ':80',
                                    '1.2.3.4:123:ssl',
                                    '5.6.7.8:124/My::Custom::Proto',
                                    '5.6.7.8:5001:ssleay/ipv6',
                                    '/tmp/starman.sock|unix',
                                    ]
                                    }                                   
);

my $server = shift @last_args;
my %opts = @last_args;
my $ports = $opts{'port'};

is_deeply( $ports, [
           { ipv => 4,   port => 80,   proto => 'tcp', host => '0.0.0.0' },
           { ipv => 4,   port => 123,  proto => 'ssl', host => '1.2.3.4' },
           { ipv => 4,   port => 124,  proto => 'My::Custom::Proto', host => '5.6.7.8' },
           { ipv => 6,   port => 5001, proto => 'ssleay',            host => '5.6.7.8' },
           { ipv => '*', port => '/tmp/starman.sock', proto => 'unix',              host => '*' },
            ], 'Expected ports' ) or diag explain $ports;

done_testing;
