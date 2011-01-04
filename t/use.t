use Test::More qw/no_plan/;
use Method::Signatures::XS;

method name { 
    warn 'la la la la';
}

ok 1, 'parsed name method ok'; 

name();

ok 1, 'called name method as sub';
