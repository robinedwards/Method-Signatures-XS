use Test::More 'no_plan';# => 4;
require_ok "Method::Signatures::XS";

package foo;
use 5.013;
use Test::More;
use Method::Signatures::XS;

method name { 
    ok 1, "method called";
    return 1;
}

1;


ok 1, 'package defined';

ok(foo->name(), "method returned");

