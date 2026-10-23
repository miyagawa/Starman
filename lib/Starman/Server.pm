package Starman::Server;
use strict;
use base 'Net::Server::PreFork';

use Data::Dump qw(dump);
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use IO::Socket qw(:crlf);
use HTTP::Parser::XS qw(parse_http_request);
use HTTP::Status qw(status_message);
use HTTP::Date qw(time2str);
use POSIX qw(EINTR EPIPE ECONNRESET);
use Symbol;

use Plack::Util;
use Plack::TempBuffer;

use constant DEBUG        => $ENV{STARMAN_DEBUG} || 0;
use constant CHUNKSIZE    => 64 * 1024;
use constant MAX_CHUNK_LINE => 4096;
use constant MAX_TRAILER_SIZE => 16 * 1024;

my $null_io = do { open my $io, "<", \""; $io };

use Net::Server::SIG qw(register_sig);

# Override Net::Server's HUP handling - just restart all the workers and that's about it
sub sig_hup {
    my $self = shift;
    $self->hup_children;
}

sub run {
    my($self, $app, $options) = @_;

    $self->{app} = $app;
    $self->{options} = $options;

    my %extra = ();

    if ($options->{net_server_args}) {
        %extra = %{ $options->{net_server_args} };
    }

    if ( $options->{pid} ) {
        $extra{pid_file} = $options->{pid};
    }
    if ( $options->{daemonize} ) {
        $extra{setsid} = $extra{background} = 1;
    }
    if ( $options->{error_log} ) {
        $extra{log_file} = $options->{error_log};
    }
    if ( DEBUG ) {
        $extra{log_level} = 4;
    }
    if ( $options->{ssl_cert} ) {
        $extra{SSL_cert_file} = $options->{ssl_cert};
    }
    if ( $options->{ssl_key} ) {
        $extra{SSL_key_file} = $options->{ssl_key};
    }
    if (! exists $options->{keepalive}) {
        $options->{keepalive} = 1;
    }
    if (! exists $options->{keepalive_timeout}) {
        $options->{keepalive_timeout} = 1;
    }
    if (! exists $options->{read_timeout}) {
        $options->{read_timeout} = 5;
    }
    if (! exists $options->{proctitle}) {
        $options->{proctitle} = 1;
    }

    my @port;
    for my $listen (@{$options->{listen} || [ "$options->{host}:$options->{port}" ]}) {
        my %listen;
        if ($listen =~ /:/) {
            my($h, $p, $opt) = split /:/, $listen, 3;
            $listen{host} = $h if $h;
            $listen{port} = $p;
            $listen{proto} = 'ssl' if defined $opt && lc $opt eq 'ssl';
        } else {
            %listen = (
                host  => 'localhost',
                port  => $listen,
                proto => 'unix',
            );
        }
        push @port, \%listen;
    }

    my $workers = $options->{workers} || 5;
    local @ARGV = ();

    $self->SUPER::run(
        port                => \@port,
        host                => '*',   # default host
        proto               => $options->{ssl} ? 'ssl' : 'tcp', # default proto
        serialize           => ( $^O =~ m!(linux|darwin|bsd|cygwin)$! ) ? 'none' : 'flock',
        min_servers         => $options->{min_servers}       || $workers,
        min_spare_servers   => $options->{min_spare_servers} || $workers - 1,
        max_spare_servers   => $options->{max_spare_servers} || $workers - 1,
        max_servers         => $options->{max_servers}       || $workers,
        max_requests        => $options->{max_requests}      || 1000,
        user                => $options->{user}              || $>,
        group               => $options->{group}             || $),
        listen              => $options->{backlog}           || 1024,
        check_for_waiting   => 1,
        no_client_stdout    => 1,
        %extra
    );
}

