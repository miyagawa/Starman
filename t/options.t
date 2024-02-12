use strict;
use warnings;
use Test::More;
use Starman::Server;

######################################################################
# Hack: change Starman::Server's parent class so we can intercept
# the run() results.
{
    package
	NoOpServer;
    {
	no warnings 'once';
	*new = Starman::Server->can('new');
    }
    sub run { @_ }
}
@Starman::Server::ISA = 'NoOpServer';
######################################################################

sub check_computed_port ($$$) {
    my($options, $expected_port, $test_name) = @_;
    my(undef, %got_options) = Starman::Server->new->run(sub {}, $options);
    is_deeply $got_options{port}, $expected_port, $test_name;
}

check_computed_port
    { },
    [ { port => '' } ],
    'no host/port/listen options'; # however would fail later with "Missing port in hashref passed in port argument."
check_computed_port
    { host => 'host', port => 12345 },
    [ { host => 'host', port => 12345 } ],
    'host+port specified';
check_computed_port
    { host => '127.0.0.1', port => 12345 },
    [ { host => '127.0.0.1', port => 12345 } ],
    'ipv4 address+port specified';
check_computed_port
    { listen => [ ':12345' ] },
    [ { port => 12345 } ],
    'listen without host specified';
check_computed_port
    { listen => [ 'host:12345' ] },
    [ { host => 'host', port => 12345 } ],
    'listen address (ipv4) specified';
check_computed_port
    { listen => [ 'host:443:ssl' ] },
    [ { host => 'host', port => 443, proto => 'ssl' } ],
    'ssl option specified';
check_computed_port
    { listen => [ 'host:8080:foo' ] },
    [ { host => 'host', port => 8080 } ],
    'unhandled option ignored';
check_computed_port
    { listen => [ '/tmp/unix.sock' ] },
    [ { host => 'localhost', port => '/tmp/unix.sock', proto => 'unix' } ],
    'socket file specified';

{
local $TODO = 'known errors with IPv6 address handling (see #149)';
check_computed_port
    { host => '::1', port => 12345 },
    [ { host => '::1', port => 12345 } ],
    'ipv6 address+port specified';
check_computed_port
    { listen => [ '[::1]:12345' ] },
    [ { host => '::1', port => 12345 } ],
    'listen address (ipv6) specified';
check_computed_port
    { listen => [ '[::1]:12345:ssl' ] },
    [ { host => '::1', port => 12345, proto => 'ssl' } ],
    'listen address (ipv6) with ssl option specified';
check_computed_port
    { listen => [ '[::1]:12345:foo' ] },
    [ { host => '::1', port => 12345 } ],
    'listen address (ipv6) with unhandled option';
}

done_testing;

__END__
