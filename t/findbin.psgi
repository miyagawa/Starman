use strict;
use FindBin;
sub {
    my $env = shift;
    return [ 200, [ "Content-Type", "text/plain" ], [ $FindBin::Bin ] ];
};
