package Point;

use Moose;

has x => ( isa => 'Num', is => 'rw', default => 0 );
has y => ( isa => 'Num', is => 'rw', default => 0 );

sub move {
    my ($self, $x, $y) = @_;
    $self->x($x);
    $self->y($y);
}

__PACKAGE__->meta->make_immutable;

package Point3D;

use Moose;
extends qw/Point/;

has z => ( isa => 'Num', is => 'rw', default => 0 );

sub move {
    my ( $self, $x, $y, $z ) = @_;
    $self->SUPER::move($x, $y);
    $self->z($z);
}

__PACKAGE__->meta->make_immutable;

package main;

my $p = Point3D->new();
for ( 1 .. 10_000_000 ) {
    $p->move($_, $_ + 1, $_ + 2);
}

1;
