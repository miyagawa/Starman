package Nomo::Loader;
use strict;
use Plack::Util;

sub build(&$;$) {
    my($builder, $cb, $opts) = @_;
    sub { $builder->($cb, $opts) };
}

sub new {
    my($class, %opts) = @_;

    my $engine  = $opts{engine}      || "HTTPServer"; # TODO support AnyEvent
    my $workers = $opts{max_workers} || 32;

    my $server_class = Plack::Util::load_class($engine, "Nomo::Engine");
    my $server = sub { $server_class->new(@_) };

    my @wrappers;
    push @wrappers, "Prefork" if $workers > 1;
    push @wrappers, "ServerStarter" if $ENV{SERVER_STARTER_PORT};

    for my $wrapper (@wrappers) {
        my $wrapper_class = Plack::Util::load_class($wrapper, "Nomo::Engine::$engine");
        $server = build { $wrapper_class->wrap(@_) } $server, \%opts;
    }

    bless { server => $server, opts => \%opts }, $class;
}

sub run {
    my($self, $app) = @_;

    my $server = $self->{server}->(%{$self->{opts}});
    $server->run($app);
}

1;
