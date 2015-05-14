use Test::TCP;
use LWP::UserAgent;
use FindBin;
use Test::More;

for (1..2) { # preload, non-preload
    my @preload = $_ == 1 ? ("--preload-app") : ();

    my $s = Test::TCP->new(
        code => sub {
            my $port = shift;
            exec $^X, "script/starman", @preload, "--port", $port, "--max-requests=1", "--workers=1", "t/rand.psgi";
        },
    );

    my $ua = LWP::UserAgent->new;

    my @res;
    for (1..2) {
        push @res, $ua->get("http://localhost:" . $s->port);
    }

    isnt $res[0]->content, $res[1]->content;

    undef $s;
}

done_testing;
