package HTTP::Server::Starman;

use strict;
use 5.008_001;
our $VERSION = '0.01';

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

HTTP::Server::Starman - High-performance preforking PSGI web server

=head1 SYNOPSIS

  # Run app.psgi with the default settings
  > starman

  # run with Server::Starter
  > start_server --port 127.0.0.1:80 -- starman --max-servers 32 myapp.psgi

  # UNIX domain sockets
  > starman --listen /tmp/starman.sock

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

Supports C<HUP> for graceful restarts, and C<TTIN>/C<TTOU> to
dynamically increase or decrease the number of worker processes.

=item Superdaemon aware

Supports L<Server::Starter> for hot deploy and graceful restarts.

=item Multiple interfaces and UNIX Domain Socket support

Able to listen on multiple intefaces including UNIX sockets.

=item Small memory footprint

Preloading the applications enables copy-on-write friendly memory
management. Also, the minimum memory usage Starman requires for the
master process is 7MB and children (workers) is less than 3.0MB.

=item PSGI compatible

Can run any PSGI applications and frameworks

=item HTTP/1.1 support

Supports chunked requests and responses, keep-alive and pipeline requests.

=back

=head1 PERFORMANCE

A simple benchmark using C<Hello.psgi> as of Plack git SHA I<82121a>
with ApacheBench concurrenty 10 and Keep-alive on.

  -- server: Starman
  Requests per second:    6413.87 [#/sec] (mean)
  -- server: AnyEvent
  Requests per second:    3911.78 [#/sec] (mean)
  -- server: AnyEvent::HTTPD
  Requests per second:    2738.49 [#/sec] (mean)
  -- server: Standalone
  Requests per second:    1045.66 [#/sec] (mean)
  -- server: Standalone (prefork)
  Requests per second:    2792.99 [#/sec] (mean)
  -- server: HTTP::Server::Simple
  Requests per second:    1435.50 [#/sec] (mean)
  -- server: Coro
  Requests per second:    2332.00 [#/sec] (mean)
  -- server: POE
  Requests per second:    503.59 [#/sec] (mean)

=head1 STARMAN?

The name Starman is taken from the song (I<Star na Otoko>) by a
Japanese rock band Unicorn. It's also a power-up from Super Mario and
a character from the video game Earthbound.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Andy Grundman wrote L<Catalyst::Engine::HTTP::Prefork>, which this module
is heavily based on.

Kazuho Oku wrote L<Net::Server::SS::PreFork> that makes it easy to add
L<Server::Starter> support to this software.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Plack> L<Catalyst::Engine::HTTP::Prefork> L<Net::Server::Prefork>

=cut
