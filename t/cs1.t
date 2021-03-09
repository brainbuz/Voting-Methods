#!/usr/bin/env perl

use 5.022;

# Using Test2, important to specify which version of Test2
# since later versions may break things.
use Test2::V0;
use Test2::Bundle::More;
use Test::Exception;
# use JSON::MaybeXS qw/encode_json/;
# use YAML::XS;
use feature qw /postderef signatures/;
no warnings 'experimental';
# use Path::Tiny;
use Vote::Count::Method::Cascade;
use Vote::Count::Charge::Utility 'FullCascadeCharge', 'NthApproval';
use Vote::Count::ReadBallots 'read_ballots';
use Test2::Tools::Exception qw/dies lives/;
use Test2::Tools::Warnings qw/warns warning warnings no_warnings/;
use Vote::Count::Charge::TestBalance 'balance_ok';
use Data::Printer;
use Storable 3.15 'dclone';
use Data::Dumper;
# use Carp::Always;

sub argtemplate ($file, $namepattern) {
  return (
    BallotSet => { read_ballots => $file },
    CalculatedPrecedenceFile => "${namepattern}_charge_precedence.txt",
    IterationLog => $namepattern,
    LogTo     => $namepattern,
    AutomaticDefeat => 'NthApproval',
    DropRule => 'topcount' ),
    EstimationFresh => 0,
    EstimationRule => 'estimate',
    FinalPhase => 0,
    FinalPhaseMethod => 'none',
    FloorRule => 'Approval',
    FloorThresshold => 1,
    Seats     => 7,
    VoteValue => 100000,
    QuotaTrigger => 100,
    }

my %mpargs = argtemplate('t/data/MOCKADELPHIA.txt', '/tmp/mockadelphia');
# $mpargs{FinalPhase }= 1;
$mpargs{FinalPhaseMethod} = 'smith';

my $mp = Vote::Count::Method::Cascade->new( %mpargs );
$mp->StartElection();
my @elected = $mp->Conduct();


# note $mp->logv;
# note $mp->PrecedenceFile;
# my %args1 = template( '/tmp/votecount_cascademethod_dmb1');
# my %args2 = template( '/tmp/votecount_short1');

# note $args1{LogTo};
# $args1{LogTo} = '/tmp/foobar';
# note $args2{LogTo};
# note $args1{LogTo};
ok 1;
done_testing;
=pod
# my $DMB1 =
#   Vote::Count::Method::Cascade->new(
#   );

$DMB1->StartElection;
my @elected = $DMB1->Conduct();
# note( $DMB1->logv );
# note Dumper @elected;
my $expectwin = [ 'David_MCBRIDE_Lab',  'Elizabeth_RUINE_Lab', 'Iain_MCLAREN_SNP', 'Karen_CONAGHAN_SNP'];
is_deeply( \@elected, $expectwin, 'first run winners ***' );

my $DMB2 =
  Vote::Count::Method::Cascade->new(
    Seats     => 4,
    BallotSet => read_ballots('t/data/Scotland2017/Dumbarton.txt'),
    VoteValue => 100000,
    IterationLog => '/tmp/votecount_cascademethod_dmb2',
    LogTo     => '/tmp/votecount_cascademethod_dmb2',
    FloorThresshold => 1,
    FloorRule => 'TopCount',
    DropRule => 'bottomrunoff',
    # FinalPhase => 'approval',
  );
$DMB2->StartElection;
@elected = $DMB2->Conduct();
# note( $DMB2->logv );
# note Dumper @elected;
$expectwin = [ 'Brian_WALKER_Con', 'David_MCBRIDE_Lab', 'George_BLACK_WDCP', 'Karen_CONAGHAN_SNP'];
is_deeply( \@elected, $expectwin, 'second run winners' );


my $DMB3 =
  Vote::Count::Method::Cascade->new(
    Seats     => 4,
    BallotSet => read_ballots('t/data/Scotland2017/Dumbarton.txt'),
    VoteValue => 100,
    IterationLog => '/tmp/votecount_cascademethod_dmb3',
    LogTo     => '/tmp/votecount_cascademethod_dmb3',
    FloorThresshold => 1,
    FloorRule => 'TopCount',
    DropRule => 'topcount',
    AutomaticDefeat => 'none',
    FinalPhase => 'approval',
  );
$DMB3->StartElection;
@elected = $DMB3->Conduct();
note( $DMB3->logv );

my $BIG1 =
  Vote::Count::Method::Cascade->new(
    Seats     => 4,
    BallotSet => read_ballots('t/data/biggerset1.txt'),
    VoteValue => 100,
    IterationLog => '/tmp/votecount_cascademethod_big1',
    LogTo     => '/tmp/votecount_cascademethod_big1',
    FloorThresshold => 1,
    FloorRule => 'TopCount',
    DropRule => 'topcount',
    AutomaticDefeat => 'none',
    FinalPhase => 'approval',
  );
$BIG1->StartElection;
@elected = $BIG1->Conduct();
note( $BIG1->logv );


# note Dumper @elected;
# 100000 82 10000 57 1000 36 100 16

done_testing();
