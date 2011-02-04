package Point;

sub new {
    my ( $class, $x, $y ) = @_;
    bless { x => $x, y => $y }, $class;
}

sub move {
    my ($self, $x, $y) = @_;
    $self->{x} = $x;
    $self->{y} = $y;
}

package Point3D;

use base qw/Point/;

sub move {
    my ( $self, $x, $y, $z ) = @_;
    $self->SUPER::move($x, $y);
    $self->{z} = $z;
}


my $p = Point3D->new();
for ( 1 .. 10_000_000 ) {
    $p->move($_, $_ + 1, $_ + 2);
}

1;
