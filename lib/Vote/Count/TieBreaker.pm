use strict;
use warnings;
use 5.024;

use feature qw /postderef signatures switch/;

package Vote::Count::TieBreaker;
use Moose::Role;

no warnings 'experimental';
use List::Util qw( min max sum );
use Path::Tiny;
use Data::Dumper;
use Data::Printer;
use Vote::Count::RankCount;
use List::Util qw( min max sum);
use Carp;
use Try::Tiny;

our $VERSION = '2.00';

=head1 NAME

Vote::Count::TieBreaker

=head1 VERSION 2.00

=head1 Synopsis

  my $Election = Vote::Count->new(
    'BallotSet'      => $ballotsirvtie2,
    'TieBreakMethod' => 'approval',
    'TieBreakerFallBackPrecedence' => 0,
  );

=cut

# ABSTRACT: TieBreaker object for Vote::Count. Toolkit for vote counting.

=head1 TieBreakMethod argument to Vote::Count->new

  'approval'
  'topcount'
  'all' [ eliminate all tied choices ]
  'borda' [ Borda Count to current Active set ]
  'borda_all' [ includes all choices in Borda Count ]
  'grandjunction' [ more resolveable than simple TopCount would be ]
  'none' [ eliminate no choices ]
  'precedence' [ requires also setting PrecedenceFile ]

Approval, TopCount, and Borda may be passed in either lower case or in the CamelCase form of the method name. These methods only consider the current choices. borda_all calculates the Borda Count with all choices which can yield a different result than just the current choices.

=head1 Grand Junction

The Grand Junction (also known as Bucklin) method is one of the simplest and easiest to Hand Count RCV resolution methods. Other than that it is generally not considered a good method.

Because it is simple, and nearly always resolves, except when ballots are perfectly matched up, it is a great TieBreaker. It is not Later Harm Safe, but heavily favors higher rankings.

=head2 The (Standard) Grand Junction Method

Only the Tie-Breaker variant is currently implemented in Vote::Count.

=over

=item 1

Count the Ballots to determine the quota for a majority.

=item 2

Count the first choices and elect a choice which has a majority.

=item 3

If there is no winner add the second choices to the totals and elect the choice which has a majority (or the most votes if more than one choice reaches a majority).

=item 4

Keep adding the next rank to the totals until either there is a winner or all ballots are exhausted.

=item 5

When all ballots are exhausted the choice with the highest total wins.

=back

=head2 As a Tie Breaker

The Tie Breaker Method is modified.

Instead of Majority, any choice with a current total less than another is eliminated. This allows resolution of any number of choices in a tie.

The winner is the last choice remaining.

=head2 TieBreakerGrandJunction

  my $resolve = $Election->TieBreakerGrandJunction( $choice1, $choice2 [ $choice3 ... ]  );
  if ( $resolve->{'winner'}) { say "Tie Winner is $resolve->{'winner'}"}
  elsif ( $resolve->{'tie'}) {
    my @tied = $resolve->{'tied'}->@*;
    say "Still tied between @tied."
  }

The Tie Breaking will be logged to the verbose log, any number of tied choices may be provided.

=cut

has 'TieBreakMethod' => (
  is       => 'rw',
  isa      => 'Str',
  required => 0,
);

# This is only used for the precedence tiebreaker and fallback!
has 'PrecedenceFile' => (
  is       => 'rw',
  isa      => 'Str',
  required => 0,
  trigger  => \&_triggercheckprecedence,
);

has 'TieBreakerFallBackPrecedence' => (
  is      => 'rw',
  isa     => 'Bool',
  default => 0,
  lazy    => 0,
  trigger => \&_triggercheckprecedence,
);

sub _triggercheckprecedence ( $I, $new, $old = undef ) {
  unless ( $I->PrecedenceFile() ) {
    $I->PrecedenceFile('/tmp/precedence.txt');
    $I->logt( "Generated FallBack TieBreaker Precedence Order: \n"
        . join( ', ', $I->CreatePrecedenceRandom() ) );
  }
  $I->{'PRECEDENCEORDER'} = undef;    # clear cached if the file changes.
}

