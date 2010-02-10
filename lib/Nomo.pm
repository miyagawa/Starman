package Nomo;

use strict;
use 5.008_001;
our $VERSION = '0.01';

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Nomo - High-performance preforking PSGI web server

=head1 SYNOPSIS

  # Run app.psgi with the default settings
  > nomo

  # run with Server::Starter
  > start_server --port 127.0.0.1:80 -- nomo --max-servers 32 myapp.psgi

  # UNIX domain sockets
  > nomo --listen /tmp/nomo.sock

=head1 DESCRIPTION

Nomo is a PSGI perl web server that has unique features such as:

=over 4

=item High Performance

Uses the fast XS/C HTTP header parser

=item Preforking

Spawns workers preforked like most high performance UNIX servers
do. Nomo also reaps dead children and automatically restarts the
worker pool.

=item Signals

Supports C<HUP> for graceful restarts, and C<TTIN>/C<TTOU> to
dynamically increase or decrease the number of worker processes.

=item Superdaemon aware

Supports L<Server::Starter> for hot deploy and graceful restarts.

=item Multiple interfaces and UNIX Domain Socket support

Able to listen on multiple intefaces including UNIX sockets.

=item PSGI compatible

Can run any PSGI applications and frameworks

=item HTTP/1.1 support

Supports chunked requests and responses, keep-alive and pipeline requests.

=back

=head1 PERFORMANCE

A simple benchmark using C<Hello.psgi> as of Plack git SHA I<82121a>
with ApacheBench concurrenty 10 and Keep-alive on.

  -- server: Nomo
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

=head1 NOMO?

The name Nomo is taken from the baseball player L<Hideo
Nomo|http://en.wikipedia.org/wiki/Hideo_Nomo>, who is a great starter,
famous for his forkball and whose nickname is Tornado.

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
