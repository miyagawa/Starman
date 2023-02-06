# NAME

Starman - High-performance preforking PSGI/Plack web server

# SYNOPSIS

    # Run app.psgi with the default settings
    > starman

    # run with Server::Starter
    > start_server --port 127.0.0.1:80 -- starman --workers 32 myapp.psgi

    # UNIX domain sockets
    > starman --listen /tmp/starman.sock

Read more options and configurations by running \`perldoc starman\` (lower-case s).

# DESCRIPTION

Starman is a PSGI perl web server that has unique features such as:

- High Performance

    Uses the fast XS/C HTTP header parser

- Preforking

    Spawns workers preforked like most high performance UNIX servers
    do. Starman also reaps dead children and automatically restarts the
    worker pool.

- Signals

    Supports `HUP` for graceful worker restarts, and `TTIN`/`TTOU` to
    dynamically increase or decrease the number of worker processes, as
    well as `QUIT` to gracefully shutdown the worker processes.

- Superdaemon aware

    Supports [Server::Starter](https://metacpan.org/pod/Server%3A%3AStarter) for hot deploy and graceful restarts.

- Multiple interfaces and UNIX Domain Socket support

    Able to listen on multiple interfaces including UNIX sockets.

- Small memory footprint

    Preloading the applications with `--preload-app` command line option
    enables copy-on-write friendly memory management. Also, the minimum
    memory usage Starman requires for the master process is 7MB and
    children (workers) is less than 3.0MB.

- PSGI compatible

    Can run any PSGI applications and frameworks

- HTTP/1.1 support

    Supports chunked requests and responses, keep-alive and pipeline requests.

- UNIX only

    This server does not support Win32.

# PERFORMANCE

Here's a simple benchmark using `Hello.psgi`.

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

This benchmark was processed with `ab -c 10 -t 1 -k` on MacBook Pro
13" late 2009 model on Mac OS X 10.6.2 with perl 5.10.0. YMMV.

# NOTES

Because Starman runs as a preforking model, it is not recommended to
serve the requests directly from the internet, especially when slow
requesting clients are taken into consideration. It is suggested to
put Starman workers behind the frontend servers such as nginx, and use
HTTP proxy with TCP or UNIX sockets.

# PSGI EXTENSIONS

## psgix.informational

Starman exposes a callback named `psgix.informational` that can be
used for sending an informational response. The callback accepts two
arguments, the first argument being the status code and the second
being an arrayref of the headers to be sent. Example below sends an
103 Early Hints response before processing the request to build a
final response.

    sub {
        my $env = shift;

        $env->{'psgix.informational'}->( 103, [
            "Link" => "</style.css>; rel=preload"
        ] );

        my $rest = ...
        $resp;
    }

# AUTHOR

Tatsuhiko Miyagawa <miyagawa@bulknews.net>

Andy Grundman wrote [Catalyst::Engine::HTTP::Prefork](https://metacpan.org/pod/Catalyst%3A%3AEngine%3A%3AHTTP%3A%3APrefork), which this module
is heavily based on.

Kazuho Oku wrote [Net::Server::SS::PreFork](https://metacpan.org/pod/Net%3A%3AServer%3A%3ASS%3A%3APreFork) that makes it easy to add
[Server::Starter](https://metacpan.org/pod/Server%3A%3AStarter) support to this software.

The `psgix.informational` callback comes from [Starlet](https://metacpan.org/pod/Starlet) by Kazuho Oku.

# COPYRIGHT

Tatsuhiko Miyagawa, 2010-

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[Plack](https://metacpan.org/pod/Plack) [Catalyst::Engine::HTTP::Prefork](https://metacpan.org/pod/Catalyst%3A%3AEngine%3A%3AHTTP%3A%3APrefork) [Net::Server::PreFork](https://metacpan.org/pod/Net%3A%3AServer%3A%3APreFork)