sub pre_loop_hook {
    my $self = shift;

    my $port = $self->{server}->{port}->[0];
    my $proto = $port->{proto} eq 'ssl'  ? 'https' :
                $port->{proto} eq 'unix' ? 'unix'  :
                                           'http';

    $self->{options}{server_ready}->({
        host => $port->{host},
        port => $port->{port},
        proto => $proto,
        server_software => 'Starman',
    }) if $self->{options}{server_ready};

    register_sig(
        TTIN => sub { $self->{server}->{$_}++ for qw( min_servers max_servers ) },
        TTOU => sub { $self->{server}->{$_}-- for qw( min_servers max_servers ) },
        QUIT => sub { $self->server_close(1) },
    );
}

sub server_close {
    my($self, $quit) = @_;

    if ($quit) {
        $self->log(2, $self->log_time . " Received QUIT. Running a graceful shutdown\n");
        $self->{server}->{$_} = 0 for qw( min_servers max_servers );
        $self->hup_children;
        while (1) {
            Net::Server::SIG::check_sigs();
            $self->coordinate_children;
            last if !keys %{$self->{server}{children}};
            sleep 1;
        }
        $self->log(2, $self->log_time . " Worker processes cleaned up\n");
    }

    $self->SUPER::server_close();
}

sub run_parent {
    my $self = shift;
    $0 = "starman master " . join(" ", @{$self->{options}{argv} || []})
        if $self->{options}{proctitle};
    no warnings 'redefine';
    local *Net::Server::PreFork::register_sig = sub {
        my %args = @_;
        delete $args{QUIT};
        Net::Server::SIG::register_sig(%args);
    };
    $self->SUPER::run_parent(@_);
}

# The below methods run in the child process

sub child_init_hook {
    my $self = shift;
    srand();
    if ($self->{options}->{psgi_app_builder}) {
        DEBUG && warn "[$$] Initializing the PSGI app\n";
        $self->{app} = $self->{options}->{psgi_app_builder}->();
    }
    $0 = "starman worker " . join(" ", @{$self->{options}{argv} || []})
        if $self->{options}{proctitle};

}

sub post_accept_hook {
    my $self = shift;

    $self->{client} = {
        headerbuf => '',
        inputbuf  => '',
        keepalive => 1,
    };
}

sub dispatch_request {
    my ($self, $env) = @_;

    # Run PSGI apps
    my $res = Plack::Util::run_app($self->{app}, $env);

    if (ref $res eq 'CODE') {
        $res->(sub { $self->_finalize_response($env, $_[0]) });
    } else {
        $self->_finalize_response($env, $res);
    }
}

