use 5.013;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => "Method::Signatures::XS",
    VERSION_FROM => "lib/Method/Signatures/XS.pm",
    PREREQ_PM => {},
    ABSTRACT_FROM => "lib/Method/Signatures/XS.pm",
    AUTHOR => "Robin Edwards",
);

1;
