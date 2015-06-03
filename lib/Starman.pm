package Starman;

use strict;
use 5.008_001;
our $VERSION = '0.4014';

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Starman - High-performance preforking PSGI/Plack web server

=head1 SYNOPSIS

  # Run app.psgi with the default settings
  > starman

  # run with Server::Starter
  > start_server --port 127.0.0.1:80 -- starman --workers 32 myapp.psgi

  # UNIX domain sockets
  > starman --listen /tmp/starman.sock

Read more options and configurations by running `perldoc starman` (lower-case s).

=head1 DESCRIPTION

Starman is a PSGI perl web server that has unique features such as:

=over 4

=item High Performance

Uses the fast XS/C HTTP header parser

=item Preforking

Spawns workers preforked like most high performance UNIX servers
do. Starman also reaps dead children and automatically restarts the
worker pool.

=item Signals

Supports C<HUP> for graceful worker restarts, and C<TTIN>/C<TTOU> to
dynamically increase or decrease the number of worker processes, as
well as C<QUIT> to gracefully shutdown the worker processes.

=item Superdaemon aware

Supports L<Server::Starter> for hot deploy and graceful restarts.

=item Multiple interfaces and UNIX Domain Socket support

Able to listen on multiple interfaces including UNIX sockets.

=item Small memory footprint

Preloading the applications with C<--preload-app> command line option
enables copy-on-write friendly memory management. Also, the minimum
memory usage Starman requires for the master process is 7MB and
children (workers) is less than 3.0MB.

=item PSGI compatible

Can run any PSGI applications and frameworks

=item HTTP/1.1 support

Supports chunked requests and responses, keep-alive and pipeline requests.

=item UNIX only

This server does not support Win32.

=back

=head1 PERFORMANCE

Here's a simple benchmark using C<Hello.psgi>.

  -- server: Starman (workers=10)
  Requests per second:    6849.16 [#/sec] (mean)
  -- server: Twiggy
  Requests per second:    3911.78 [#/sec] (mean)
  -- server: AnyEvent::HTTPD
  Requests per second:    2738.49 [#/sec] (mean)
  -- server: HTTP::Server::PSGI
  Requests per second:    2218.16 [#/sec] (mean)
  -- server: HTTP::Server::PSGI (workers=10)
  Requests per second:    2792.99 [#/sec] (mean)
  -- server: HTTP::Server::Simple
  Requests per second:    1435.50 [#/sec] (mean)
  -- server: Corona
  Requests per second:    2332.00 [#/sec] (mean)
  -- server: POE
  Requests per second:    503.59 [#/sec] (mean)

This benchmark was processed with C<ab -c 10 -t 1 -k> on MacBook Pro
13" late 2009 model on Mac OS X 10.6.2 with perl 5.10.0. YMMV.

=head1 NOTES

Because Starman runs as a preforking model, it is not recommended to
serve the requests directly from the internet, especially when slow
requesting clients are taken into consideration. It is suggested to
put Starman workers behind the frontend servers such as nginx, and use
HTTP proxy with TCP or UNIX sockets.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Andy Grundman wrote L<Catalyst::Engine::HTTP::Prefork>, which this module
is heavily based on.

Kazuho Oku wrote L<Net::Server::SS::PreFork> that makes it easy to add
L<Server::Starter> support to this software.


=head1 COPYRIGHT

Tatsuhiko Miyagawa, 2010-

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Plack> L<Catalyst::Engine::HTTP::Prefork> L<Net::Server::PreFork>

=cut
