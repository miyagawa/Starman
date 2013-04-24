
use strict;
use warnings;

use 5.008001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "High-performance preforking PSGI/Plack web server",
  "AUTHOR" => "Tatsuhiko Miyagawa <miyagawa\@bulknews.net>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Starman",
  "EXE_FILES" => [
    "script/starman"
  ],
  "LICENSE" => "perl",
  "NAME" => "Starman",
  "PREREQ_PM" => {
    "Data::Dump" => 0,
    "HTTP::Date" => 0,
    "HTTP::Parser::XS" => 0,
    "HTTP::Status" => 0,
    "Net::Server" => "0.91",
    "Plack" => "0.9971",
    "Test::TCP" => "1.11",
    "parent" => 0
  },
  "TEST_REQUIRES" => {
    "Test::More" => 0,
    "Test::Requires" => 0
  },
  "VERSION" => "0.3009",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



