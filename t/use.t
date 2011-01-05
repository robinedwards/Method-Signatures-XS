use Test::More plan => 4;
require_ok "Method::Signatures::XS";

package foo;
use 5.012;
use Test::More;
use Method::Signatures::XS;

method name { 
    ok 1, "method called";
}

1;


ok 1, 'package defined';

foo->name();

ok 1, 'method call complete';