sub TieBreakerGrandJunction ( $self, @tiedchoices ) {
  my $ballots = $self->BallotSet()->{'ballots'};
  my %current = ( map { $_ => 0 } @tiedchoices );
  my $deepest = 0;
  for my $b ( keys $ballots->%* ) {
    my $depth = scalar $ballots->{$b}{'votes'}->@*;
    $deepest = $depth if $depth > $deepest;
  }
  my $round = 1;
  while ( $round <= $deepest ) {
    $self->logv("Tie Breaker Round: $round");
    for my $b ( keys $ballots->%* ) {
      my $pick = $ballots->{$b}{'votes'}[ $round - 1 ] or next;
      if ( defined $current{$pick} ) {
        $current{$pick} += $ballots->{$b}{'count'};
      }
    }
    my $max = max( values %current );
    for my $c ( sort @tiedchoices ) {
      $self->logv("\t$c: $current{$c}");
    }
    for my $c ( sort @tiedchoices ) {
      if ( $current{$c} < $max ) {
        delete $current{$c};
        $self->logv("Tie Breaker $c eliminated");
      }
    }
    @tiedchoices = ( sort keys %current );
    if ( 1 == @tiedchoices ) {
      $self->logv("Tie Breaker Won By: $tiedchoices[0]");
      return { 'winner' => $tiedchoices[0], 'tie' => 0, 'tied' => [] };
    }
    $round++;
  }
  if ( $self->TieBreakerFallBackPrecedence() ) {
    $self->logv('Applying Precedence fallback');
    return $self->TieBreakerPrecedence(@tiedchoices);
  }
  else {
    return { 'winner' => 0, 'tie' => 1, 'tied' => \@tiedchoices };
  }
}

=head1 TieBreaker

Implements some basic methods for resolving ties. The default value for IRV is eliminate 'all', and the default value for Matrix is eliminate 'none'. 'all' is inappropriate for Matrix, and 'none' is inappropriate for IRV.

  my @keep = $Election->TieBreaker( $tiebreaker, $active, @tiedchoices );

TieBreaker returns a list containing the winner, if the method is 'all' the list is empty, if 'none' the original @tiedchoices list is returned. If the TieBreaker is a tie there will be multiple elements.

=head1 Breaking Ties With Precedence

Since many existing Elections Rules call for Random, and Vote::Count does not accept Random as the result will be different bewtween runs, Precedence allows the Administrators of an election to randomly or arbitrarily determine who will win ties before running Vote::Count.

The Precedence list takes the choices of the election one per line. Choices defeat any choice lower than them in the list. When Precedence is used an additional attribute must be specified for the Precedence List.

 my $Election = Vote::Count->new(
   BallotSet => read_ballots('somefile'),
   TieBreakMethod => 'precedence',
   PrecedenceFile => '/path/to/precedencefile');

=head2 Precedence (Method)

Returns a RankCount object from the Precedence List. Takes a HashRef of an Active set as an optional argument, defaults to the Current Active Set.

  my $RankCountByPrecedence = $Election->Precedence();
  my $RankCountByPrecedence = $Election->Precedence( $active );

=head2 CreatePrecedenceRandom

Creates a Predictable Psuedo Random Precedence file, and returns the list. Randomizes the choices using the number of ballots as the Random Seed for Perl's built in rand() function. For any given Ballot File, it will always return the same list. If the precedence filename argument is not given it defaults to '/tmp/precedence.txt'. This is the best solution to use where the Rules call for Random, in a large election the number of ballots cast will be sufficiently random, while anyone with access to Perl can reproduce the Precedence file.

  my @precedence = Vote::Count->new( BallotSet => read_ballots('somefile') )
    ->CreatePrecedenceRandom( '/tmp/precedence.txt');

=head2 TieBreakerFallBackPrecedence

This optional argument enables or disables using precedence as a fallback, generates /tmp/precedence.txt if no PrecedenceFile is specified. Default is off (0).

=head1 UnTieList

