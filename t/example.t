use 5.012;
use strict;
use warnings;
use Test::More 'no_plan';
require_ok "Method::Signatures::XS";

package Foo; {
    use Test::More;
    use strict;
    use warnings;
    use Data::Dumper;
    use Method::Signatures::XS;

    method new_method { 
        ok 1, "new_method called";
        return 1;
    }

    sub sub_method {
        ok 1, "sub_method called";
        return 1;
    }

    method new {
        return bless {}, __PACKAGE__ ;
    }

    method with_sig ($a, $b, $c) {
        return $a + $b + $c;
    }
}


ok 1, 'package defined';

ok(Foo->sub_method(), "class method 'sub_method' works");
ok(Foo->new_method(), "class method 'new_method' returns");


my $foo = Foo->new;
isa_ok($foo, 'Foo', 'constructor works');


ok($foo->sub_method(), "class method 'sub_method' works");
ok($foo->new_method(), "class method 'new_method' returns");

is($foo->with_sig(1,1,1), 3, "method call with sig");
