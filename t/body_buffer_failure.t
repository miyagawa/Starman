use strict;
use warnings;
use Test::More;
use Starman::Server;

# If the request body cannot be stored completely (e.g. the temporary
# file system is full), the app must not be dispatched with a truncated
# body.

{
    package FeedHandle;
    sub TIEHANDLE { my($class, @data) = @_; bless [ @data ], $class }
    sub READ {
        my $self = shift;
        return 0 unless @$self;
        $_[0] = shift @$self;
        return length $_[0];
    }

    # Stores only the first 4 bytes, like a write to a full disk
    package FullBuffer;
    sub new { bless { data => '' }, shift }
    sub print { my $self = shift; my $room = 4 - length $self->{data}; $self->{data} .= substr join('', @_), 0, $room > 0 ? $room : 0; 1 }
    sub size { length $_[0]{data} }
    sub rewind { open my $fh, '<', \$_[0]{data}; $fh }
}

my %cases = (
    'Content-Length' => [ { CONTENT_LENGTH => 10 }, "0123456789" ],
    'chunked'        => [ { HTTP_TRANSFER_ENCODING => 'chunked' }, "a\r\n0123456789\r\n0\r\n\r\n" ],
);

for my $what (sort keys %cases) {
    my($env, $data) = @{ $cases{$what} };
    tie *SOCK, 'FeedHandle', $data;
    my $server = bless {
        client => { inputbuf => '' },
        server => { client => \*SOCK },
    }, 'Starman::Server';

    my $status;
    {
        no warnings 'redefine';
        local *Plack::TempBuffer::new = sub { FullBuffer->new };
        $status = $server->_prepare_env({ REQUEST_METHOD => 'POST', %$env });
    }
    is $status, 500, "$what body that is not stored completely is an error";
    untie *SOCK;
}

done_testing;
