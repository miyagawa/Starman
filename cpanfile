requires 'Data::Dump';
requires 'HTTP::Date';
requires 'HTTP::Parser::XS';
requires 'HTTP::Status';
requires 'Net::Server', '2.007';
requires 'Plack', '0.9971';
requires 'Test::TCP', '2.00';
requires 'parent';
requires 'perl', '5.008001';

on test => sub {
    requires 'Test::More';
    requires 'Test::Requires';
    requires 'LWP::UserAgent';
};