sub process_request {
    my $self = shift;
    my $conn = $self->{server}->{client};

    if ($conn->NS_proto eq 'TCP') {
        setsockopt($conn, IPPROTO_TCP, TCP_NODELAY, 1)
            or die $!;
    }

    while ( $self->{client}->{keepalive} ) {
        last if !$conn->connected;

        # Read until we see all headers
        last if !$self->_read_headers;

        my $env = {
            REMOTE_ADDR     => $self->{server}->{peeraddr},
            REMOTE_HOST     => $self->{server}->{peerhost} || $self->{server}->{peeraddr},
            REMOTE_PORT     => $self->{server}->{peerport} || 0,
            SERVER_NAME     => $self->{server}->{sockaddr} || 0, # XXX: needs to be resolved?
            SERVER_PORT     => $self->{server}->{sockport} || 0,
            SCRIPT_NAME     => '',
            'psgi.version'      => [ 1, 1 ],
            'psgi.errors'       => *STDERR,
            'psgi.url_scheme'   => ($conn->NS_proto eq 'SSL' ? 'https' : 'http'),
            'psgi.nonblocking'  => Plack::Util::FALSE,
            'psgi.streaming'    => Plack::Util::TRUE,
            'psgi.run_once'     => Plack::Util::FALSE,
            'psgi.multithread'  => Plack::Util::FALSE,
            'psgi.multiprocess' => Plack::Util::TRUE,
            'psgix.io'          => $conn,
            'psgix.input.buffered' => Plack::Util::TRUE,
            'psgix.harakiri' => Plack::Util::TRUE,
            'psgix.informational' => sub { _write_informational($conn, @_) },
        };

        # Parse headers
        my $reqlen = parse_http_request(delete $self->{client}->{headerbuf}, $env);
        if ( $reqlen == -1 ) {
            # Bad request
            DEBUG && warn "[$$] Bad request\n";
            $self->_http_error(400, { SERVER_PROTOCOL => "HTTP/1.0" });
            last;
        }

        # Reject ambiguous message framing before we touch the body
        my($framing_error, $close_after) = $self->_check_framing($env);
        if ( $framing_error ) {
            DEBUG && warn "[$$] Invalid message framing, returning $framing_error\n";
            $self->_http_error( $framing_error, $env );
            last;
        }

        # Initialize PSGI environment
        # Determine whether we will keep the connection open after the request
        my $connection = delete $env->{HTTP_CONNECTION};
        my $proto = $env->{SERVER_PROTOCOL};
        if ( $proto && $proto eq 'HTTP/1.0' ) {
            if ( $connection && $connection =~ /^keep-alive$/i ) {
                # Keep-alive only with explicit header in HTTP/1.0
                $self->{client}->{keepalive} = 1;
            }
            else {
                $self->{client}->{keepalive} = 0;
            }
        }
        elsif ( $proto && $proto eq 'HTTP/1.1' ) {
            if ( $connection && $connection =~ /^close$/i ) {
                $self->{client}->{keepalive} = 0;
            }
            else {
                # Keep-alive assumed in HTTP/1.1
                $self->{client}->{keepalive} = 1;
            }

            # Do we need to send 100 Continue?
            if ( $env->{HTTP_EXPECT} ) {
                if ( lc $env->{HTTP_EXPECT} eq '100-continue' ) {
                    _syswrite($conn, \('HTTP/1.1 100 Continue' . $CRLF . $CRLF));
                    DEBUG && warn "[$$] Sent 100 Continue response\n";
                }
                else {
                    DEBUG && warn "[$$] Invalid Expect header, returning 417\n";
                    $self->_http_error( 417, $env );
                    last;
                }
            }

            unless ($env->{HTTP_HOST}) {
                # No host, bad request
                DEBUG && warn "[$$] Bad request, HTTP/1.1 without Host header\n";
                $self->_http_error( 400, $env );
                last;
            }
        }

        unless ($self->{options}->{keepalive}) {
            DEBUG && warn "[$$] keep-alive is disabled. Closing the connection after this request\n";
            $self->{client}->{keepalive} = 0;
        }

        if ($close_after) {
            DEBUG && warn "[$$] Both Transfer-Encoding and Content-Length present. Closing the connection after this request\n";
            $self->{client}->{keepalive} = 0;
        }

        if ( my $status = $self->_prepare_env($env) ) {
            DEBUG && warn "[$$] Bad request body, returning $status\n";
            $self->_http_error( $status, $env );
            last;
        }

        $self->dispatch_request($env);

        DEBUG && warn "[$$] Request done\n";

        if ( $self->{client}->{keepalive} ) {
            # If we still have data in the input buffer it may be a pipelined request
            # The request body has been read exactly, so this is the next request
            if ( $self->{client}->{inputbuf} ne '' ) {
                if ( DEBUG ) {
                    warn "Pipelined request in input buffer: "
                        . dump( $self->{client}->{inputbuf} ) . "\n";
                }

                # Continue processing the input buffer
                next;
            }

            DEBUG && warn "[$$] Waiting on previous connection for keep-alive request...\n";

            my $sel = IO::Select->new($conn);
            last unless $sel->can_read($self->{options}->{keepalive_timeout});
        }
    }

    DEBUG && warn "[$$] Closing connection\n";
}

