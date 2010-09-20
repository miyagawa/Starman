package Starman::Server;
use strict;
use base 'Net::Server::PreFork';

use Data::Dump qw(dump);
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use IO::Socket qw(:crlf);
use HTTP::Parser::XS qw(parse_http_request);
use HTTP::Status qw(status_message);
use HTTP::Date qw(time2str);
use Symbol;

use Plack::Util;
use Plack::TempBuffer;

use constant DEBUG        => $ENV{STARMAN_DEBUG} || 0;
use constant CHUNKSIZE    => 64 * 1024;
use constant READ_TIMEOUT => 5;

my $null_io = do { open my $io, "<", \""; $io };

use Net::Server::SIG qw(register_sig);

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
    if (! exists $options->{keepalive}) {
        $options->{keepalive} = 1;
    }

    my($host, $port, $proto);
    for my $listen (@{$options->{listen} || [ "$options->{host}:$options->{port}" ]}) {
        if ($listen =~ /:/) {
            my($h, $p) = split /:/, $listen, 2;
            push @$host, $h || '*';
            push @$port, $p;
            push @$proto, 'tcp';
        } else {
            push @$host, 'localhost';
            push @$port, $listen;
            push @$proto, 'unix';
        }
    }

    my $workers = $options->{workers} || 5;
    local @ARGV = (@{$options->{argv} || []});

    $self->SUPER::run(
        port                       => $port,
        host                       => $host,
        proto                      => $proto,
        serialize                  => 'flock',
        log_level                  => DEBUG ? 4 : 2,
        min_servers                => $options->{min_servers}       || $workers,
        min_spare_servers          => $options->{min_spare_servers} || $workers - 1,
        max_spare_servers          => $options->{max_spare_servers} || $workers - 1,
        max_servers                => $options->{max_servers}       || $workers,
        max_requests               => $options->{max_requests}      || 1000,
        user                       => $options->{user}              || $>,
        group                      => $options->{group}             || $),
        listen                     => $options->{backlog}           || 1024,
        leave_children_open_on_hup => 1, # XXX conigurable?
        no_client_stdout           => 1,
        %extra
    );
}

sub pre_loop_hook {
    my $self = shift;

    my $host = $self->{server}->{host}->[0];
    my $port = $self->{server}->{port}->[0];

    $self->{options}{server_ready}->({
        host => $host,
        port => $port,
        proto => $port =~ /unix/ ? 'unix' : 'http',
        server_software => 'Starman',
    }) if $self->{options}{server_ready};

    register_sig(
        TTIN => sub { $self->{server}->{$_}++ for qw( min_servers max_servers ) },
        TTOU => sub { $self->{server}->{$_}-- for qw( min_servers max_servers ) },
    );
}

sub run_parent {
    my $self = shift;
    $0 = "starman master " . join(" ", @{$self->{options}{argv} || []});
    $self->SUPER::run_parent(@_);
}

# The below methods run in the child process

sub child_init_hook {
    my $self = shift;
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
            SERVER_NAME     => $self->{server}->{sockaddr}, # XXX: needs to be resolved?
            SERVER_PORT     => $self->{server}->{sockport},
            SCRIPT_NAME     => '',
            'psgi.version'      => [ 1, 1 ],
            'psgi.errors'       => *STDERR,
            'psgi.url_scheme'   => 'http',
            'psgi.nonblocking'  => Plack::Util::FALSE,
            'psgi.streaming'    => Plack::Util::TRUE,
            'psgi.run_once'     => Plack::Util::FALSE,
            'psgi.multithread'  => Plack::Util::FALSE,
            'psgi.multiprocess' => Plack::Util::TRUE,
            'psgix.io'          => $conn,
            'psgix.input.buffered' => Plack::Util::TRUE,
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
                    syswrite $conn, 'HTTP/1.1 100 Continue' . $CRLF . $CRLF;
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
            last unless $sel->can_read(1);
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
            last if $self->{client}->{inputbuf} =~ /$CRLF$CRLF/s;

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
    $self->{client}->{inputbuf} =~ s/.*?$CRLF$CRLF//s;

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
                } elsif (length $chunk_buffer < $chunk_len) {
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

    my $protocol = $env->{SERVER_PROTOCOL};
    my $status   = $res->[0];
    my $message  = status_message($status);

    my(@headers, %headers);
    push @headers, "$protocol $status $message";

    # Switch on Transfer-Encoding: chunked if we don't know Content-Length.
    my $chunked;
    while (my($k, $v) = splice @{$res->[1]}, 0, 2) {
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
    syswrite $conn, join( $CRLF, @headers, '' ) . $CRLF;

    if (defined $res->[2]) {
        Plack::Util::foreach($res->[2], sub {
            my $buffer = $_[0];
            if ($chunked) {
                my $len = length $buffer;
                $buffer = sprintf( "%x", $len ) . $CRLF . $buffer . $CRLF;
            }
            syswrite $conn, $buffer;
            DEBUG && warn "[$$] Wrote " . length($buffer) . " bytes\n";
        });

        syswrite $conn, "0$CRLF$CRLF" if $chunked;
    } else {
        return Plack::Util::inline_object
            write => sub {
                my $buffer = $_[0];
                if ($chunked) {
                    my $len = length $buffer;
                    $buffer = sprintf( "%x", $len ) . $CRLF . $buffer . $CRLF;
                }
                syswrite $conn, $buffer;
                DEBUG && warn "[$$] Wrote " . length($buffer) . " bytes\n";
            },
            close => sub {
                syswrite $conn, "0$CRLF$CRLF" if $chunked;
            };
    }
}

1;
