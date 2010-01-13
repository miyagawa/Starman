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
    my $builder = sub { $server_class->new(%{$_[0]}) };

    my @wrappers;
    if ($ENV{NOMO_USE_CONTROLFREAK}) {
        $workers = 1;
        push @wrappers, "ControlFreak";
    } else {
        push @wrappers, "Prefork" if $workers > 1;
        push @wrappers, "ServerStarter" if $ENV{SERVER_STARTER_PORT};
    }

    for my $wrapper (@wrappers) {
        my $wrapper_class = Plack::Util::load_class($wrapper, "Nomo::Engine::$engine");
        $builder = build { $wrapper_class->wrap(@_) } $builder, \%opts;
    }

    $opts{max_workers} = $workers;

    my $server = $builder->(\%opts);
    bless { server => $server }, $class;
}

sub run {
    my($self, $app) = @_;

    $self->{server}->run($app);
}

1;
