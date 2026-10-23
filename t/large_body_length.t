use strict;
use warnings;
use Test::More;
use Starman::Server;

# Body lengths of 2**32 and more must still consume input. Older perls
# (e.g. 5.8.9) truncate the length argument of substr() to 32 bits, so
# taking substr($input, 0, $remaining) extracted nothing and looped.

{
    package FeedHandle;
    sub TIEHANDLE { my($class, @data) = @_; bless [ @data ], $class }
    sub READ {
        my $self = shift;
        return 0 unless @$self;
        $_[0] = shift @$self;
        return length $_[0];
    }
}

my %cases = (
    'Content-Length' => [ { CONTENT_LENGTH => 4294967296 }, "abc" ],
    'chunk size'     => [ { HTTP_TRANSFER_ENCODING => 'chunked' }, "100000000\r\nabc" ],
);

for my $what (sort keys %cases) {
    my($env, $data) = @{ $cases{$what} };
    tie *SOCK, 'FeedHandle', $data;
    my $server = bless {
        client => { inputbuf => '' },
        server => { client => \*SOCK },
    }, 'Starman::Server';

    my $status = eval {
        local $SIG{ALRM} = sub { die "Timed out\n" };
        alarm 5;
        my $status = $server->_prepare_env({ REQUEST_METHOD => 'POST', %$env });
        alarm 0;
        $status;
    };
    alarm 0;
    is $@, '', "$what of 2**32 or more does not spin";
    is $status, 400, "$what of 2**32 or more with a truncated body is rejected";
    untie *SOCK;
}

done_testing;
