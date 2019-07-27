use strict;
use warnings;
use 5.022;

package Vote::Count::RankCount;

use feature qw /postderef signatures/;
no warnings 'experimental';
use List::Util qw( min max sum);
use TextTableTiny  qw/generate_markdown_table/;
# use boolean;
# use Data::Printer;

our $VERSION='0.012';

=head1 NAME

Vote::Count::RankCount

=head1 VERSION 0.012

=cut

# ABSTRACT: RankCount object for Vote::Count. Toolkit for vote counting.


sub _RankResult ( $rawcount ) {
  my %rc      = $rawcount->%*;    # destructive process needs to use a copy.
  my %ordered = ();
  my %byrank  = () ;
  my $pos = 0;
  my $maxpos = scalar( keys %rc ) ;
  while ( 0 < scalar( keys %rc ) ) {
    $pos++;
    my @vrc      = values %rc;
    my $max      = max @vrc;
    for my $k ( keys %rc ) {
      if ( $rc{$k} == $max ) {
        $ordered{$k} = $pos;
        delete $rc{ $k };
        if ( defined $byrank{$pos} ) {
          push @{ $byrank{$pos} }, $k;
        }
        else {
          $byrank{$pos} = [ $k ];
        }
      }
    }
    die "Vote::Count::RankCount::Rank in infinite loop\n" if
      $pos > $maxpos ;
    ;
  }
  # %byrank[1] is arrayref of 1st position,
  # $pos still has last position filled, %byrank{$pos} is the last place.
  # sometimes byranks came in as var{byrank...} deref and reref fixes this
  # although it would be better if I understood why it happened.
  # It is useful to sort the arrays anyway, for display they would likely be
  # sorted anyway. For testing it makes the element order predictable.
  my @top = sort @{$byrank{1}} ;
  my @bottom = sort @{$byrank{ $pos }};
  my $tie = scalar(@top) > 1 ? 1 : 0 ;
  return {
    'rawcount' => $rawcount,
    'ordered' => \%ordered,
    'byrank' => \%byrank,
    'top' => \@top,
    'bottom' => \@bottom,
    'tie' => $tie,
    };
}

sub Rank ( $class, $rawcount ) {
  my $I = _RankResult( $rawcount);
# p $I;
  return bless $I, $class;
}

sub RawCount ( $I ) { return $I->{'rawcount'} }
sub HashWithOrder ( $I ) { return $I->{'ordered'} }
sub HashByRank ( $I ) { return $I->{'byrank'} }
sub ArrayTop ( $I ) { return  $I->{'top'} }
sub ArrayBottom ( $I ) { return $I->{'bottom'} }
sub CountVotes ($I) { return sum ( values $I->{'rawcount'}->%* )}

sub Leader ( $I ) {
  my @leaders = $I->ArrayTop()->@*;
  my %return = ( 'tie' => 0, 'winner' => '', 'tied' => [] );
  if ( 1 == @leaders ) { $return{'winner'} = $leaders[0] }
  elsif ( 1 < @leaders ) { $return{'tie'} = 1; $return{'tied'} =  \@leaders }
  else { die "Does not compute in sub RankCount->Leader\n"}
  return \%return;
}

sub RankTable( $self ) {
  my @rows = ( [ 'Rank', 'Choice', 'Votes']);
  my %rc = $self->{'rawcount'}->%*;
  my %byrank = $self->{'byrank'}->%*;
  for my $r ( sort keys %byrank ) {
    my @choice = sort $byrank{$r}->@*;
    for my $choice ( @choice ) {
      my $votes = $rc{$choice};
      my @row = ( $r, $choice, $votes );
      push @rows, (\@row);
    }
  }
  return generate_markdown_table( rows => \@rows );
}

1;

#buildpod
#FOOTER

=pod

BUG TRACKER

L<https://github.com/brainbuz/Vote-Count/issues>

AUTHOR

John Karr (BRAINBUZ) brainbuz@cpan.org

CONTRIBUTORS

Copyright 2019 by John Karr (BRAINBUZ) brainbuz@cpan.org.

LICENSE

This module is released under the GNU Public License Version 3. See license file for details. For more information on this license visit L<http://fsf.org>.

=cut

