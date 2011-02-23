rand(); # this initializes the random seed

sub {
    return [ 200, ["Content-Type", "text/plain"], [ rand(100) ] ];
};
