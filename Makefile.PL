#!/usr/bin/env perl
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Perlbal::Plugin::Router',
    VERSION_FROM  => 'lib/Perlbal/Plugin/Router.pm',
    AUTHOR        => 'Yann Kerherve <yannk@cpan.org>',
    ABSTRACT_FROM => 'lib/Perlbal/Plugin/Router.pm',

    PREREQ_PM     => {
        'Perlbal' => 0,
    },
);
