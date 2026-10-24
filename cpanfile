requires 'Data::Dump';
requires 'HTTP::Date';
requires 'HTTP::Parser::XS';
requires 'HTTP::Status';
requires 'Net::Server', '2.007';
requires 'Plack', '0.9971';
requires 'Test::TCP', '2.00';
requires 'parent';
requires 'perl', '5.008001';

suggests 'Server::Starter';
suggests 'Net::Server::SS::PreFork';

on test => sub {
    requires 'Test::More';
    requires 'Test::Requires';
    requires 'LWP::UserAgent';
    # Older versions end chunked request bodies without the final CRLF
    requires 'HTTP::Tiny', '0.064';
};

on develop => sub {
    requires 'LWP::Protocol::https';
};
