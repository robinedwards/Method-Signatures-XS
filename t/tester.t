package Bar;
use Method::Signatures::XS;

method say_hi ($name) {
    print "about to segfault:\n";
    #   print "Hello $name!\n";
}

__PACKAGE__->say_hi("Jim");

1;
