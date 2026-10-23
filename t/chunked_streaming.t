use strict;
use warnings;
use Test::More;
use Digest::MD5 qw(md5_hex);
use Starman::Server;

# CVE-2026-115824: chunk payload must be written to the body buffer as it
# arrives, not held in memory until the whole chunk has been received.

my $chunk_len = 8 * 1024 * 1024;
my $piece     = 'x' x 65536;

my($fed, $written, $max_held) = (0, 0, 0);

{
    package FeedHandle;
    sub TIEHANDLE { my($class, @data) = @_; bless [ @data ], $class }
    sub READ {
        my $self = shift;
        my $held = $fed - $written;
        $max_held = $held if $held > $max_held;
        return 0 unless @$self;
        my $data = shift @$self;
        $_[0] = $data;
        $fed += length $data;
        return length $data;
    }

    package CountingBuffer;
    sub new { bless { ctx => Digest::MD5->new, len => 0 }, shift }
    sub print { my $self = shift; $written += length $_[0]; $self->{len} += length $_[0]; $self->{ctx}->add($_[0]) }
    sub rewind { $_[0] }
}

my @data = ("800000\r\n", ($piece) x ($chunk_len / length $piece), "\r\n0\r\n\r\n");
tie *SOCK, 'FeedHandle', @data;

my $server = bless {
    client => { inputbuf => '' },
    server => { client => \*SOCK },
}, 'Starman::Server';

my $env = { REQUEST_METHOD => 'POST', HTTP_TRANSFER_ENCODING => 'chunked' };

my $status;
{
    no warnings 'redefine';
    local *Plack::TempBuffer::new = sub { CountingBuffer->new };
    $status = $server->_prepare_env($env);
}

ok !$status, 'chunked body is accepted';
is $env->{CONTENT_LENGTH}, $chunk_len, 'CONTENT_LENGTH is the decoded length';
is $env->{'psgi.input'}{ctx}->hexdigest, md5_hex('x' x $chunk_len), 'body is decoded correctly';
cmp_ok $max_held, '<=', 2 * 65536, 'chunk payload is not held in memory while it arrives';

done_testing;
