use strict;
use warnings;
use Method::Signatures::XS;

package Example; {

    method new {
        return bless {}, $self;
    }

    method test_method_with_signature ($a, $b) {
        return $a + $b;
    }

    method test_method {
        return 1 if $self;
    }

    method test_edge_case1{
        return 1;
    }

    method test_edge_case2($a) {
        return 1;
    }


    method test_edge_case3($a){
        return 1;
    }

    method test_edge_case4 
    {
        return 1;
    }

    method test_edge_case5 
    ($a,
    $b,
    $c)

    {
        return 1 + $a + $b + $c;
    }

    method test_edge_case6
    (

    )
    {
        return 1;
    }
}


use Test::More tests => 11;

is Example->test_method, 1, 'class method ';
is Example->test_method_with_signature(1,1), 2, 'class method with signature';

my $obj = Example->new({});
ok defined $obj, "constructor";
is $obj->test_method, 1, 'object method';
is $obj->test_method_with_signature(1,1), 2, 'object method with signature';

is $obj->test_edge_case1, 1, 'parse edge case 1';
is $obj->test_edge_case2, 1, 'parse edge case 2';
is $obj->test_edge_case3, 1, 'parse edge case 3';
is $obj->test_edge_case4, 1, 'parse edge case 4';
is $obj->test_edge_case5(1,1,1), 4, 'parse edge case 5';
is $obj->test_edge_case6, 1, 'parse edge case 6';