Sort a list in an order determined by a ranking method, sorted in Descending Order. The ranking must be a method that returns a RankCount object: Borda, TopCount, Precedence and Approval. If the tie is not resolved it will fallback to Precedence.

  my @orderedlosers = $Election->UnTieList(
    'ranking1' => $Election->TieBreakMethod(), 'tied' => \@unorderedlosers );

A second method may be provided.

  my @orderedlosers = $Election->UnTieList(
    'ranking1' => 'TopCount', 'ranking2' => 'Borda', 'tied' => \@unorderedlosers );

The Rankings are generated at the beginning and used for all resolutions. Precedence must be enabled by either setting the TieBreakMethod to Precedence or setting TieBreakerFallBackPrecedence to a true value.

=head1 UnTieActive

Produces a precedence list of all the active choices in the election. Takes the same arguments as UnTieList.

  my @untiedset = $Election->UnTieActive( 'ranking1' => 'TopCount', 'ranking2' => 'Approval');

=cut

sub _precedence_sort ( $I, @list ) {
  my %ordered = ();
  my $start   = 0;
  if ( defined $I->{'PRECEDENCEORDER'} ) {
    %ordered = $I->{'PRECEDENCEORDER'}->%*;
  }
  else {
    for ( split /\n/, path( $I->PrecedenceFile() )->slurp() ) {
      $_ =~ s/\s//g;    #strip out any accidental white space
      $ordered{$_} = ++$start;
    }
    for my $c ( $I->GetChoices ) {
      unless ( defined $ordered{$c} ) {
        croak "Choice $c missing from precedence file\n";
      }
    }
    $I->{'PRECEDENCEORDER'} = \%ordered;
  }
  my %L = map { $ordered{$_} => $_ } @list;
  return ( map { $L{$_} } ( sort { $a <=> $b } keys %L ) );
}

sub TieBreakerPrecedence ( $I, @tiedchoices ) {
  my @list = $I->_precedence_sort(@tiedchoices);
  return { 'winner' => $list[0], 'tie' => 0, 'tied' => [] };
}

sub CreatePrecedenceRandom ( $I, $outfile = '/tmp/precedence.txt' ) {
  my @choices    = $I->GetActiveList();
  my %randomized = ();
  srand( $I->BallotSet()->{'votescast'} );
  while (@choices) {
    my $next   = shift @choices;
    my $random = int( rand(1000000) );
    if ( defined $randomized{$random} ) {
      # collision, this choice needs to do again.
      unshift @choices, ($next);
    }
    else {
      $randomized{$random} = $next;
    }
  }
  my @precedence =
    ( map { $randomized{$_} } sort { $a <=> $b } ( keys %randomized ) );
  path($outfile)->spew( join( "\n", @precedence ) . "\n" );
  return @precedence;
}

sub TieBreaker ( $I, $tiebreaker, $active, @tiedchoices ) {
  no warnings 'uninitialized';
  $tiebreaker = lc $tiebreaker;
  if ( $tiebreaker eq 'none' ) { return @tiedchoices }
  if ( $tiebreaker eq 'all' )  { return () }
  my $choices_hashref = { map { $_ => 1 } @tiedchoices };
  my $ranked          = undef;
  if ( $tiebreaker eq 'borda' ) {
    $ranked = $I->Borda($active);
  }
  elsif ( $tiebreaker eq 'borda_all' ) {
    $ranked = $I->Borda( $I->BallotSet()->{'choices'} );
  }
  elsif ( $tiebreaker eq 'approval' ) {
    $ranked = $I->Approval($choices_hashref);
  }
  elsif ( $tiebreaker eq 'topcount' ) {
    $ranked = $I->TopCount($choices_hashref);
  }
  elsif ( $tiebreaker eq 'grandjunction' ) {
    my $GJ = $I->TieBreakerGrandJunction(@tiedchoices);
    if    ( $GJ->{'winner'} ) { return $GJ->{'winner'} }
    elsif ( $GJ->{'tie'} )    { return $GJ->{'tied'}->@* }
    else { croak "unexpected (or no) result from $tiebreaker!\n" }
  }
  elsif ( $tiebreaker eq 'precedence' ) {
    # The one nice thing about precedence is that there is always a winner.
    return $I->TieBreakerPrecedence(@tiedchoices)->{'winner'};
  }
  else { croak "undefined tiebreak method $tiebreaker!\n" }
  my @highchoice = ();
  my $highest    = 0;
  my $counted    = $ranked->RawCount();
  for my $c (@tiedchoices) {
    if ( $counted->{$c} > $highest ) {
      @highchoice = ($c);
      $highest    = $counted->{$c};
    }
    elsif ( $counted->{$c} == $highest ) {
      push @highchoice, $c;
    }
  }
  my $terse =
      "Tie Breaker $tiebreaker: "
    . join( ', ', @tiedchoices )
    . "\nwinner(s): "
    . join( ', ', @highchoice );
  $I->{'last_tiebreaker'} = {
    'terse'   => $terse,
    'verbose' => $ranked->RankTable(),
  };
  if ( @highchoice > 1 ) {
    if ( $I->TieBreakerFallBackPrecedence() ) {
      return ( $I->TieBreakerPrecedence(@tiedchoices)->{'winner'} );
    }
  }
  return (@highchoice);
}

