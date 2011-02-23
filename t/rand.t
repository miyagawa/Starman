use Test::TCP;
use LWP::UserAgent;
use FindBin;
use Test::More;

my $s = Test::TCP->new(
    code => sub {
        my $port = shift;
        exec "$^X bin/starman --preload-app --port $port --max-requests=1 --workers=1 $FindBin::Bin/rand.psgi";
    },
);

my $ua = LWP::UserAgent->new;

my @res;
for (1..2) {
    push @res, $ua->get("http://localhost:" . $s->port);
}

isnt $res[0]->content, $res[1]->content;

done_testing;
