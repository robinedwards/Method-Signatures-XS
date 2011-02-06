package Method::Signatures::XS;
use 5.012;
use strict;
use warnings;

our $VERSION = "0.001";

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

1;

__END__

head1 NAME

Method::Signatures::XS - method declarations using the keyword API.

=head1 VERSION

version 0.001;

=head1 SYNOPSIS

    use Method::Signatures::XS

    method foo { $self->bar }

    method foo($a, $b) {
        return $a + $b;
    }

=head1 EXPERIMENTAL

This module is extremely easy to break (try adding a few returns in your method declaration). It is merely a proof of concept.

Hopefully over the next few months I can make it work. Maybe I will even write a small API so we don't have to work in XS?

=head1 AUTHOR

Robin Edwards C<< <robin.ge at gmail.com> >>

=head1 SEE ALSO

L<Devel::Declare>, L<Method::Signatures>, L<MooseX::Method::Signatures>

    git://github.com/robinedwards/Devel-Declare-Evil.git

=head1 CODE

    git://github.com/robinedwards/Method-Signatures-XS.git

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Robin Edwards

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself, either Perl version 5.12.1 or, at your option, any later version of Perl 5 you may have available.
=cut