sub _read_headers {
    my $self = shift;

    eval {
        local $SIG{ALRM} = sub { die "Timed out\n"; };

        alarm( $self->{options}->{read_timeout} );

        while (1) {
            # Do we have a full header in the buffer?
            # This is before sysread so we don't read if we have a pipelined request
            # waiting in the buffer
            last if $self->{client}->{inputbuf} ne '' && $self->{client}->{inputbuf} =~ /$CR?$LF$CR?$LF/s;

            # If not, read some data
            my $read = _sysread($self->{server}->{client}, my $buf, CHUNKSIZE);

            if ( !defined $read || $read == 0 ) {
                die "Read error: $!\n";
            }

            if ( DEBUG ) {
                warn "[$$] Read $read bytes: " . dump($buf) . "\n";
            }

            $self->{client}->{inputbuf} .= $buf;
        }
    };

    alarm(0);

    if ( $@ ) {
        if ( $@ =~ /Timed out/ ) {
            DEBUG && warn "[$$] Client connection timed out\n";
            return;
        }

        if ( $@ =~ /Read error/ ) {
            DEBUG && warn "[$$] Read error: $!\n";
            return;
        }
    }

    # Pull out the complete header into a new buffer
    $self->{client}->{headerbuf} = $self->{client}->{inputbuf};

    # Save any left-over data, possibly body data or pipelined requests
    $self->{client}->{inputbuf} =~ s/.*?$CR?$LF$CR?$LF//s;

    return 1;
}