# untielist
# xxxxxx 1. sort criteria
# 2. tiebraker to rank count
# 3. fallback (implied)
# will untie a list according to tiebreaker and precedence fallback.

sub Precedence ( $I, $active = undef ) {
  $active = $I->Active() unless defined $active;
  return Vote::Count::RankCount->newFromList(
    $I->_precedence_sort( keys( $active->%* ) ) );
}

sub precedence { Precedence(@_) }

sub _shortuntie ( $I, $RC, @tied ) {
  my %T     = map { $_ => $RC->{$_} } @tied;
  my @order = ();
  while ( keys %T ) {
    my $best    = min values %T;
    my @leaders = ();
    for my $leader ( keys %T ) {
      push @leaders, $leader if $T{$leader} == $best;
    }
    @leaders = $I->_precedence_sort(@leaders);
    push @order, @leaders;
    for (@leaders) { delete $T{$_} }
  }
  return @order;
}

sub UnTieList ( $I, %args ) {
  no warnings 'uninitialized';
  unless ( $I->TieBreakerFallBackPrecedence()
    or $I->TieBreakMethod eq 'precedence' )
  {
    croak
"TieBreakerFallBackPrecedence must be enabled or TieBreakMethod must be precedence to use UnTieList [UnTieActive and BottomRunOff call it]";
  }
  my $ranking1  = $args{ranking1};
  my $ranking2  = $args{ranking2} || 'precedence';
  my @tied      = $args{tied}->@*;
  my %tieactive = map { $_ => 1 } @tied;

  my @ordered = ();
  return $I->_precedence_sort(@tied) if ( lc($ranking1) eq 'precedence' );
  my $RC1 = $I->$ranking1( \%tieactive )->HashByRank();
  my $RC2 = $I->$ranking2( \%tieactive )->HashWithOrder();
  for my $level ( sort { $a <=> $b } ( keys $RC1->%* ) ) {
    my @l = @{ $RC1->{$level} };
    my @suborder = ();
    if    ( 1 == $RC1->{$level}->@* ) { @suborder = @l }
    elsif ( $ranking2 eq 'precedence' ) {
      @suborder = $I->_precedence_sort(@l);
    }
    else {
      @suborder = $I->_shortuntie( $RC2, @l );
    }
    push @ordered, @suborder;
  }
  return @ordered;
}

sub UnTieActive ( $I, %ARGS ) {
  $I->UnTieList( %ARGS, 'tied' => [ $I->GetActiveList() ], );
}

1;

#FOOTER

=pod

BUG TRACKER

L<https://github.com/brainbuz/Vote-Count/issues>

AUTHOR

John Karr (BRAINBUZ) brainbuz@cpan.org

CONTRIBUTORS

Copyright 2019-2021 by John Karr (BRAINBUZ) brainbuz@cpan.org.

LICENSE

This module is released under the GNU Public License Version 3. See license file for details. For more information on this license visit L<http://fsf.org>.

SUPPORT

This software is provided as is, per the terms of the GNU Public License. Professional support and customisation services are available from the author.

=cut

