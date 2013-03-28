use Test::TCP;
use LWP::UserAgent;
use FindBin;
use Test::More;

my $s = Test::TCP->new(
    code => sub {
        my $port = shift;
        exec $^X, "script/starman", "--port", $port, "--max-requests=1", "--workers=1", "t/findbin.psgi";
    },
);

my $ua = LWP::UserAgent->new(timeout => 3);

for (1..2) {
    my $res = $ua->get("http://localhost:" . $s->port);
    is $res->content, $FindBin::Bin;
}

done_testing;