# Returns an error status if the request framing is invalid, and
# whether the connection must be closed after this request.
sub _check_framing {
    my($self, $env) = @_;

    if ( defined $env->{HTTP_TRANSFER_ENCODING} ) {
        # Only "chunked" is supported, and it must be the only coding
        # (RFC 9112 section 6.1). HTTP/1.0 has no Transfer-Encoding.
        return 400 if $env->{SERVER_PROTOCOL} ne 'HTTP/1.1';

        my @codings = map { s/^[ \t]+|[ \t]+$//g; lc } split /,/, $env->{HTTP_TRANSFER_ENCODING}, -1;
        return 400 unless @codings && $codings[-1] eq 'chunked';
        return 400 if grep { $_ eq 'chunked' } @codings[0..$#codings-1];
        return 501 if @codings > 1;

        $env->{HTTP_TRANSFER_ENCODING} = 'chunked';

        # Transfer-Encoding overrides Content-Length, but a message with
        # both may be an attempt at request smuggling (RFC 9112 6.3).
        my $close_after = defined delete $env->{CONTENT_LENGTH};
        return (undef, $close_after);
    }

    if ( defined $env->{CONTENT_LENGTH} ) {
        # Duplicate headers arrive joined with ",". They are only acceptable
        # if every value is the same valid length (RFC 9112 section 6.3).
        my @values = split /\s*,\s*/, $env->{CONTENT_LENGTH}, -1;
        my %seen;
        for my $v (@values) {
            $v =~ s/^[ \t]+|[ \t]+$//g;
            return 400 unless $v =~ /\A[0-9]{1,18}\z/;
            $seen{0 + $v}++;
        }
        return 400 unless keys %seen == 1;
        ($env->{CONTENT_LENGTH}) = keys %seen;
    }

    return;
}

sub _http_error {
    my ( $self, $code, $env ) = @_;

    my $status = $code || 500;
    my $msg    = status_message($status);

    my $res = [
        $status,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => length($msg) ],
        [ $msg ],
    ];

    $self->{client}->{keepalive} = 0;
    $self->_finalize_response($env, $res);
}

sub _prepare_env {
    my($self, $env) = @_;

    # Body bytes are taken from the input buffer, leaving anything after
    # the body there for the next request on this connection.
    my $input = \$self->{client}->{inputbuf};
    my $read_more = sub {
        my $read = _sysread($self->{server}->{client}, my($chunk), CHUNKSIZE);
        $$input .= $chunk if $read;
        return $read;
    };

    my $chunked = do { no warnings; delete $env->{HTTP_TRANSFER_ENCODING} eq 'chunked' };

    if ($chunked) {
        my $buf = Plack::TempBuffer->new;
        my $length = 0;
        my $remaining;    # bytes left in the current chunk, undef while reading a size line
        my $trailer_size; # defined once the last chunk has been read

    DECHUNK:
        while (1) {
            while ($$input ne '') {
                if (defined $trailer_size) {
                    my $eol = index $$input, "\015\012";
                    if ($eol < 0) {
                        return 400 if $trailer_size + length $$input > MAX_TRAILER_SIZE;
                        last;
                    }
                    $trailer_size += $eol + 2;
                    return 400 if $trailer_size > MAX_TRAILER_SIZE;

                    my $line = substr $$input, 0, $eol + 2, '';
                    last DECHUNK if $eol == 0;
                    return 400 if $line =~ /[\015\012].*\015\012/s;
                    next;
                }

                if (defined $remaining) {
                    if ($remaining > 0) {
                        # Write chunk data out as it arrives
                        my $data = substr $$input, 0, $remaining, '';
                        $buf->print($data);
                        $remaining -= length $data;
                        $length    += length $data;
                        next;
                    }

                    last if length $$input < 2;
                    return 400 unless substr($$input, 0, 2, '') eq "\015\012";
                    undef $remaining;
                    next;
                }

                my $eol = index $$input, "\015\012";
                if ($eol < 0) {
                    return 400 if length $$input > MAX_CHUNK_LINE;
                    last;
                }
                return 400 if $eol > MAX_CHUNK_LINE;

                my $chunk_len = _parse_chunk_size(substr $$input, 0, $eol + 2, '');
                return 400 unless defined $chunk_len;

                if ($chunk_len == 0) {
                    $trailer_size = 0;
                } else {
                    $remaining = $chunk_len;
                }
            }

            # The connection ended before the body did
            return 400 unless $read_more->();
        }

        $env->{CONTENT_LENGTH} = $length;
        $env->{'psgi.input'}   = $buf->rewind;
    } elsif (my $cl = $env->{CONTENT_LENGTH}) {
        my $buf = Plack::TempBuffer->new($cl);
        while ($cl > 0) {
            if ($$input eq '') {
                # The connection ended before the body did
                return 400 unless $read_more->();
            }

            my $data = substr $$input, 0, $cl, '';
            $cl -= length $data;
            $buf->print($data);
        }
        $env->{'psgi.input'} = $buf->rewind;
    } else {
        $env->{'psgi.input'} = $null_io;
    }

    return;
}

# chunk-size [ chunk-ext ] CRLF (RFC 9112 section 7.1). Returns undef if
# the line is malformed or the size is too large to count exactly.
sub _parse_chunk_size {
    my $line = shift;

    $line =~ /\A([0-9A-Fa-f]+)(?:[ \t]*;[^\015\012]*)?\015\012\z/
        or return;
    (my $size = $1) =~ s/\A0+(?=.)//;
    return if length $size > 13;

    return hex $size;
}

sub _finalize_response {
    my($self, $env, $res) = @_;

    if ($env->{'psgix.harakiri.commit'}) {
        $self->{client}->{keepalive} = 0;
        $self->{client}->{harakiri} = 1;
    }

    my $protocol = $env->{SERVER_PROTOCOL};
    my $status   = $res->[0];
    my $message  = status_message($status);

    # These responses never have a body (RFC 9110 sections 6.4.1 and 9.3.2)
    my $no_body = $env->{REQUEST_METHOD} eq 'HEAD' || $status =~ /^(?:1\d\d|204|304)$/;

    my(@headers, %headers);
    push @headers, "$protocol $status $message";

    # Switch on Transfer-Encoding: chunked if we don't know Content-Length.
    my $chunked;
    my $headers = $res->[1];
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $k = $headers->[$i];
        my $v = $headers->[$i + 1];
        next if $k eq 'Connection';
        push @headers, "$k: $v";
        $headers{lc $k} = $v;
    }

    if ( $no_body ) {
        # Do not frame (or send) a body, whatever the headers say
    }
    elsif ( $protocol eq 'HTTP/1.1' ) {
        if ( !exists $headers{'content-length'} ) {
            DEBUG && warn "[$$] Using chunked transfer-encoding to send unknown length body\n";
            push @headers, 'Transfer-Encoding: chunked';
            $chunked = 1;
        }
        elsif ( my $te = $headers{'transfer-encoding'} ) {
            if ( $te eq 'chunked' ) {
                DEBUG && warn "[$$] Chunked transfer-encoding set for response\n";
                $chunked = 1;
            }
        }
    } else {
        if ( !exists $headers{'content-length'} ) {
            DEBUG && warn "[$$] Disabling keep-alive after sending unknown length body on $protocol\n";
            $self->{client}->{keepalive} = 0;
        }
    }

    if ( ! $headers{date} ) {
        push @headers, "Date: " . time2str( time() );
    }

    # Should we keep the connection open?
    if ( $self->{client}->{keepalive} ) {
        push @headers, 'Connection: keep-alive';
    } else {
        push @headers, 'Connection: close';
    }

    my $conn = $self->{server}->{client};

    # Buffer the headers so they are sent with the first write() call
    # This reduces the number of TCP packets we are sending
    _syswrite($conn, \(join( $CRLF, @headers, '' ) . $CRLF));

    if (defined $res->[2]) {
        if ($no_body) {
            # Release the body without reading it
            $res->[2]->close if ref $res->[2] ne 'ARRAY';
            return;
        }
        Plack::Util::foreach($res->[2], sub {
            my $buffer = $_[0];
            if ($chunked) {
                my $len = length $buffer;
                return unless $len;
                $buffer = sprintf( "%x", $len ) . $CRLF . $buffer . $CRLF;
            }
            _syswrite($conn, \$buffer);
        });
        _syswrite($conn, \"0$CRLF$CRLF") if $chunked;
    } else {
        return Plack::Util::inline_object
            write => sub {
                return if $no_body;
                my $buffer = $_[0];
                if ($chunked) {
                    my $len = length $buffer;
                    return unless $len;
                    $buffer = sprintf( "%x", $len ) . $CRLF . $buffer . $CRLF;
                }
                _syswrite($conn, \$buffer);
            },
            close => sub {
                _syswrite($conn, \"0$CRLF$CRLF") if $chunked;
            };
    }
}

