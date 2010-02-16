package Starman;

use strict;
use 5.008_001;
our $VERSION = '0.1000';

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Starman - High-performance preforking PSGI web server

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

Here's a simple benchmark using C<Hello.psgi>.

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

This benchmark was processed with C<ab -c 10 -t 1 -k> on MacBook Pro
13" late 2009 model on Mac OS X 10.6.2 with perl 5.10.0. YMMV.

=head1 NAMING

=head2 Starman?

The name Starman is taken from the song (I<Star na Otoko>) by the
Japanese rock band Unicorn. It's also a power-up from Super Mario
Brothers and a character from the video game Earthbound.

=head2 Why the cute name instead of more descriptive namespace? Are you on drugs?

I'm sick of naming Perl software like
HTTP::Server::PSGI::How::Its::Written::With::What::Module and people
call it HSSPHIWWWM on IRC. It's hard to say on speeches and newbies
would ask questions what they stand for every day. That's crazy.

This module actually includes the longer alias and an empty subclass
L<HTTP::Server::PSGI::Net::Server::PreFork> for those who like to type
more ::'s. It would actually help you find this software by searching
for I<PSGI Server Prefork> on CPAN, which i believe is a good thing.

Yes, maybe I'm on drugs. We'll see.

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
