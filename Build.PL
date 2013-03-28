
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601",
    "Test::More" => 0,
    "Test::Requires" => 0
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "High-performance preforking PSGI/Plack web server",
  "dist_author" => [
    "Tatsuhiko Miyagawa <miyagawa\@bulknews.net>"
  ],
  "dist_name" => "Starman",
  "dist_version" => "0.3007",
  "license" => "perl",
  "module_name" => "Starman",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Data::Dump" => 0,
    "HTTP::Date" => 0,
    "HTTP::Parser::XS" => 0,
    "HTTP::Status" => 0,
    "Net::Server" => "0.91",
    "Plack" => "0.9971",
    "Test::TCP" => "1.11",
    "parent" => 0,
    "perl" => "5.008001"
  },
  "script_files" => [
    "script/starman"
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
