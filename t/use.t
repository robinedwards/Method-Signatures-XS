use 5.013;
use Test::More 'no_plan';
require_ok "Method::Signatures::XS";

package Foo {
    use Test::More;
    use Method::Signatures::XS;

    sub new { return bless {}, __PACKAGE__ };

    method name { 
        ok 1, "method called";
        return 1;
    }
}

#use Foo;


ok 1, 'package defined';

my $foobar = Foo->new;

ok(Foo->name(), "class method returned");