sub _syswrite {
    my ($conn, $buffer_ref) = @_;

    my $amount = length $$buffer_ref;
    my $offset = 0;

    while ($amount > 0) {
        my $len = syswrite($conn, $$buffer_ref, $amount, $offset);

        if (not defined $len) {
            return if $! == EPIPE;
            return if $! == ECONNRESET;
            redo if $! == EINTR;
            die "write error: $!";
        }

        $amount -= $len;
        $offset += $len;

        DEBUG && warn "[$$] Wrote $len byte", ($len == 1 ? '' : 's'), "\n";
    }
}

sub _sysread {
    while (1) {
        my $len = sysread $_[0], $_[1], $_[2];
        return $len if defined $len or $! != EINTR;
    }
}

sub _write_informational {
    my ($conn, $code, $headers) = @_;
    my $message = HTTP::Status::status_message($code);
    my @lines = "HTTP/1.1 $code $message";
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $k = $headers->[$i];
        my $v = $headers->[$i + 1];
        push @lines, "$k: $v" ;
    }
    _syswrite($conn, \join($CRLF, @lines, $CRLF));

    DEBUG && warn "[$$] Sent $code $message response\n";
}

sub post_client_connection_hook {
    my $self = shift;
    if ($self->{client}->{harakiri}) {
        exit;
    }
}

1;
