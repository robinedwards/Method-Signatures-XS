package Bar;
use Method::Signatures::XS;

method foo ($aa, $b) {
    print "hello world";
    # print "$self $a $b\n";
}

__PACKAGE__->foo(1,2);

1;
