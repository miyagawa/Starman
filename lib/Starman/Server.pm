package Starman::Server;
use strict;
use base 'Net::Server::PreFork';

use Data::Dump qw(dump);
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use IO::Socket qw(:crlf);
use HTTP::Parser::XS qw(parse_http_request);
use HTTP::Status qw(status_message);
use HTTP::Date qw(time2str);
use POSIX qw(EINTR EPIPE);
use Symbol;

use Plack::Util;
use Plack::TempBuffer;

use constant DEBUG        => $ENV{STARMAN_DEBUG} || 0;
use constant CHUNKSIZE    => 64 * 1024;
use constant READ_TIMEOUT => 5;

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

    my @port;
    for my $listen (@{$options->{listen} || [ "$options->{host}:$options->{port}" ]}) {
        my %listen;
        if ($listen =~ /:/) {
            my($h, $p, $opt) = split /:/, $listen, 3;
            $listen{host} = $h if $h;
            $listen{port} = $p;
            $listen{proto} = 'ssl' if 'ssl' eq lc $opt;
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
    $0 = "starman master " . join(" ", @{$self->{options}{argv} || []});
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
    $0 = "starman worker " . join(" ", @{$self->{options}{argv} || []});
}

sub post_accept_hook {
    my $self = shift;

    $self->{client} = {
        headerbuf => '',
        inputbuf  => '',
        keepalive => 1,
    };
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
        };

        # Parse headers
        my $reqlen = parse_http_request(delete $self->{client}->{headerbuf}, $env);
        if ( $reqlen == -1 ) {
            # Bad request
            DEBUG && warn "[$$] Bad request\n";
            $self->_http_error(400, { SERVER_PROTOCOL => "HTTP/1.0" });
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
                if ( $env->{HTTP_EXPECT} eq '100-continue' ) {
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

        $self->_prepare_env($env);

        # Run PSGI apps
        my $res = Plack::Util::run_app($self->{app}, $env);

        if (ref $res eq 'CODE') {
            $res->(sub { $self->_finalize_response($env, $_[0]) });
        } else {
            $self->_finalize_response($env, $res);
        }

        DEBUG && warn "[$$] Request done\n";

        if ( $self->{client}->{keepalive} ) {
            # If we still have data in the input buffer it may be a pipelined request
            if ( $self->{client}->{inputbuf} ) {
                if ( $self->{client}->{inputbuf} =~ /^(?:GET|HEAD)/ ) {
                    if ( DEBUG ) {
                        warn "Pipelined GET/HEAD request in input buffer: "
                            . dump( $self->{client}->{inputbuf} ) . "\n";
                    }

                    # Continue processing the input buffer
                    next;
                }
                else {
                    # Input buffer just has junk, clear it
                    if ( DEBUG ) {
                        warn "Clearing junk from input buffer: "
                            . dump( $self->{client}->{inputbuf} ) . "\n";
                    }

                    $self->{client}->{inputbuf} = '';
                }
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

        alarm( READ_TIMEOUT );

        while (1) {
            # Do we have a full header in the buffer?
            # This is before sysread so we don't read if we have a pipelined request
            # waiting in the buffer
            last if defined $self->{client}->{inputbuf} && $self->{client}->{inputbuf} =~ /$CR?$LF$CR?$LF/s;

            # If not, read some data
            my $read = sysread $self->{server}->{client}, my $buf, CHUNKSIZE;

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

    my $get_chunk = sub {
        if ($self->{client}->{inputbuf}) {
            my $chunk = delete $self->{client}->{inputbuf};
            return ($chunk, length $chunk);
        }
        my $read = sysread $self->{server}->{client}, my($chunk), CHUNKSIZE;
        return ($chunk, $read);
    };

    my $chunked = do { no warnings; lc delete $env->{HTTP_TRANSFER_ENCODING} eq 'chunked' };

    if (my $cl = $env->{CONTENT_LENGTH}) {
        my $buf = Plack::TempBuffer->new($cl);
        while ($cl > 0) {
            my($chunk, $read) = $get_chunk->();

            if ( !defined $read || $read == 0 ) {
                die "Read error: $!\n";
            }

            $cl -= $read;
            $buf->print($chunk);
        }
        $env->{'psgi.input'} = $buf->rewind;
    } elsif ($chunked) {
        my $buf = Plack::TempBuffer->new;
        my $chunk_buffer = '';
        my $length;

    DECHUNK:
        while (1) {
            my($chunk, $read) = $get_chunk->();
            $chunk_buffer .= $chunk;

            while ( $chunk_buffer =~ s/^(([0-9a-fA-F]+).*\015\012)// ) {
                my $trailer   = $1;
                my $chunk_len = hex $2;

                if ($chunk_len == 0) {
                    last DECHUNK;
                } elsif (length $chunk_buffer < $chunk_len + 2) {
                    $chunk_buffer = $trailer . $chunk_buffer;
                    last;
                }

                $buf->print(substr $chunk_buffer, 0, $chunk_len, '');
                $chunk_buffer =~ s/^\015\012//;

                $length += $chunk_len;
            }

            last unless $read && $read > 0;
        }

        $env->{CONTENT_LENGTH} = $length;
        $env->{'psgi.input'}   = $buf->rewind;
    } else {
        $env->{'psgi.input'} = $null_io;
    }
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

    if ( $protocol eq 'HTTP/1.1' ) {
        if ( !exists $headers{'content-length'} ) {
            if ( $status !~ /^1\d\d|[23]04$/ ) {
                DEBUG && warn "[$$] Using chunked transfer-encoding to send unknown length body\n";
                push @headers, 'Transfer-Encoding: chunked';
                $chunked = 1;
            }
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
            redo if $! == EINTR;
            die "write error: $!";
        }

        $amount -= $len;
        $offset += $len;

        DEBUG && warn "[$$] Wrote $len byte", ($len == 1 ? '' : 's'), "\n";
    }
}

sub post_client_connection_hook {
    my $self = shift;
    if ($self->{client}->{harakiri}) {
        exit;
    }
}

1;
