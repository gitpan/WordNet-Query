use ExtUtils::MakeMaker;

WriteMakefile(
    'dist'      => { 'COMPRESS'  => 'gzip', 'SUFFIX'    => '.gz', },
    'NAME'	=> 'WordNet::Query',
    'VERSION_FROM'   => 'Query.pm',
);
