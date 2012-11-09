if ($^O eq 'MSWin32') {
    print STDERR "OS unsupported: $^O\n";
    exit;
}

use inc::Module::Install;
name 'Starman';
all_from 'lib/Starman.pm';
readme_from 'lib/Starman.pm';
build_requires 'Test::More';
requires 'Plack', 0.9971;
requires 'Net::Server', 0.91;
requires 'Data::Dump';
requires 'HTTP::Parser::XS';
requires 'HTTP::Status';
requires 'HTTP::Date';
requires 'parent';
requires 'Test::TCP', 1.11;
install_script 'bin/starman';
recommends 'Server::Starter', 0.12;
recommends 'Net::Server::SS::PreFork';
test_requires 'Test::Requires';
author_tests('xt');
auto_set_repository;
WriteAll;
