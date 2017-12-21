#  version 19, 2017-02-22
#  5. check 1.35 cm poweron poweroff in case like CK->KK or KK->CK
#  This requires a major revision of the corresponding part.
#
#  version 18, 2017-02-09
#  1. PRM = --
#  +2. check warm up time (shoul dnot be too long)
#  +3. switch off receivers if the gap between observations is >= 5 hours
#  +4. for gravitational observations power on receivers 1 hour in advance. For 6-cm receiver do not switch on the "termostat"
#  5. check 1.35 cm poweron poweroff in case like CK->KK or KK->CK
#  + 6. For 1.35 cm after "vosstanov1.1.35" add 2F0 7/8dB GSH-otkl U 7.5 mA
#  7. Manage subbands of the wide 1 cm receiver.
#
#
#	version 17, 2016-11-30
#	1. Need to rewrite a section on the receivers power on|off
#
#
#	version 16 , 2016-04-07
# 	Feature requests:
#		1) power off ant then power on receivers if there is more than 5 hours between subsequent observations
#	Power on receivers ON DEMAND. Warm up time = 1h30m for CLP, and 1h50m for K.
#	??? Power off receivers
#		2) change COHERENT
#		3) add beginscan, endscan to comments about yust
#
#	BUGFIXES
#	28.10.2013	added FGSVCH on for JUST
#	27.01.2014	changed K-band att to 7/8dB
# 	changed time of comments(begin -2 ) and chapters (begin -1 )
#
#	TODO
#	2) handle multiband experiments
#	3) change power at least 5 min in advance before observation, regadless of before time;
# BUGFIXES and feature adding
# 06sep2013
# 1. fixed GSH_before overlapping with justirovka.
# 2. added GSH_after justirovka var 0-4
# 3. added interactive mode flag --interactive or --i . Unless specified user interaction will be suppressed. Affects GSH performing and writing to ZU when there's not enough time (less than -10 +5)
# 4. added comment line for justirovka(not VIRK). It shouldbe placed properly somewhere between beginscan and endscan.
# 5. if TS time is +0, then perform GSH_low during the scan, and then GSH_high
# 5. if TS time is -0, then perform GSH_low during the scan (GSH_low ON at the beginning of observation)

#

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use Date::Calc qw(:all);
use Getopt::Long;
use List::Util qw(max min);
use List::MoreUtils qw{ minmax any};

require "ra_schedule_read.pl";
use strict;

GetOptions(
    "schedule|s=s"  => \my $sogl,
    "debug|d"       => \my $debug,
    "usage|u"       => \my $usage,
    "interactive|i" => \my $interactive
);
if ($usage) {
    print
"USAGE : perl $0 --s single_schedule_file(after break_sns.pl) [--debug]\n";
    exit 0;
}

unless ( defined $interactive ) {
    $interactive = 0;
}

# USAGE:   perl make_cyclo_vXXXX.pl --d --s dec_2012_8

# version 15
# completely rewritten

our %T = ()  ; # test hash with all blocks. Primary key is block start time. Secondary are start and stop
our %times;    # global hash with a cyclogramm. $T{time_in_seconds}=command
our $t      = 0;    # global time
our $dt     = 5;    # default delay between commands
our $debug2 = 0;
my $default_regim = 'f3/f3';
my %GSHB          = ();        # keys are start times
my %GSHA          = ();        # keys are stop times

#################################################################################################################################################################
#################################################################################################################################################################
#################################################################################################################################################################
#################################################################################################################################################################
#
# the whole workflow
# 1. read Soglasnov style schedule file. There should be difference between observations, justirovka of different variants, justirovka s VIRK, test observations, command sessions.
# 2. determine global start and stop files.
# 3. determine receivers to be powered on and power them on.
# 4. insert GSH(calibration) before and after each observation. For some justirovka variants insert them in proper places.
# prompt user if time is not enough, put ZU on and ZU of commands also
# 5. put 40 W power on before GSH if needed, 4W after GSH if needed
# 6. put kluchi on before, put kluchi off after
# 7. attenuatori if needed
# 8. put RABOTA, REGIM before if needed
# 9. power off receivers after last GSH

# TODO: a) block duration calculation
#	b) schedule reading
#	c) receivers status (keys, attenuators)

# 1. read Soglasnov style schedule file. There should be difference between observations, justirovka of different variants, justirovka s VIRK, test observations, command sessions.

print "Reading schedule file ", $sogl, "\n";

our %S;    # global hash to contain schedule
open G, $sogl;
my @g = <G>;
close G;

( my $srt_options, my $srt_errors ) =
  read_soglasnov( \@g, \%S );    # schedule reading routine

if (@$srt_errors) {

    #	print "SRT schedule file reading errors:\n";
    foreach (@$srt_errors) {

        #		print $_,"\n";
    }
}

# 2. determine global start and stop files.

print "Determining global start and stop times\n";

my $next             = 0;
my $global_start_sec = 0;
my $global_stop_sec  = 0;

foreach ( sort keys %S ) {
    if ( $S{$_}{'type'} eq "sns_cmd" ) {
        if ($next) {
            print print_time( $S{$_}{'start'} ), "\n" if $debug2;
            $global_stop_sec = $S{$_}{'start'};
        }
        else {
            print print_time( $S{$_}{'stop'} ), "\n" if $debug2;
            $next             = 1;
            $global_start_sec = $S{$_}{'stop'};
        }
    }
}




# explicitly delete LASER RANGING sessions from the schedule
foreach ( sort keys %S ) {
	if ( $S{$_}{'type'} eq "sns_ll" ) {
		delete $S{$_};}
}




my @keys = sort keys %S;
for my $i ( 0 .. scalar @keys ) {

    

		print "Going to insert keys\n";

		my $key = $keys[$i];
		
		if (   $S{$key}{'type'} eq "obs"
        || $S{$key}{'type'} eq "just"
        || $S{$key}{'type'} eq "just_virk" )
    {
		
		
		
		if ( $i > 0 ) {
# 			$S{$key}{'prev'} = $S{ $keys[ $i - 1 ] };
			$S{$key}{'prev'} = $keys[ $i - 1 ];
			
		}
		if ( $i < scalar @keys - 1 ) {
# 			$S{$key}{'next'} = $S{ $keys[ $i + 1 ] };
			$S{$key}{'next'} = $keys[ $i + 1 ];
		}
    
    
    }
    
}


# test 
foreach (sort {$a <=> $b} keys %S){

 if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just"
        || $S{$_}{'type'} eq "just_virk" )
    {
	print "*"x50,"\n";
	print "THIS OBSERVATION: ",$S{$_}{'osbcode'},"\n";
	print Dumper($S{$_}),"\n";
	print "next observation obscode:\n";
	print Dumper($S{$S{$_}{'next'}}{'obscode'});
	print "\n"x3;
}
}














print "Global start = ", print_time($global_start_sec), "\n";
print "Global stop  = ", print_time($global_stop_sec),  "\n";

my $time_to_start = 0;
my $firstobskey;    # key of the first observation/justirovka in cyclogramm
my $lastobskey;
foreach ( sort keys %S ) {
    if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just"
        || $S{$_}{'type'} eq "just_virk" )
    {
        $time_to_start = $_ - $global_start_sec;
        $firstobskey   = $_;
        last;
    }
}
my $time_to_stop = 0;
foreach ( reverse sort keys %S ) {
    if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just"
        || $S{$_}{'type'} eq "just_virk" )
    {
        $time_to_stop = $global_stop_sec - $S{$_}{'stop'};
        $lastobskey   = $_;
        last;
    }
}

my $firstvirkkey
  ; # key of the first observation/justirovka_virk in cyclogramm. That uses POWER
my $lastvirkkey;
foreach ( sort keys %S ) {
    if ( $S{$_}{'type'} eq "obs" || $S{$_}{'type'} eq "just_virk" ) {
        $firstvirkkey = $_;
        last;
    }
}
foreach ( reverse sort keys %S ) {
    if ( $S{$_}{'type'} eq "obs" || $S{$_}{'type'} eq "just_virk" ) {
        $lastvirkkey = $_;
        last;
    }
}

print Dumper( \%S ) if $debug;

# v16
# check if there are gaps between observation longer than 5 hours. In that case will need to power off - power on receivers and heterodyne

my $time_of_prev_stop =
  $S{$firstobskey}{'stop'};    # stop time of previous observation
my %receiver_poweron = ()
  ; # hash with keys like ones in the %S hash. If key exists here then BEFORE this observation receivers should be powered on
my %receiver_poweroff = ()
  ; # hash with keys like ones in the %S hash. If key exists here then AFTER(not checked yet) this observation receivers should be powered off

# my @rec2poweroff

foreach ( sort keys %S ) {

    # skip non-observational stuff
    if (   $S{$_}{'type'} ne "obs"
        && $S{$_}{'type'} ne "just"
        && $S{$_}{'type'} ne "just_virk" )
    {
        next;
    }

    # skip first
    if ( abs( $_ - $firstobskey ) < 1 ) {
        $time_of_prev_stop = $S{$_}{'stop'};
        next;
    }

    # find all period of > 5 hours between observations
    if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just"
        || $S{$_}{'type'} eq "just_virk" )
    {
        my $time_of_this_start = $S{$_}{'start'};
        if ( $time_of_this_start - $time_of_prev_stop >= 5 * 3600 ) {
            $receiver_poweroff{$_} = 'all';
            $receiver_poweron{$_}  = 'all';
        }
    }
    $time_of_prev_stop = $S{$_}{'stop'};
}

# my @rec_periods = ($firstobskey, sort keys %receiver_poweroff, $S{$lastobskey}{'stop'});
my @rec_periods =
  ( $firstobskey, sort keys %receiver_poweroff, $global_stop_sec );

@rec_periods = uniq(@rec_periods);
print "RECEIVER periods:\n";
my $period = 1;
for ( my $i = 1 ; $i < scalar @rec_periods ; $i++ ) {
    my @bands_inthisperiod = ();
    print "Period $period\n";
    $period++;

    foreach ( sort keys %S ) {
        if (   $S{$_}{'start'} < $rec_periods[ $i - 1 ]
            or $S{$_}{'stop'} > $rec_periods[$i] )
        {
            next;
        }    # skip observations not from this period.
        if (   $S{$_}{'type'} ne "obs"
            && $S{$_}{'type'} ne "just"
            && $S{$_}{'type'} ne "just_virk" )
        {
            next;
        }

        # 	print ".\n";

        # 	print "bands num = ",$S{$_}{'bands_num'},"\n";

        for my $i ( 0 .. $S{$_}{'bands_num'} ) {
            push @bands_inthisperiod,
              substr( $S{$_}{ 'bands' . $i }, 0, 1 ) . "1";
            push @bands_inthisperiod,
              substr( $S{$_}{ 'bands' . $i }, 1, 1 ) . "2";

            if ( $S{$_}{'type'} eq 'just' )
            {    # 4 channels totally available for justirovka
                push @bands_inthisperiod,
                  substr( $S{$_}{ 'bands' . $i }, 0, 1 ) . "2"
                  if substr( $S{$_}{ 'bands' . $i }, 0, 1 ) !~ m/c/i;
                push @bands_inthisperiod,
                  substr( $S{$_}{ 'bands' . $i }, 1, 1 ) . "1"
                  if substr( $S{$_}{ 'bands' . $i }, 1, 1 ) !~ m/c/i;
            }
        }
        @bands_inthisperiod = uniq(@bands_inthisperiod);
    }

    #     	print "*"x50,$S{$_}{'obscode'},"\n";
    # 	print $S{$_}{'type'},"\n";
    # 	print Dumper(@bands_inthisperiod);

    print print_time( $rec_periods[ $i - 1 ] ), " -- ",
      print_time( $rec_periods[$i] ), "\t BANDS = ", @bands_inthisperiod, "\n";

    $receiver_poweron{ $rec_periods[ $i - 1 ] } = \@bands_inthisperiod;
    $receiver_poweroff{ $rec_periods[$i] } = \@bands_inthisperiod;

}

# print Dumper(\%receiver_poweron),"\n";

print "POWER ON rec:\n";
foreach ( sort keys %receiver_poweron ) {
    print "in advance before ", print_time($_), " power on ",
      join( " ", @{ $receiver_poweron{$_} } ), "\n";
}

print "POWER OFF rec:\n";
foreach ( sort keys %receiver_poweroff ) {
    print "after ", print_time($_), " power off ",
      join( " ", @{ $receiver_poweroff{$_} } ), "\n";
}

################################################################################################

print "Time to start = ", sprintf( "%.1f hours\n", $time_to_start / 3600 );
print "Time to stop = ",  sprintf( "%.1f hours\n", $time_to_stop / 3600 );

if ( $time_to_start > 7200 ) {
    print "Enough time to warm up\n";
}
else {
    print "Little time to warm up\n";
}

# 3. determine receivers to be powered on and power them on.

print "Determine recevers to be powered on\n";

my @allbands    = "";
my @start_times = ();
my @stop_times  = ();

foreach ( sort keys %S ) {
    if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just"
        || $S{$_}{'type'} eq "just_virk" )
    {

        push @start_times, $S{$_}{'start'};
        push @stop_times,  $S{$_}{'stop'};

        for my $i ( 0 .. $S{$_}{'bands_num'} ) {
            push @allbands, substr( $S{$_}{ 'bands' . $i }, 0, 1 ) . "1";
            push @allbands, substr( $S{$_}{ 'bands' . $i }, 1, 1 ) . "2";
            if ( $S{$_}{'type'} eq 'just' )
            {    # 4 channels totally available for justirovka
                push @allbands, substr( $S{$_}{ 'bands' . $i }, 0, 1 ) . "2"
                  if substr( $S{$_}{ 'bands' . $i }, 0, 1 ) !~ m/c/i;
                push @allbands, substr( $S{$_}{ 'bands' . $i }, 1, 1 ) . "1";
            }
        }
    }
}
@start_times = sort { $a <=> $b }
  @start_times;    # this 2 shouldn't be reasonable if everything is ok
@stop_times = sort { $a <=> $b }
  @stop_times;     # this 2 shouldn't be reasonable if everything is ok

print "All bands = ", @allbands, "\n" if $debug;
our @uniq_allbands = uniq(@allbands);
print "All unique bands = ", join( " ", @uniq_allbands ), "\n" if $debug;
my $use_k1 = 0;
my $use_k2 = 0;

foreach my $i (@uniq_allbands) {
    if ( $i =~ m/k1/i ) { $use_k1 = 1; }
    if ( $i =~ m/k2/i ) { $use_k2 = 1; }
}

# don't want to power on 1.35 cm receiver twice

my @uniq_to_poweron = @uniq_allbands;

if ( $use_k1 == 1 and $use_k2 == 1 ) {
    for my $i ( 0 .. $#uniq_to_poweron ) {
        if ( $uniq_to_poweron[$i] =~ m/k1/i ) {
            splice @uniq_to_poweron, $i, 1;
            last;
        }
    }
}

# print Dumper(\@uniq_to_poweron),"\n";

# v16 +
# 1. determine which receivers to power on in this cyclogramm (@uniq_to_poweron)
# 2. for each receiver determine periods of activity
# 3. if for a given rec a gap between activities is longer then 5 h, power it off.
# 4. power on in advance, when required
# 4* avoid rec power on/power off during observations

# all keys in a cyclo
my @keys = ();
foreach ( sort keys %S ) {
    if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just_virk"
        || $S{$_}{'type'} eq "just" )
    {
        push @keys, $_;
    }
}
my @cmd = ();
@keys = sort { $a <=> $b } @keys;

my %all_rec_periods;

# print Dumper(\@keys),"\n";
# print Dumper(\%S),"\n";

print "uniq allbands\n";
print Dumper( \@uniq_allbands ), "\n";

# get periods for every rec
foreach my $rec (@uniq_allbands) {
    my @array = ();    # keys of observations where this rec is used
    for ( my $i = 0 ; $i < scalar @keys ; $i++ ) {

        # 	print $rec,"\t", $S{$keys[$i]}{'bands'},"\n";;

        if ( $S{ $keys[$i] }{'type'} eq 'just' ) {    # power on both channels
            if (                
                (lc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) ) eq 'c'
                and $rec =~ m/c1/i)
                or (lc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) ) eq 'c'
                and $rec =~ m/c2/i)
                or $rec !~ m/c\d/i and (
                    lc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) ) eq
                    lc( substr( $rec,                     0, 1 ) )
                    or lc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) ) eq
                    lc( substr( $rec, 0, 1 ) )
                 )
                )
            {
                push @array, $keys[$i];
            }
        }
        else {
            if ( $rec =~ m/1/
                and lc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) ) eq
                lc( substr( $rec, 0, 1 ) ) )
            {
                push @array, $keys[$i];
            }
            if ( $rec =~ m/2/
                and lc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) ) eq
                lc( substr( $rec, 0, 1 ) ) )
            {
                push @array, $keys[$i];
            }
        }
    }
    @array = sort { $a <=> $b } @array;
    $all_rec_periods{$rec} = \@array;
}

print Dumper( \%all_rec_periods ), "\n";


my %all_rec_poweron
  ; # keys of observation BEFORE which rec should be powered on. Primary key - rec. Value - array of %S keys( == start times)
my %all_rec_poweroff
  ; # keys of observation AFTER which rec should be powered off. Primary key - rec. Value - array of %S keys( == start times)

# find gaps longer than 5 hours for each rec used
# loop over receivers
foreach ( keys %all_rec_periods ) {

    my @array_on;     # array of power on keys
    my @array_off;    # array of power off keys

    if ( scalar @{ $all_rec_periods{$_} } == 0 ) {
        die "Zero time usage of receiver. Weirdest thing. Bye.\n";
    }
    elsif ( scalar @{ $all_rec_periods{$_} } == 1 )
    {    # if only 1 observation: power on before, power off after. Simple.
        push @array_on,  ${ $all_rec_periods{$_} }[0];
        push @array_off, ${ $all_rec_periods{$_} }[0];
    }
    else {
        #     print $_,"\t";
        for ( my $i = 1 ; $i < scalar @{ $all_rec_periods{$_} } ; $i++ ) {

            if (
                (
                    $S{ ${ $all_rec_periods{$_} }[$i] }{'start'} -
                    $S{ ${ $all_rec_periods{$_} }[ $i - 1 ] }{'stop'}
                ) >= 5 * 3600
              )
            { # if a gap between start of this obs and stop of previos with this rec is longer than 5hours
                 # if found than $i-th is pushed to poweron, $i-1 th  -- to poweroffs

                print "gap between ",
                  $S{ ${ $all_rec_periods{$_} }[$i] }{'obscode'}, "  and  ",
                  $S{ ${ $all_rec_periods{$_} }[ $i - 1 ] }{'obscode'}, " is ",
                  ( $S{ ${ $all_rec_periods{$_} }[$i] }{'start'} -
                      $S{ ${ $all_rec_periods{$_} }[ $i - 1 ] }{'stop'} ) /
                  3600, " hours\n";

                push @array_on, $S{ ${ $all_rec_periods{$_} }[$i] }{'start'};
                push @array_off,                  $S{ ${ $all_rec_periods{$_} }[ $i - 1 ] }{'start'};

            } elsif ($S{ ${ $all_rec_periods{$_} }[$i] }{'type'} eq 'just' and
                     $S{ ${ $all_rec_periods{$_} }[$i] }{'bands'} =~ m/.c/i and
                     $_ =~ m/c/i) {
                     
					push @array_off,                  $S{ ${ $all_rec_periods{$_} }[ $i - 1 ] }{'start'};
            }
            # special case of LL->CL observations. 
                     # CASE: both L-band channels are powered off afler an LL observation
                     # then L2 should be powered ON for a subsequent CL observation
			elsif(uc($S{ ${ $all_rec_periods{$_} }[ $i - 1 ] }{'bands'}) eq 'LL' and  uc($S{ ${ $all_rec_periods{$_} }[$i] }{'bands'}) eq 'CL')
                     {
						push @array_on, $S{ ${ $all_rec_periods{$_} }[$i] }{'start'};
                     }

            #     print ${$all_rec_periods{$_}}[$i],"\t";
        }

        # 	print "\n";

        # add first obs with this rec to poweron and last one to poweroff
        unshift @array_on, $S{ ${ $all_rec_periods{$_} }[0] }{'start'};
        push @array_off, $S{ ${ $all_rec_periods{$_} }[-1] }{'start'};
    }

    @array_on  = sort { $a <=> $b } @array_on;
    @array_off = sort { $a <=> $b } @array_off;

    $all_rec_poweron{$_}  = \@array_on;
    $all_rec_poweroff{$_} = \@array_off;

}

# print

foreach ( keys %all_rec_periods ) {
    print "rec $_\n";
    print " POWER ON at\n";
    foreach my $tt ( @{ $all_rec_poweron{$_} } ) {
        print print_time($tt), "\t";
    }
    print "\n";
    print "POWER OFF at \n";
    foreach my $tt ( @{ $all_rec_poweroff{$_} } ) {
        print print_time( $S{$tt}{'stop'} ), "\t";
    }
    print "\n\n";
}

# rec to be powered on for the  first obs
my @poweron_first;
foreach ( keys %all_rec_poweron ) {
    print $_, "\n";
    if ( $all_rec_poweron{$_}[0] == $keys[0] ) {
        push @poweron_first, $_;
    }
}

print "POWERON FIRST = ", join( " ", @poweron_first ), "\n";

# 4. insert GSH(calibration) before and after each observation. For some justirovka variants insert them in proper places.

print "Starting calibration (GSH)\n";

my $dozu  = 0;
my $dogsh = 1;

foreach ( sort keys %S ) {

    my @keys = sort keys %S;
    my ( $prev, $this, $next ) = ( 0, $_, 1e9 );
    my $prevstop = 0;
    my $thisstop = $S{$_}{'stop'};
    for ( my $i = 1 ; $i < $#keys ; $i++ ) {
        if ( $keys[$i] == $this ) {
            for my $back ( 1 .. 5 ) {
                if (   $S{ $keys[ $i - $back ] }{'type'} eq "obs"
                    or $S{ $keys[ $i - $back ] }{'type'} eq "just_virk" )
                {

                    if ( ( $i - $back ) <= 0 ) {
                        $prev     = 0;
                        $prevstop = 0;
                        last;
                    }
                    $prev     = $keys[ $i - $back ];
                    $prevstop = $S{ $keys[ $i - $back ] }{'stop'};
                    last;
                }
            }
            for my $forward ( 1 .. 5 ) {
                if (   $S{ $keys[ $i + $forward ] }{'type'} eq "obs"
                    or $S{ $keys[ $i - $forward ] }{'type'} eq "just_virk" )
                {

                    if ( ( $i + $forward ) > $#keys ) {
                        $next = 1e9;
                        last;
                    }
                    $next = $keys[ $i + $forward ];
                    last;

                }
            }
        }
    }

## kostyli
    $S{$_}{'bands'} =~ s/[0-9\-\+]//g;

    # calibration BEFORE observations and VIRK justirovkas
    if ( $S{$_}{'type'} eq "obs" || $S{$_}{'type'} eq "just_virk" ) {

        # for special "home" justirovkas, var0
        if ( $S{$_}{'type'} eq "just_virk" and $S{$_}{'var'} == 0 ) {

            if (
                $S{$_}{'power'} == 40
                and ( $_ + 0 == $firstvirkkey + 0
                    or ( 0 + $this - $prevstop ) > 900 )
              )
            {
                #$t-=$dt;
                $t = $S{$_}{'beginscan'};

                print "POWER = 40 ON at ", print_time($t), "\n";
                my @cmd =
                  "1\t" . $dt . "\t3112\t// otkl. regim 4W (power = 40W)";

                # added deep in the night 04.07.2014
                print "FGSVCH on (different bands)\n";
                my @cmd1 = read_file(
                        uc( substr( $S{$_}{'bands'}, 0, 1 ) ) . "1/"
                      . lc( substr( $S{$_}{'bands'}, 0, 1 ) )
                      . "1_fgsvch_on" );
                my @cmd2 = read_file(
                        uc( substr( $S{$_}{'bands'}, 1, 1 ) ) . "2/"
                      . lc( substr( $S{$_}{'bands'}, 1, 1 ) )
                      . "2_fgsvch_on" );

                #unshift @cmd,@cmd2;
                #unshift @cmd,@cmd1;
                push @cmd, @cmd1;

                # v18
                # 1.35 GSH 7/8 dB after vosstanovl 1.35.

                if ( substr( $S{$_}{'bands'}, 0, 1 ) =~ m/k/i ) {
                    push @cmd,
                        "1\t"
                      . $dt
                      . "\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                }

                push @cmd, @cmd2;
                if (    substr( $S{$_}{'bands'}, 1, 1 ) =~ m/k/i
                    and substr( $S{$_}{'bands'}, 0, 1 ) !~ m/k/i )
                {
                    push @cmd,
                        "1\t"
                      . $dt
                      . "\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                }
                insert_block( \$t, \@cmd, "-", 1 );
            }

            my @cmd =
              read_file( "GSH_NEW/"
                  . lc( substr( $S{$_}{'bands'}, 0, 1 ) )
                  . lc( substr( $S{$_}{'bands'}, 1, 1 ) )
                  . "_var0" );

#my @cmd = read_file("GSH_NEW/".lc(substr($S{$_}{'bands'},0,1)).lc(substr($S{$_}{'bands'},1,1))."_var0_c2");

            #$t=$S{$_}{'start'}+$dt;
            $t = $S{$_}{'beginscan'} + 2 * 60 + $dt;

            print Dumper(@cmd);
            $GSHB{ $S{$_}{'start'} } = $t;
            my @rep_cmd = repeat_block( \@cmd, 2 );

            # set power 40 if needed

            #my $n = int(($S{$_}{'stop'} - $S{$_}{'start'})/7/60);
            my $n = int( ( $S{$_}{'endscan'} - $S{$_}{'beginscan'} ) / 7 / 60 );

            for my $i ( 0 .. $n ) {

                #$t+=$i*7*60;	# every 7 min
                $t -= 20;

                insert_block( \$t, \@rep_cmd, "+", 1 );
            }

            print
"\n\n#######################################################################
			this power  = $S{$_}{'power'}
			next = $next
			thisstop = $thisstop
			next power =  $S{$next}{'power'}
			\n\n";

            if ( $S{$_}{'power'} == 40
                and ( ( $next - $thisstop ) > 900 or $S{$next}{'power'} == 4 ) )
            {

                $t = $S{$_}{'stop'} + 10;

                # 				$t=$S{$_}{'endscan'};
                print "Power 40 OFF at ", print_time($t), "\n";
                my @cmd =
                  "1\t" . $dt . "\t3111\t// vkl. regim 4W (power =  4W)";
                insert_block( \$t, \@cmd, "+", 1 );
            }
            $GSHA{ $S{$_}{'stop'} } = $S{$_}{'stop'};

            next;
        }

        
        ##############################################################
        # GSH
        print "Calibration before ", $S{$_}{'obscode'}, " start time ",
          print_time( $S{$_}{'start'} ), "\n";

        # GSH BEFORE
        my @cmd     = ();
        my @rep_cmd = ();
        my @cmd1    = ();

        my ( $doshort_bef, $doshort_aft ) = ( 0, 0 );

# chech if there is too little time for the full GSH calibation. Then insert only GSH_low.
        if (
            (
                abs( $S{$this}{'ts_bef'} + 0 ) < 2
                and ( $this - $prevstop ) < 600
            )
          )
        {
            $doshort_bef = 1;
        }

        if ( ( $S{$this}{'ts_aft'} + 0 < 2 and ( $next - $thisstop ) < 600 ) ) {
            $doshort_aft = 1;
        }
        if ( $global_stop_sec - $S{$this}{'stop'} < 600 ) {
            $doshort_aft = 1;
        }

        print "DOSHORT = ($doshort_bef, $doshort_aft)   ts_mode = ",$S{$this}{'ts_mode'}," \n";

        # if coherent mode for GRAVITATIONAL sessions only
        if ( $S{$_}{'ts_mode'} =~ m/ch/i  and $S{$_}{'obscode'} =~ m/(?:puts|gbts|grts|raks19)/i) {

            # Added on 13-04-2015

            push @cmd, "1\t" . $dt . "\t3115\t// vkl Cogerent";
            push @cmd, "1\t" . $dt . "\t3212,01010814\t// Razreshenie otkl.";
            push @cmd, "1\t" . $dt . "\t3212,050466A1\t// otkl. 15MHz";
            push @cmd, "1\t" . $dt . "\t3212,050324DB\t// vkl. 5MHz na BVSCh-2";
            push @cmd, "1\t" . $dt . "\t3240,0000001A\t// Rabota ot BVSCh-2.";
            push @cmd, "1\t" . $dt . "\t3220,00002065\t// \"Test-2\",  72 Mbod, USTM-ON";
            @rep_cmd = repeat_block( \@cmd, 2 );

            $t = $S{$_}{'start'} - 600;
        }
#         # for VLBI sessions
#         elsif ($S{$_}{'ts_mode'} =~ m/ch/i  and $S{$_}{'obscode'} !~ m/(?:puts|grts|gbts|raks19)/i){
#         	push @cmd, "1\t" . $dt . "\t3115\t// vkl Cogerent";
# 			push @cmd, "1\t" . $dt . "\t3211,01010814\t// Razreshenie otkl.";
# 			push @cmd, "1\t" . $dt . "\t3211,050466A1\t// otkl. 15MHz";
# 			@rep_cmd = repeat_block( \@cmd, 2 );
# 			
# 			print "COHERENT. BLOCK DUR = ",&block_duration( \@rep_cmd )," sec\n";
# 			
# 			
# 			$t = $S{$_}{'start'} - &block_duration( \@rep_cmd );
#         }

# 		unless($S{$_}{'obscode'} =~ m/(?:puts|gbts)/i   and  $S{$_}{'ts_mode'} !~ m/ch/i){


		# here should go all VLBI sessions incl. HM, RB, CH modes
        else {
        
			
            if (!$doshort_bef ) {

				if(!$interactive){
					if ( $S{$_}{'bands'} =~ m/k/i ) {
						push @cmd,
						"1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
						push @cmd,
							"1\t"
						. ( 70 - $dt )
						. "\t3230,3F000000\t// otkl. get. 1.35";
					}
					else {
						push @cmd, "1\t70\t3240,0000009E\t// otkl.kanalov FGSVCH";
					}
				}

                if (
                    substr( $S{$_}{'bands'}, 0, 1 ) eq
                    substr( $S{$_}{'bands'}, 1, 1 ) )
                {
                    print "FGSVCH on (2 same bands)\n";
                    my @cmd1 = read_file(
                            uc( substr( $S{$_}{'bands'}, 0, 1 ) ) . "1/"
                          . lc( substr( $S{$_}{'bands'}, 0, 1 ) )
                          . "1_fgsvch_on" );
                    push @cmd, @cmd1;
                    if ( substr( $S{$_}{'bands'}, 0, 1 ) =~ m/k/i ) {

# v19					push @cmd, "1\t".$dt."\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                    }
                }
                else {
                    print "FGSVCH on (different bands)\n";
                    my @cmd1 = read_file(
                            uc( substr( $S{$_}{'bands'}, 0, 1 ) ) . "1/"
                          . lc( substr( $S{$_}{'bands'}, 0, 1 ) )
                          . "1_fgsvch_on" );
                    my @cmd2 = read_file(
                            uc( substr( $S{$_}{'bands'}, 1, 1 ) ) . "2/"
                          . lc( substr( $S{$_}{'bands'}, 1, 1 ) )
                          . "2_fgsvch_on" );
                    push @cmd, @cmd1;
                    if ( substr( $S{$_}{'bands'}, 0, 1 ) =~ m/k/i ) {

# v19					push @cmd, "1\t".$dt."\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                    }

                    push @cmd, @cmd2;
                    if (    substr( $S{$_}{'bands'}, 1, 1 ) =~ m/k/i
                        and substr( $S{$_}{'bands'}, 0, 1 ) !~ m/k/i )
                    {
# v19					push @cmd, "1\t".$dt."\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                    }

                }
            }
            my @cmd1 = read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh" );
            
            
            # 2017-12-20 (MML): try to add here different UKS for 1cm-receiver sub-bands. Uses this sub:
            
            # sub to generate CONTROL WORD (UKS) for 1.35 receivers
			# INPUT: channel 1 ([k|f]number), channel 2 (i.e. f0, k0-2 etc), attenuator 1 in dB, att 2, time to wait after UKS (basically this is already beyond the UKS itself), gsh{1} = off|high|low (turn different GSH on/off),  gsh{2} = off|high|low  
			# OUTPUT: UKS with comment as a single line
			#	sub uks()

#             # Currently supports ONLY KK observations.
#             # further efforts are required to add CK, KL support, or different subbands for polarisations
            if($S{$_}{'bands'} =~ m/kk/i and 
            (
				($S{$_}{'fmode'} =~ m/f2/i and $S{$_}{'cfreq1'} != 22228) or 
				($S{$_}{'fmode'} =~ m/f3/i and $S{$_}{'cfreq1'} != 22236))
			){
# 				
# 				# Initially a special naming scheme for PRM value was assigned. But to the moment nobody uses it. Hence, observations performed at any 1cm sub-band contain PRM=KK. 
# 				# Only CFREQ+FMODE values could help to distinguish sub-bands.
# 				# Current code only handles CFREQ=22196, FMODE=F2/F2, which is used for rags34a observations.
# 				# This corresponds to F0-1.
				
				# to @cmd: otkl --> GSh visokiy --> otkl --> GSh nizkiy --> otkl
# 				my $str=uks('k0','k0',7,8,35,1=>'off',2=>'high');

 				@cmd1=();
				if($S{$_}{'cfreq1'} == 22196){
					my $gsh_off1 = uks('f0-1','f0-1',7,8,5,1=>'off',2=>'off');
					my $gsh_off2 = uks('f0-1','f0-1',7,8,35,1=>'off',2=>'off');
					my $gsh_v_on = uks('f0-1','f0-1',7,8,45,1=>'high',2=>'off');
					my $gsh_n_on = uks('f0-1','f0-1',7,8,45,1=>'low',2=>'off');
					push @cmd1, ($gsh_off1,$gsh_v_on,$gsh_off2,$gsh_off1,$gsh_n_on,$gsh_off2);
				}             
				else{
					die "K-band frequency is not standard. But this is not yet supported. LINE = ".__LINE__."\n";
				}
            }
            
            print Dumper(\@cmd1) if $debug;
            
            push @cmd, @cmd1;

            #		my @AAAA = reorder_gsh($S{$_}{'bands'}, @cmd1);
            #		print "\n\n\nCMD1 = \n",join("\n",@cmd1),"\n";
            #		print "AAAA = \n",join("\n",@AAAA),"\n\n\n\n";

            @rep_cmd = repeat_block( \@cmd, 2 );

            if ( $S{$_}{'ts_bef'} <= 0
                && block_duration( \@rep_cmd ) <
                ( abs( $S{$_}{'ts_bef'} ) - 3 ) * 60 )
            {    # if fits well

                print "DEBUG: ts_bef=", $S{$_}{'ts_bef'},
                  " GSH before block duration = ", block_duration( \@rep_cmd ),
                  "\n"
                  if $debug;

                print "fits well\n" if $debug;
                $t = $S{$_}{'start'} - &block_duration( \@rep_cmd ) - 5;
            }
            else {
                my $ans;
                if ($interactive) {
                    print "block duration is ", &block_duration( \@rep_cmd ),
                      "\n";
                    print
"Do you want to perform calibration before this obervation[y/n]";
                    $ans = <STDIN>;
                }
                else {
                    $ans = "y";

                }

                if ( $ans =~ m/n/i ) { $dozu = 0; $dogsh = 0; }
                elsif ( $ans =~ m/y/i ) {

                    if ($interactive) {
                        print "Duration of calibration is ",
                          &block_duration( \@rep_cmd ), " sec\n";
                        print
"Enter calibration time offset in SECONDS (with + or -):\n";
                        $ans = int(<STDIN>);
                    }

                    else {
                        $ans = -( &block_duration( \@rep_cmd ) + 20 );
                        if ( $S{$_}{'ts_bef'} + 0 == 0 ) {
                            if ( $S{$_}{'bands'} =~ m/kk/i ) {
                                $ans += 110;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/ll|pp|cc/i ) {
                                $ans += 110;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/([^k])[^\1k]/i )
                            { # I believe this should correspond to lc,cl,lp,pl,cp,pc
                                $ans += 110;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/[^k]k$/i ) {
                                $ans += 110;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/^k[^k]/i ) {
                                $ans += 110;
                            }
                            print "Found -0. Shifting GSH_before\n" if $debug;
                        }
                    }
                    $dozu  = 1;
                    $dogsh = 1;
                    print "t1=", print_time( $S{$_}{'start'} ), "\n";
                    $t = $S{$_}{'start'} + $ans;
                    print "t2=", print_time($t), "\n";
                }
            }

            if ($dozu) {
                print "Write to ZU\n";

                unshift @rep_cmd, "1\t" . $dt . "\t866-34\t// vkl zapis ZU";
                push @rep_cmd, "1\t" . $dt . "\t808\t// otkl zapis ZU";
                $t -= $dt;
            }

            if ($doshort_bef) {
                $t                       = $S{$_}{'start'} - 15;
                $GSHB{ $S{$_}{'start'} } = $t;
                @cmd                     = read_file(
                    "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh_short" );
                @rep_cmd = repeat_block( \@cmd, 2 );
            }
        }

        $GSHB{ $S{$_}{'start'} } = $t if $dogsh;    # GHS before start time
        $GSHB{ $S{$_}{'start'} } = $S{$_}{'start'} unless $dogsh;

        ##############################################################
        # POWER 40 ON
        # compare @rep_cmd duration with ts_bef

        print " before power 40 on:
		dogdh = $dogsh
		";
        print $S{$_}{'start'} - &block_duration( \@rep_cmd ), " <= ",
          $S{$_}{'start'} + $S{$_}{'ts_bef'} * 60 - 10, "\n";

  # if		max possible time of GSH_before start   <   time of power 4/40 switching
        if ( $dogsh
            and ( $S{$_}{'start'} - &block_duration( \@rep_cmd ) ) <=
            ( $S{$_}{'start'} + $S{$_}{'ts_bef'} * 60 - 10 ) )
        {

            if ( $S{$_}{'power'} + 0 == 40 ) {

                print "here I am!!!!!!!!!!!1\n";

#$t=$S{$_}{'start'} - &block_duration(\@rep_cmd) - $dt;		# commented to make all efforts of moving -0 GSH useful
                $t -= $dt;

                if (   $S{$prev}{'power'} + 0 == 4
                    or ( $this - $prevstop ) > 900
                    or $this == $firstvirkkey )
                {

                    print "and here. OBscode = ", $S{$this}{'obscode'}, "\n";
                    print "POWER = 40 ON at ", print_time($t), "\n";
                    my @cmd =
                      "1\t" . $dt . "\t3112\t// otkl. regim 4W (power = 40W)";
                    unshift @rep_cmd, @cmd;
                }

                #$GSHB{$S{$_}{'start'}}= $t ;		# GHS before start time

                if ($dogsh) {
                    insert_block( \$t, \@rep_cmd, "-", 1 )
                      if $S{$_}{'ts_bef'} + 0 != 0;
                    insert_block( \$t, \@rep_cmd, "+", 1 )
                      if $S{$_}{'ts_bef'} + 0 == 0;
                }

                $GSHB{ $S{$_}{'start'} } = $t;    # GHS before start time
            }
            else {

                if ($dogsh) {
                    insert_block( \$t, \@rep_cmd, "-", 1 )
                      if $S{$_}{'ts_bef'} + 0 != 0;
                    insert_block( \$t, \@rep_cmd, "+", 1 )
                      if $S{$_}{'ts_bef'} + 0 == 0;
                }
                $GSHB{ $S{$_}{'start'} } = $t;    # GHS before start time

            }

        }
        elsif ( !$dogsh
            and ( $S{$_}{'start'} - &block_duration( \@rep_cmd ) ) <=
            ( $S{$_}{'start'} + $S{$_}{'ts_bef'} * 60 - 10 ) )
        {
            if ( $S{$_}{'power'} + 0 == 40
                and ( ( $this - $prevstop ) > 900 or $this == $firstvirkkey ) )
            {

                $t = $S{$_}{'start'} + $S{$_}{'ts_bef'} * 60 - 10;
                print "POWER = 40 ON at ", print_time($t), "\n";
                my @cmd =
                  "1\t" . $dt . "\t3112\t// otkl. regim 4W (power = 40W)";
                insert_block( \$t, \@cmd, "-", 1 );
            }
			$GSHB{ $S{$_}{'start'} } = $S{$_}{'start'};
        }
        else {
            print "finally got here\n";

            insert_block( \$t, \@rep_cmd, "-", 1 ) if $dogsh;
            print "this = $this   ",     print_time($this),     "\n";
            print "prev = $prevstop   ", print_time($prevstop), "\n";
            print $this- $prevstop, " seconds between observations\n";

            if ( $S{$_}{'power'} + 0 == 40
                and ( ( $this - $prevstop ) > 900 or $this == $firstvirkkey ) )
            {
                $t = $S{$_}{'start'} + $S{$_}{'ts_bef'} * 60 - 10;
                if ( $S{$prev}{'power'} + 0 == 4
                    or ( $this - $prevstop ) > 900 )
                {
                    print "POWER = 40 ON atatat ", print_time($t), "\n";
                    my @cmd =
                      "1\t" . $dt . "\t3112\t// otkl. regim 4W (power = 40W)";
                    insert_block( \$t, \@cmd, "-", 1 );
                }
				$GSHB{ $S{$_}{'start'} } = $S{$_}{'start'};
            }

        }

        $GSHB{ $S{$_}{'start'} } = $t;    # GHS before start time

        
        
        
        # CH and RB switch ON before calibration start time. Should work even in case of no GSH_BEF inserted (MML)
        if ($S{$_}{'ts_mode'} =~ m/ch/i  and $S{$_}{'obscode'} !~ m/(?:puts|grts|gbts|raks19)/i and
            $S{$S{$_}{'prev'}}{'ts_mode'} !~ m/ch/i){	# for interferometric observations
				my @cmd1=();
				push @cmd1, "1\t" . $dt . "\t3115\t// vkl Cogerent";
				push @cmd1, "1\t" . $dt . "\t3211,01010814\t// Razreshenie otkl.";
				push @cmd1, "1\t" . $dt . "\t3211,050466A1\t// otkl. 15MHz";
				my @rep_cmd1 = repeat_block( \@cmd1, 2 );
				$t =   $GSHB{ $S{$_}{'start'} };
				insert_block( \$t, \@rep_cmd1, "-", 1 );
				
		}
	
	
		if (   $S{$_}{'ts_mode'} =~ m/rb/i
			&& $S{$S{$_}{'prev'}}{'ts_mode'} !~ m/rb/i )
		{
			my @cmd1;
			push @cmd1,                  "1\t" . $dt . "\t3240,00000017   // Vkl 5MHz na BRSCh-2";
			push @cmd1,                  "1\t" . $dt . "\t3240,0000001A   // Work FGTCh ot BRSCh-2";
			my @rep_cmd1 = repeat_block( \@cmd1, 2 );
			$t =   $GSHB{ $S{$_}{'start'} };
			
			print "RB mode switch on; dogsh = $dogsh. t = ",print_time($t),"\n";
			
			
			# test insertion of the RB mode switch on. 
			my $test_time = simulate_insert_block(\$t, \@rep_cmd1, "-", 1 );
			print "RB mode switch on; dogsh = $dogsh. t = ",print_time($t),"\n";
			print "test_time = ",print_time($test_time),"\n";
			
			
			# if it puts RB switch on commands before the prev session stop, or before prev session GSH_after end, then change direction of search. 			
			my $rb_dir="-";
			if($test_time <= $S{$S{$_}{'prev'}}{'stop'}  or $test_time <= $GSHA{$S{$_}{'prev'}}) {$rb_dir="+";}
			
			
			insert_block( \$t, \@rep_cmd1, $rb_dir, 1 );
		}
        
                   
     
        
        
        print "---\n";

        # 		print Dumper(@rep_cmd);# if $debug;

        ##############################################################
        # POWER 40 OFF
        $dozu    = 0;
        $dogsh   = 1;
        @rep_cmd = @cmd = @cmd1 = ();

        print "this = $this   ",     print_time($this),     "\n";
        print "prev = $prevstop   ", print_time($prevstop), "\n";
        print "\n++++++++++++++++\n", $this - $prevstop,
          " seconds between observations\n";

        # if coherent mode for GRAVITATIONAL sessions
        if ( $S{$_}{'ts_mode'} =~ m/ch/i  and $S{$_}{'obscode'} =~ m/(?:puts|gbts|raks19)/i) {
            push @cmd, "1\t" . $dt . "\t3116\t// vkl. HM";
            push @cmd, "1\t" . $dt . "\t3115\t// vkl Cogerent";
            push @cmd, "1\t" . $dt . "\t3116\t// vkl. HM";

            # ADDDED 13-04-2015
            push @cmd, "1\t" . $dt . "\t3240,0000001B\t// Rabota ot VIRK-1";
            push @cmd, "1\t" . $dt . "\t3212,01010814\t// Razreshenie otkl.";
            push @cmd, "1\t" . $dt . "\t3212,05026314\t// otkl. 5MHz";
            push @cmd, "1\t" . $dt . "\t3220,000020B5\t//  \"Rabota\", 72 Mbod, USTM-ON, F3/F3";

            my @cmd1;
            push @cmd1, "1\t" . $dt . "\t3116\t// vkl. HM";
            push @cmd1, "1\t" . $dt . "\t3115\t// vkl Cogerent";
            push @cmd1, "1\t" . $dt . "\t3116\t// vkl. HM";
            push @cmd1, "1\t" . $dt . "\t3240,0000001B\t// Rabota ot VIRK-1";
            push @cmd1, "1\t" . $dt . "\t3212,01010814\t// Razreshenie otkl.";
            push @cmd1, "1\t" . $dt . "\t3212,05026314\t// otkl. 5MHz";
            push @cmd1, "1\t" . $dt . "\t3220,000020B5\t//  \"Rabota\", 72 Mbod, USTM-ON, F3/F3";

            @rep_cmd = repeat_block( \@cmd1, 2 );

            $t = $S{$_}{'stop'} + &block_duration( \@rep_cmd );
        }

        else {
            ######################################
            # GSH AFTER

            
            print "Calibration after ", $S{$_}{'obscode'}, " stop time ",
              print_time( $S{$_}{'stop'} ), "\n";

            @cmd1 = read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh" );

            # reorder GSH if +0
            if ( $S{$_}{'ts_aft'} == 0 ) {
                @cmd1 = reorder_gsh( $S{$_}{'bands'}, @cmd1 );
            }

            push @cmd, @cmd1;

            unless ($doshort_aft) {
#                         die "long GSH_AFT haha start time = ",print_time($_),"\n"   if($S{$_}{'obscode'}=~m/raks18bg/i);

                if ( $S{$_}{'bands'} =~ m/k/i ) {
                    push @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                    push @cmd,
                      "1\t" . $dt . "\t3230,3F000000\t// otkl. get. 1.35";
                }
                else {
                    push @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }
            }
            @rep_cmd = repeat_block( \@cmd, 2 );

            if ( &block_duration( \@rep_cmd ) <=
                ( abs( $S{$_}{'ts_aft'} ) ) * 60 )
            {    # if fits well

                print "DEBUG: ts_aft = ", $S{$_}{'ts_aft'} * 60,
                  "\n ts aft duration =  ", &block_duration( \@rep_cmd ), "\n"
                  if $debug;

                print "fits well\n" if $debug;
                $t = $S{$_}{'stop'};
            }
            else {
                my $ans;
                if ($interactive) {
                    print "block duration is ", &block_duration( \@rep_cmd ),
                      "\n";
                    print
"Do you want to perform calibration AFTER this obervation[y/n]";
                    $ans = <STDIN>;
                }
                else {
                    $ans = "y";
                }

                if ( $ans =~ m/n/i ) { $dozu = 0; $dogsh = 0; }
                elsif ( $ans =~ m/y/i ) {

                    if ($interactive) {
                        print "Duration of calibration is ",
                          &block_duration( \@rep_cmd ), " sec\n";
                        print
"Enter calibration time offset in SECONDS (with + or -):\n";
                        $ans = int(<STDIN>);
                    }
                    else {
                        $ans = 0;
                        if ( $S{$_}{'ts_aft'} == 0 ) {

                            if ( $S{$_}{'bands'} =~ m/kk/i ) {
                                $ans = -60;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/ll|pp|cc/i ) {
                                $ans = -60;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/([^k])[^\1k]/i )
                            { # I believe this should correspond to lc,cl,lp,pl,cp,pc
                                $ans = -80;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/[^k]k$/i ) {
                                $ans = -80;
                            }
                            elsif ( $S{$_}{'bands'} =~ m/^k[^k]/i ) {
                                $ans = -80;
                            }
                        }

                    }
                    $dozu  = 1;
                    $dogsh = 1;
                    $t     = $S{$_}{'stop'} + $ans;
                }
            }
            
            
            print "111111 GSH AFT time at this point is ", print_time($t),"\n";
            

            if ($dozu) {
                unshift @rep_cmd, "1\t" . $dt . "\t866-34\t// vkl zapis ZU";
                push @rep_cmd, "1\t" . $dt . "\t808\t// otkl zapis ZU";
            }

            if ( $doshort_aft and !$interactive ) {
                @cmd = read_file(
                    "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh_short" );
                @rep_cmd = repeat_block( \@cmd, 2 );
                $t = $S{$_}{'stop'} - &block_duration( \@rep_cmd ) + 5;    ### ??????????????????????? why minus???????????????

                # 		      $t=$S{$_}{'stop'} - 20;

                $GSHA{ $S{$_}{'stop'} } = $t;
            }

            print "222222 GSH AFT time at this point is ", print_time($t),"\n";

	
        }

        $GSHA{ $S{$_}{'stop'} } = $t + &block_duration( \@rep_cmd )     if $dogsh;    # GSH after stop time
        $GSHA{ $S{$_}{'stop'} } = $S{$_}{'stop'} unless $dogsh;

        
        insert_block( \$t, \@rep_cmd, "+", 1 ) if $dogsh;
        
        # two blocks below should be executed even if the GSH_AFT is not inserted. (MML)
        
         # coherent mode for VLBI observations
		if( $S{$_}{'ts_mode'} =~ m/ch/i  and $S{$_}{'obscode'} !~ m/(?:puts|gbts|grts|raks19)/i and
            $S{$S{$_}{'next'}}{'ts_mode'} !~ m/ch/i){
			my @cmd1=();
			push @cmd1, "1\t" . $dt . "\t3211,05052867		// vkl.15MHz na BVSCh-1";
			push @cmd1, "1\t" . $dt . "\t3116\t// vkl. HM";
            push @cmd1, "1\t" . $dt . "\t3115\t// vkl Cogerent";
            push @cmd1, "1\t" . $dt . "\t3116\t// vkl. HM";
			
			my @rep_cmd1 = repeat_block( \@cmd1, 2 );
# 			push @rep_cmd, @rep_cmd1;	# add to GSH_AFT commands
			
			$t = $S{$_}{'stop'};# + &block_duration( \@rep_cmd );
			
			insert_block( \$t, \@rep_cmd1, "+", 1 );
		}
		
		
		
		
		if (   $S{$_}{'ts_mode'} =~ m/rb/i
            && $S{$S{$_}{'next'}}{'ts_mode'} !~ m/rb/i )
        {
            my @cmd1;
            push @cmd1, "1\t" . $dt . "\t3240,00000013\t// Otkl 5MHz na BRSCh-2";
            push @cmd1, "1\t". $dt. "\t3240,0000001B\t// Work FGTCh s  \"VIRK-1\" (BVSCH-1,2)";
            my @rep_cmd1=();
            push @rep_cmd1, repeat_block( \@cmd1, 2 );
			insert_block( \$t, \@rep_cmd1, "+", 1 );

        }

                
        print
"\n\n#######################################################################
			this power  = $S{$_}{'power'}
			next = $next
			thisstop = $thisstop
			(next - thisstop) = ", $next - $thisstop, "
			next power =  $S{$next}{'power'}
			\n\n";

        unless ($interactive) {
            if (
                $S{$_}{'power'} == 40
                and (  ( ( $next - $thisstop ) > 900 )
                    or
                    ( ( $next - $thisstop ) < 900 and $S{$next}{'power'} == 4 )
                    or ( $this == $lastvirkkey ) )
              )
            {

                print "	i definetely must get here!!!!!!\n\n\n";

                $t = $S{$_}{'stop'} + $S{$_}{'ts_aft'} * 60 + 10;
                print "Power 40 OFF at ", print_time($t), "\n";
                my @cmd =
                  "1\t" . $dt . "\t3111\t// vkl. regim 4W (power =  4W)";

                insert_block( \$t, \@cmd, "+", 1 );
            }
        }

        if ($interactive) {
            if (
                $S{$_}{'power'} == 40
                and (  ( ( $next - $thisstop ) > 900 )
                    or
                    ( ( $next - $thisstop ) < 900 and $S{$next}{'power'} == 4 )
                    or ( $this == $lastvirkkey ) )
              )
            {

                #$t=$S{$_}{'stop'}+$S{$_}{'ts_aft'}*60+10;
                print "Power 40 OFF at ", print_time($t), "\n";
                my @cmd =
                  "1\t" . $dt . "\t3111\t// vkl. regim 4W (power =  4W)";

                insert_block( \$t, \@cmd, "+", 1 );
            }
        }

    }    # observation

    #####################################
    # justirovka
    if ( $S{$_}{'type'} eq "just" ) {

        #####################################
        # GSH before

        print "Calibration before JUSTIROVKA start time ",
          print_time( $S{$_}{'start'} ),     " beginscan ",
          print_time( $S{$_}{'beginscan'} ), "\n";
        my @ts = ();
        my @gsh_pattern;
        my $ans     = "";
        my @cmd     = ();
        my @rep_cmd = ();

        # TODO: remove var 0 from the next IF statement??
        if (   $S{$_}{'var'} == 0
            || $S{$_}{'var'} == 1
            || $S{$_}{'var'} == 2
            || $S{$_}{'var'} == 3
            || $S{$_}{'var'} == 4 )
        {
            $t = $S{$_}{'beginscan'};
            push @ts, $t;

            if (
                substr( $S{$_}{'bands'}, 0, 1 ) eq
                substr( $S{$_}{'bands'}, 1, 1 ) )
            {    # same bands

                my @cmd1 =
                  read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh_yust" );
                push @cmd, @cmd1;
                @cmd1 = read_file(
                        uc( substr( $S{$_}{'bands'}, 0, 1 ) ) . "1/"
                      . lc( substr( $S{$_}{'bands'}, 0, 1 ) )
                      . "1_fgsvch_on" );

                # v18
                # add command to the eng of the "fgsvch on" block
                if ( substr( $S{$_}{'bands'}, 0, 1 ) =~ m/k/i ) {
                    push @cmd1,
                        "1\t"
                      . $dt
                      . "\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                }
                unshift @cmd, @cmd1;
                if ( $S{$_}{'bands'} =~ m/k/i ) {
                    unshift @cmd,
                        "1\t"
                      . ( 70 - $dt )
                      . "\t3230,3F000000\t// otkl. get. 1.35";
                    unshift @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }
                else {
                    unshift @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }
            }
            else {    # different bands

                #
                my @cmd1 =
                  read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh_yust" );
                push @cmd, @cmd1;

                print "use GSH file : GSH_NEW/"
                  . lc( $S{$_}{'bands'} )
                  . "_gsh_yust\n"
                  if $debug;

                print "FGSVCH on (different bands) @ yust\n";

                @cmd1 = read_file(
                        uc( substr( $S{$_}{'bands'}, 0, 1 ) ) . "1/"
                      . lc( substr( $S{$_}{'bands'}, 0, 1 ) )
                      . "1_fgsvch_on" );

                # v18
                # add command to the eng of the "fgsvch on" block
                if ( substr( $S{$_}{'bands'}, 0, 1 ) =~ m/k/i ) {
                    push @cmd1,
                        "1\t"
                      . $dt
                      . "\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                }

                my @cmd2 = read_file(
                        uc( substr( $S{$_}{'bands'}, 1, 1 ) ) . "2/"
                      . lc( substr( $S{$_}{'bands'}, 1, 1 ) )
                      . "2_fgsvch_on" );    # v18
                    # add command to the eng of the "fgsvch on" block
                if (    substr( $S{$_}{'bands'}, 1, 1 ) =~ m/k/i
                    and substr( $S{$_}{'bands'}, 0, 1 ) !~ m/k/i )
                {
                    push @cmd2,
                        "1\t"
                      . $dt
                      . "\t3230,2443A000\t// 2F0 7/8dB GSH-otkl U 7.5mA";
                }

                unshift @cmd, @cmd2;
                unshift @cmd, @cmd1;
                if ( $S{$_}{'bands'} =~ m/k/i ) {
                    unshift @cmd,
                        "1\t"
                      . ( 70 - $dt )
                      . "\t3230,3F000000\t// otkl. get. 1.35";
                    unshift @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }
                else {
                    unshift @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }

            }

            my @rep_cmd = repeat_block( \@cmd, 2 );

            # 			unshift @rep_cmd,"1\t".$dt."\t866-34\t// vkl zapis ZU";
            $t = $t - &block_duration( \@rep_cmd );
            $GSHB{$_} = $t;
            insert_block( \$t, \@rep_cmd, "+", 1 );

            $t       = $S{$_}{'start'};
            my $tt       = $S{$_}{'beginscan'};
            @rep_cmd = ( "1\t" . $dt . "\t866-34\t// vkl zapis ZU" );
            insert_block( \$tt, \@rep_cmd, "-", 1 );

            my @cmd1;
            push @cmd1,                  "1\t" . $dt . "\t3240,00000017   // Vkl 5MHz na BRSCh-2";
            push @cmd1,                  "1\t" . $dt . "\t3240,0000001A   // Work FGTCh ot BRSCh-2";
            my @rep_cmd1 = repeat_block( \@cmd1, 2 );
            insert_block( \$t, \@rep_cmd1, "-", 1 );

            print "---\n";

        }
        elsif ( $S{$_}{'var'} =~ m/5\.[12]/ ) {
            print "Calibration before JUSTIROVKA start time ",
              print_time( $S{$_}{'start'} ),     " beginscan ",
              print_time( $S{$_}{'beginscan'} ), "\n";
            my $n;
            do {
                print "Please enter 4 values\n";
                print
"Enter space separated GSH pattern in seconds: offset(time of gsh on), gsh on duration, gsh off duration, number of repetitions:\n";
                my $t1 = <STDIN>;
                chomp($t1);
                $t1 =~ s/\s+$//;
                $t1 =~ s/^\s+//;

                @gsh_pattern = split /\s+/, $t1;
                $n = $#gsh_pattern + 1;

            } while ( $n != 4 );
            print "@gsh_pattern", "\n" if $debug;
            my %g = (
                'offset' => $gsh_pattern[0],
                'on'     => $gsh_pattern[1],
                'off'    => $gsh_pattern[2],
                'num'    => $gsh_pattern[3]
            );

            #			print "Number of repetitions = ",$g{'num'},"\n" if $debug;

            $t = $S{$_}{'beginscan'} + $g{'offset'};

            for my $i ( 1 .. $g{'num'} ) {
                push @ts, $t;
                print "$i: new GSH special time calculated: $t\t",
                  print_time($t), "\n"
                  if $debug;
                $t += $g{'on'} + $g{'off'};
            }

            if (
                substr( $S{$_}{'bands'}, 0, 1 ) eq
                substr( $S{$_}{'bands'}, 1, 1 ) )
            {    # same bands
                print "Trying to open file ",
                  "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh5\n"
                  if $debug;

                my @cmd1 =
                  read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh5" );
                push @cmd, @cmd1;
            }
            else {    # different bands
                my @cmd1 =
                  read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh5" );
                my @cmd2 = read_file(
                    "GSH_NEW/" . reverse( lc( $S{$_}{'bands'} ) ) . "_gsh5" );
                push @cmd, @cmd1;
                push @cmd, @cmd2;
            }

            @rep_cmd = repeat_block( \@cmd, 2 );

            $GSHB{$_} = $ts[0];
            foreach my $tau (@ts) {
                $t = $tau;
                print "special GSH at", print_time($t), "\n" if $debug;
                insert_block( \$t, \@rep_cmd, "+", 1 );
                print "Inserted special GSH at ", print_time($t), "\n";
            }
            $GSHA{ $S{$_}{'stop'} } = $ts[-1] + block_duration( \@rep_cmd );
            print "---\n";
        }    # var5.1

        #####################################
        # GSH after

        print "Calibration AFTER JUSTIROVKA start time ",
          print_time( $S{$_}{'stop'} ),    " end ",
          print_time( $S{$_}{'endscan'} ), "\n";
        my @ts = ();
        my @gsh_pattern;
        my $ans     = "";
        my @cmd     = ();
        my @rep_cmd = ();
        if (   $S{$_}{'var'} == 0
            || $S{$_}{'var'} == 1
            || $S{$_}{'var'} == 2
            || $S{$_}{'var'} == 3
            || $S{$_}{'var'} == 4 )
        {
            $t = $S{$_}{'endscan'};

            print "ENDSCAN =", print_time($t), "\n";

            push @ts, $t;

            if (
                substr( $S{$_}{'bands'}, 0, 1 ) eq
                substr( $S{$_}{'bands'}, 1, 1 ) )
            {    # same bands
                my @cmd1 =
                  read_file( "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh" );
                push @cmd, @cmd1;
                if ( $S{$_}{'bands'} =~ m/k/i ) {
                    push @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                    push @cmd,
                      "1\t" . $dt . "\t3230,3F000000\t// otkl. get. 1.35";
                }
                else {
                    push @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }
            }
            else {    # different bands

# 				my @cmd1=read_file("GSH_NEW/".lc($S{$_}{'bands'})."_gsh");
# 				print "  + read file "."GSH_NEW/".lc($S{$_}{'bands'})."_gsh\n";
#
# 				my @cmd2=read_file("GSH_NEW/".join("",reverse(split(//,lc($S{$_}{'bands'}))))."_gsh");
# 				print "  + read file "."GSH_NEW/".join("",reverse(split(//,lc($S{$_}{'bands'}))))."_gsh\n";
#
# 				push @cmd,@cmd1;
# 				push @cmd,@cmd2;
#

                my @cmd1 = read_file(
                    "GSH_NEW/" . lc( $S{$_}{'bands'} ) . "_gsh_yust_aft" );
                push @cmd, @cmd1;
                if ( $S{$_}{'bands'} =~ m/k/i ) {
                    push @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                    push @cmd,
                      "1\t" . $dt . "\t3230,3F000000\t// otkl. get. 1.35";
                }
                else {
                    push @cmd,
                      "1\t" . $dt . "\t3240,0000009E\t// otkl.kanalov FGSVCH";
                }

            }

            my @rep_cmd = repeat_block( \@cmd, 2 );

            # 			push @rep_cmd,"1\t".$dt."\t808\t// otkl zapis ZU";
            $GSHA{$_} = $t;

            insert_block( \$t, \@rep_cmd, "+", 1 );

            $t = $S{$_}{'stop'};
            my @rep_cmd = ( "1\t" . $dt . "\t808\t// otkl zapis ZU" );
            insert_block( \$t, \@rep_cmd, "+", 1 );


            my @cmd1;
            push @cmd1, "1\t" . $dt . "\t3240,00000013\t// Otkl 5MHz na BRSCh-2";
            push @cmd1, "1\t". $dt. "\t3240,0000001B\t// Work FGTCh s  \"VIRK-1\" (BVSCH-1,2)";
            my @rep_cmd1=();
            push @rep_cmd1, repeat_block( \@cmd1, 2 );
            insert_block( \$t, \@rep_cmd1, "+", 1 );

            print "---\n";

        }

    }    # justirovka
}


# my @mm = minmax( sort { $a <=> $b } keys %times );
# print "after GSH, before setting kluchi \n";
# print "to this moment min time is $mm[0] =  ", &print_time( $mm[0] ), "\n";
# die 57;









###############################################################
# 6. put kluchi on before, put kluchi off after

print "Start kluchi switching\n";

my @band1;
my @band2;
my @keys = ();
foreach ( sort keys %S ) {
    if ( $S{$_}{'type'} eq "obs" || $S{$_}{'type'} eq "just_virk" ) {
        push @keys, $_;
    }
	
	
	# should be omitted in case if $_ is the first observation in a cyclogramm, since no keys are actually swithed on
    if ( $S{$_}{'type'} eq "just" and $_ != $firstobskey ) {
    
    
		print  "LINE: ",__LINE__,"\n" if $debug;
		print "obscode = $S{$S{$_}{'next'}}{'obscode'}\n";
		print uc( substr( $S{ $S{$_}{'prev'} }{'bands'}, 0, 1 ) ) . "1/"
              . lc( substr( $S{ $S{$_}{'prev'} }{'bands'}, 0, 1 ) )
              . "1_kluchi_off\n";
		
        my @cmd1 = read_file(
            uc( substr( $S{ $S{$_}{'prev'} }{'bands'}, 0, 1 ) ) . "1/"
              . lc( substr( $S{ $S{$_}{'prev'} }{'bands'}, 0, 1 ) )
              . "1_kluchi_off",            'all'        );
        push @cmd, @cmd1;
		print  "LINE: ",__LINE__,"\n" if $debug;

        my @cmd1 = read_file(
            uc( substr( $S{ $S{$_}{'prev'} }{'bands'}, 1, 1 ) ) . "2/"
              . lc( substr( $S{ $S{$_}{'prev'} }{'bands'}, 1, 1 ) )
              . "2_kluchi_off",
            'all'
        );
        push @cmd, @cmd1;
        push @cmd, "1\t5\t3240,000000AE\t// Otkl. shiny (1-8) +27V SSVCh";
        push @cmd, "1\t5\t3240,000000AE\t//";
        my $t = $S{$_}{'start'};
        insert_block( \$t, \@cmd, "-", 1 );
    }
}

my @cmd = ();
@keys = sort { $a <=> $b } @keys;

for my $i ( 0 .. $#keys ) {

    my $st = $keys[$i];
    my $b1 = substr( $S{$st}{'bands'}, 0, 1 );
    my $b2 = substr( $S{$st}{'bands'}, 1, 1 );
    @cmd = ();

    my $do1 = 0;    # change ch 1
    my $do2 = 0;    # change ch 2

    if ( $S{$st}{'type'} eq "obs" || $S{$st}{'type'} eq "just_virk" ) {

        print "Kluchi on for ", $S{$st}{'obscode'}, " starting at ",
          print_time( $S{$st}{'start'} ), "\n";

        #print " I = ",$i, "\n";
        if ( $i == 0 ) {
            $do1 = 1;
            $do2 = 1;

            print "FILE=", uc($b1) . "1/" . lc($b1) . "1_kluchi_on", "\n"
              if $debug2;
            my @cmd1 =
              read_file( uc($b1) . "1/" . lc($b1) . "1_kluchi_on", 'all' )
              if $do1;    # if needed
            my @cmd2 =
              read_file( uc($b2) . "2/" . lc($b2) . "2_kluchi_on", 'all' )
              if $do2;
            push @cmd, @cmd1 if $do1;
            push @cmd, @cmd2 if $do2;
            push @cmd, "1\t5\t3240,000000AE\t// Otkl. shiny (1-8) +27V SSVCh"
              if ( $do1 or $do2 );
            push @cmd, "1\t5\t3240,000000AE" if ( $do1 or $do2 );
            my @rep_cmd = repeat_block( \@cmd, 1 );
            $t = $GSHB{$st} - &block_duration( \@rep_cmd );
            insert_block( \$t, \@rep_cmd, "-", 1 ) if ( $do1 or $do2 );

            @cmd = ();
        }

# bugfix 2014.11.19
# added '=' to the condition below. It will do keys changing BEFORE the last observation if needed.
        if ( $i > 0 and $i <= $#keys ) {

            if ( $b1 eq substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) )
            {    # if no switching needed for rec. 1
                print "don't need to switch kluchi for receiver 1\n";
                $do1 = 0;
            }

            if ( $b2 eq substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) )
            {    # if no switching needed for rec. 2
                print "don't need to switch kluchi for receiver 2\n";
                $do2 = 0;
            }

            # first switch off both
            if ( $b1 ne substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) )
            {    # neeed to switch off keys for b1
                $do1 = 1;

                # switch off
                print "FILE=",
                    uc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) ) . "1/"
                  . lc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) )
                  . "1_kluchi_off", "\n"
                  if $debug2;
                my @cmd1 = read_file(
                    uc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) ) . "1/"
                      . lc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) )
                      . "1_kluchi_off",
                    'all'
                );
                push @cmd, @cmd1;
            }

            if ( $b2 ne substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) )
            {    # neeed to switch off keys for b2
                $do2 = 1;

                # switch off
                print "FILE=",
                    uc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) ) . "2/"
                  . lc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) )
                  . "2_kluchi_off", "\n"
                  if $debug2;
                my @cmd1 = read_file(
                    uc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) ) . "2/"
                      . lc( substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) )
                      . "2_kluchi_off",
                    'all'
                );
                push @cmd, @cmd1;
            }

            push @cmd, "1\t5\t3240,000000AE\t// Otkl. shiny (1-8) +27V SSVCh"
              if ( $do1 or $do2 );
            push @cmd, "1\t5\t3240,000000AE\t//" if ( $do1 or $do2 );

            # and then switch ON both
            if ( $b1 ne substr( $S{ $keys[ $i - 1 ] }{'bands'}, 0, 1 ) )
            {    # neeed to switch ON keys for b1
                    # switch on
                print "FILE=", uc($b1) . "1/" . lc($b1) . "1_kluchi_on", "\n"
                  if $debug2;
                my @cmd1 =
                  read_file( uc($b1) . "1/" . lc($b1) . "1_kluchi_on", 'all' );
                push @cmd, @cmd1;
            }

            if ( $b2 ne substr( $S{ $keys[ $i - 1 ] }{'bands'}, 1, 1 ) )
            {       # neeed to switch ON keys for b2
                    # switch on
                print "FILE=", uc($b2) . "2/" . lc($b2) . "2_kluchi_on", "\n"
                  if $debug2;
                my @cmd1 =
                  read_file( uc($b2) . "2/" . lc($b2) . "2_kluchi_on", 'all' );
                push @cmd, @cmd1;
            }

            push @cmd, "1\t5\t3240,000000AE\t// Otkl. shiny (1-8) +27V SSVCh"
              if ( $do1 or $do2 );
            push @cmd, "1\t5\t3240,000000AE\t//" if ( $do1 or $do2 );
            $t = $GSHB{$st};
            insert_block( \$t, \@cmd, "-", 1 ) if ( $do1 or $do2 );
            @cmd = ();

        }

        if ( $i == $#keys ) {

            # bugfix: 12.11.13
            # replaces $i-1 with $i in indices of array
            # switch off
            print "FILE=",
                uc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) ) . "1/"
              . lc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) )
              . "1_kluchi_off", "\n"
              if $debug2;
            my @cmd1 = read_file(
                uc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) ) . "1/"
                  . lc( substr( $S{ $keys[$i] }{'bands'}, 0, 1 ) )
                  . "1_kluchi_off",
                'all'
            );
            push @cmd, @cmd1;

            # switch off
            print "FILE=",
                uc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) ) . "2/"
              . lc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) )
              . "2_kluchi_off", "\n"
              if $debug2;
            my @cmd1 = read_file(
                uc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) ) . "2/"
                  . lc( substr( $S{ $keys[$i] }{'bands'}, 1, 1 ) )
                  . "2_kluchi_off",
                'all'
            );
            push @cmd, @cmd1;

            push @cmd, "1\t5\t3240,000000AE\t// Otkl. shiny (1-8) +27V SSVCh";

            #			$t=$S{$st}{'stop'}+$S{$st}{'ts_aft'}*60;

            $t = $GSHA{ $S{$st}{'stop'} };

            insert_block( \$t, \@cmd, "+", 1 );
            @cmd = ();

        }

        print "Inserted KLUCHI OFF-ON at ", print_time($t), "\n";
        print "---\n";

    }
    elsif ( $S{$st}{'type'} eq "just" ) {

=c
			# switch off
			print "FILE=",uc(substr($S{$keys[$i-1]}{'bands'},0,1))."1/".lc(substr($S{$keys[$i-1]}{'bands'},0,1))."1_kluchi_off","\n" if $debug2;
			my @cmd1=read_file(uc(substr($S{$keys[$i-1]}{'bands'},0,1))."1/".lc(substr($S{$keys[$i-1]}{'bands'},0,1))."1_kluchi_off",'all');
			push @cmd,@cmd1;
			push @cmd, "1\t5\t3240,000000AE\t// Otkl. shiny (1-8) +27V SSVCh";

			$t=$GSHA{$S{$st}{'stop'}};
			insert_block(\$t,\@cmd,"+",1);
=cut

    }
}






# 6.5  Regim

print "Setting formatter regime\n";
print "Regime for the first observation will be set later\n";

my $regim_f = $default_regim;
if ( $S{ $keys[0] }{'fmode'} =~ m/f3\/f3/i ) {
    $regim_f = "f3/f3";
}
elsif ( $S{ $keys[0] }{'fmode'} =~ m/f2\/f2/i ) {
    $regim_f = "f2/f2";
}

for my $i ( 1 .. $#keys ) {

    my $st = $keys[$i];
    @cmd = ();

    if ( lc( $S{$st}{'fmode'} ) eq "f3/f3" && lc($regim_f) ne "f3/f3" )
    {    # we need f3/f3, but f2/f2 is switched on

        #switch to f3/f3
        push @cmd, "1\t10\t3240,0000009E\t// otkl.kanalov FGSVCH";
        push @cmd, "1\t10\t3240,00000021\t// otkl. get FGTCH";
        push @cmd, "1\t10\t3240,0000001F\t// vkl get. 258 MHz";
        push @cmd, "1\t10\t3220,000020B5\t// Work, 72 Mbod, F3/F3 USTM ON";
        push @cmd, "1\t30\t866-130\t// PFK-5, 32kbod";
        $regim_f = "f3/f3";

        #		$t=$S{$st}{'start'}+$S{$st}{'ts_bef'}*60;
        $t = $GSHB{$st};
        insert_block( \$t, \@cmd, "-", 2 );
        @cmd = ();
        print "Switch to f3/f3\tCode: ", $S{$st}{'obscode'}, " Start: ",
          &print_time($t), "\n";

    }
    elsif ( lc( $S{$st}{'fmode'} ) eq "f2/f2" && lc($regim_f) ne "f2/f2" ) {

        #switch to f2/f2
        push @cmd, "1\t10\t3240,0000009E\t// otkl.kanalov FGSVCH";
        push @cmd, "1\t10\t3240,00000021\t// otkl. get FGTCH";
        push @cmd, "1\t10\t3240,0000001E\t// vkl get. 254 MHz";
        push @cmd, "1\t10\t3220,00002075\t// Work, 72 Mbod, F2/F2 USTM ON";
        push @cmd, "1\t30\t866-130\t// PFK-5, 32kbod";
        $regim_f = "f2/f2";

        #		$t=$S{$st}{'start'}+$S{$st}{'ts_bef'}*60;
        $t = $GSHB{$st};
        insert_block( \$t, \@cmd, "-", 2 );
        @cmd = ();
        print "Switch to f2/f2\tCode: ", $S{$st}{'obscode'}, " Start: ",
          &print_time($t), "\n";

    }
}

# v16+
# v17
# power on - poweroff receivers

print "\n", "*" x 50, "\n";
print "Power ON | Power OFF receivers\n";
print "to this moment min time is ", min( keys %times ), " =  ",
  &print_time( min( keys %times ) ), "\n";

@keys = ();    # obs + just + just_virk
foreach ( sort keys %S ) {
    if (   $S{$_}{'type'} eq "obs"
        || $S{$_}{'type'} eq "just_virk"
        || $S{$_}{'type'} eq "just" )
    {
        push @keys, $_;
    }
}
my @cmd = ();
@keys = sort { $a <=> $b } @keys;

print "All powerON times:\n",  Dumper( \%all_rec_poweron ),  "\n" if $debug;
print "All powerOFF times:\n", Dumper( \%all_rec_poweroff ), "\n" if $debug;
print "-."x30,"\n";
# print obscodes and start times for observations, when any receivers should be powered on
# in a human-readable format
if ($debug){
	foreach(sort {$a<=>$b} keys %all_rec_poweron ){
		
# 		print "Human, read this!!\n";
		my @keys = @{$all_rec_poweron{$_}};
# 		print join("\n",@keys)."\n" and die;
		print "receiver $_ powered on before : \n";

		for my $k (sort {$a<=>$b} @keys){
					print "\t"x4,$S{$k}{'obscode'} ,"\n";
		}
	}
}








my $kband_ON =
  0;    # flag that any of the K-band receivers is powered on (either K1 or K2)

for ( my $i = 0 ; $i < scalar @keys ; $i++ ) {
    my @poweron_now  = ();
    my @poweroff_now = ();

    my $poweroff_kband = 1
      ; # power off the K-band receiver flag. To be set 0 if K-band should not be powered off.
    my $poweron_kband = 0;    # power on the K-band receiver;

    # determine if any recs are to be powerred on before this obs. And OFF after
    foreach my $rec ( keys %all_rec_poweron ) {

        # ON
        foreach my $tt ( @{ $all_rec_poweron{$rec} } ) {

# if before the observation $i the receiver $rec with poweron time $tt should be powered on
            if ( $tt == $keys[$i] ) {
                print "))power on $rec\n";

   # no questions for the first observation. Just power on the fucking receiver.
                if ( $i == 0 ) {
                    push @poweron_now, $rec;
                }

  # else need to check if the same receiver was not used during previous 5 hours
                else {
                  BEFOBSON: for ( my $j = 0 ; $j < $i ; $j++ ) {

                        if ( $rec !~ m/k/i ) {

# First channel: C1,L1,P1
# If there WERE previous observations with the same receiver within 5 hours before the current observation (so they should not be powered off yet)
                            if (
                                lc( substr( $S{ $keys[$j] }{'bands'}, 0, 1 ) )
                                eq lc( substr( $rec, 0, 1 ) )
                                and ( $S{ $keys[$j] }{'stop'} -
                                    $S{ $keys[$i] }{'start'} ) < 5 * 3600
                              )
                            {
                                # do nothing
                                # 							die "soft\n";

                            }
                            else {
                                push @poweron_now, $rec;
                                last BEFOBSON;
                            }

# Second channel: C2,L2,P2
# If there WERE previous observations with the same receiver within 5 hours before the current observation (so they should not be powered off yet)
                            if (
                                lc( substr( $S{ $keys[$j] }{'bands'}, 1, 1 ) )
                                eq lc( substr( $rec, 0, 1 ) )
                                and ( $S{ $keys[$j] }{'stop'} -
                                    $S{ $keys[$i] }{'start'} ) < 5 * 3600
                              )
                            {
                                # do nothing
                                # 							die "light\n";
                            }
                            else {
                                push @poweron_now, $rec;
                                last BEFOBSON;
                            }
                        }
                        else {

# Any channel: K1, K2
# If there WERE previous observations with the same receiver within 5 hours before the current observation (so they should not be powered off yet)
                            if (
                                (
                                    lc(
                                        substr(
                                            $S{ $keys[$j] }{'bands'}, 0, 1
                                        )
                                    ) eq lc( substr( $rec, 0, 1 ) )
                                    or lc(
                                        substr(
                                            $S{ $keys[$j] }{'bands'}, 1, 1
                                        )
                                    ) eq lc( substr( $rec, 0, 1 ) )
                                )
                                and ( $S{ $keys[$j] }{'stop'} -
                                    $S{ $keys[$i] }{'start'} ) < 5 * 3600
                              )
                            {
                                # do nothing

                                # 							die "yep\n";

                            }
                            else {
                                if ( any { $_ =~ m/k/i } @poweron_now ) {

                                    # do not power on K-band twice
                                }
                                else {
                                    push @poweron_now, $rec;
                                    last BEFOBSON;
                                }
                            }

                            # 						if($rec=~m/k/i){die "hard\n";}
                        }

                    }
                }
            }
        }

        # off
        foreach my $tt ( @{ $all_rec_poweroff{$rec} } ) {

# if after the observation $i the receiver $rec with poweroff time $tt should be powered off
            if ( $tt == $keys[$i] ) {
                print "((power off $rec\n";

   # no questions for the last observation. Just power off the fucking receiver.
                if ( $i == $#keys ) {
                    push @poweroff_now, $rec;
                }

  # else need to check if the same receiver was not used during previous 5 hours
                else {
                  AFTEROBSOFF: for ( my $j = $i + 1 ; $j < scalar @keys ; $j++ ) {
#                             print 'abcdef';
#                             print Dumper($S{ $keys[$j] });

                        # v19
                        if (
                            (
                                $S{ $keys[$j] }{'start'} -
                                $S{ $keys[$i] }{'stop'}
                            ) >= 5 * 3600
                          )
                        {
                            # IT IS VITALLY IMPORTANT THAT @keys IS SORTED
                            push @poweroff_now, $rec;
                            last AFTEROBSOFF;
                        }

                        if ( $rec !~ m/k/i ) {
                            if ($S{ $keys[$j] }{'type'} eq 'just' and $rec =~ m/c1/i and substr(
                                            $S{ $keys[$j] }{'bands'}, 1, 1
                                        ) =~ m/c/i)
                            {
                                push @poweroff_now, $rec;
                                last AFTEROBSOFF;
                            }

# First channel: C1,L1,P1
# If there ARE future observations with the same receiver within 5 hours after the current observation (so they should not be powered off now)
                            if (
                                ! (
                                    lc(
                                        substr(
                                            $S{ $keys[$j] }{'bands'}, 0, 1
                                        )
                                    ) eq lc( substr( $rec, 0, 1 ) )
                                    or lc(
                                        substr(
                                            $S{ $keys[$j] }{'bands'}, 1, 1
                                        )
                                    ) eq lc( substr( $rec, 0, 1 ) )
                                )
                              )
                            {
                                push @poweroff_now, $rec;
                                last AFTEROBSOFF;
                            }
                        }
                        else {
                            # 						if($rec=~m/k/i){die "OFF hard\n";}

                            print "rec = $rec\n";
                            print $S{ $keys[$j] }{'obscode'}, "\n";

# Any channel: K1, K2
# If there ARE future observations with ***any K-band*** receiver within 5 hours after the current observation (so they should not be powered off now)

                            print "bands = ",
                              lc( substr( $S{ $keys[$j] }{'bands'}, 0, 1 ) ),
                              "\n";
                            print "bands = ",
                              lc( substr( $S{ $keys[$j] }{'bands'}, 1, 1 ) ),
                              "\n";

                            if (
                                (
                                    lc(
                                        substr(
                                            $S{ $keys[$j] }{'bands'}, 0, 1
                                        )
                                    ) eq lc( substr( $rec, 0, 1 ) )
                                    or lc(
                                        substr(
                                            $S{ $keys[$j] }{'bands'}, 1, 1
                                        )
                                    ) eq lc( substr( $rec, 0, 1 ) )
                                )
                              )
                            {
                                # do nothing
                                # 								die "will I??\n";

                            }
                            else {
                                if ( any { $_ =~ m/k/i } @poweroff_now ) {

                                    # do not power off K-band twice
                                    # 									die "twice\n";
                                }
                                else {

                                    # 									die "wtf\n";
                                    push @poweroff_now, $rec;
                                    last AFTEROBSOFF;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #     print "kband_ON = $kband_ON \n";

    if ( scalar @poweron_now ) {

        print "OBS = ", $S{ $keys[$i] }{'obscode'}, " \t poweron  ",
          join( " ", @poweron_now ), "\n"
          if $debug;

# prev time is either end of prev GHSa, or stop of prev observation, or global start time
        my $prev_time;
        if ( $i == 0 ) {
            $prev_time = $global_start_sec;

# 	    print "prev time = glbal start\n";
# v18. check if time2warm up is enough, then set it to -2 hours from the observation.
        }
        else {
            $prev_time = (
                defined $GSHA{ $S{ $keys[ $i - 1 ] }{'stop'} }
                ? $GSHA{ $S{ $keys[ $i - 1 ] }{'stop'} }
                : $S{ $keys[ $i - 1 ] }{'stop'} + 5 * 60
            );
        }

        # define warm up time
        my $time2warmup = 7200;
        if ( any { m/[kc]/i } @poweron_now ) {
            $time2warmup = 7200;
        }
        else { $time2warmup = 5700; }

        # v18. warmup time = 3600 for coherent
        if ( $S{ $keys[$i] }{'ts_mode'} =~ m/ch/i and $S{$_}{'obscode'} =~ m/(?:puts|gbts|grts|raks19)/i) { $time2warmup = 3600; }		# coherent for gravitational observations only

        if ( $i == 0 ) {
            if ( $time_to_start > $time2warmup ) {

                # v18
                # do not modify time2warmup if it fits well
            }
            else {
                $time2warmup =
                  $keys[$i] -
                  $global_start_sec -
                  5 * 60;    # give 5 min on initial commands
            }
        }

        # 	die 57;

# # v16+
# # TODO: if any K-band receiver is already powered on, then no need to power it on again.
# # if K1 and K2 are both intended to be powered on, then power on only one of them
#
# 	# THIS CAN MAKE SCALAR @POWERON_NOW == 0 !!!! HAVE TO INTRODUCE ADDITIONAL CHECK
#
# 	# if need to power on K1 but K-band rec is already on.
# 	# then remove K1 from poweron_now
# 	if((any {$_ =~ m/k1/i} @poweron_now ) and $kband_ON >=1 ){
# 		for(my $i=0;$i<scalar @poweron_now;$i++){
# 			if($poweron_now[$i] =~ m/k1/i){
# # 				splice(@poweron_now, $i, 1);
# # 				print "removed $poweron_now[$i]\n";
# 			}
# 		}
# 	}
# 	# if need to power on K2 but K-band rec is already on.
# 	# then remove K2 from poweron_now
# 	elsif((any {$_ =~ m/k2/i} @poweron_now ) and $kband_ON >=1 ){
# 		for(my $i=0;$i<scalar @poweron_now;$i++){
# 			if($poweron_now[$i] =~ m/k2/i){
# # 				print "removed $poweron_now[$i]\n";
# # 				splice(@poweron_now, $i, 1);
# # 				die 57;
# 			}
# 		}
# 	}

        # 	print "kband_ON flag = ", $kband_ON, " which means that\n";

        # 	print "scalar poweron_now = ", scalar @poweron_now,"\n";

        if ( scalar @poweron_now ) {

            if (   ( any { $_ =~ m/k1/i } @poweron_now )
                or ( any { $_ =~ m/k2/i } @poweron_now ) )
            {
                @poweron_now = kfirst( \@poweron_now );
            }

            # poweron cmds
            my $ref = poweron( \@poweron_now );

            # v18
            # do not switch on TRST-6 for CH mode observations

            if ( $S{ $keys[$i] }{'ts_mode'} =~ m/ch/i
                and ( any { $_ =~ m/c/i } @poweron_now )  and $S{$_}{'obscode'} =~ m/(?:puts|gbts|grts|raks19)/i )		# grav only
            {
                for my $i ( 0 .. $#$ref ) {
                    if ( $$ref[$i] =~ m/3130.*TRST/i ) {
                        splice @$ref, $i, 1;
                        last;
                    }
                }

                # 				print Dumper($ref) and die;
            }

            my @cmd = @$ref;

            if ( $S{ $keys[$i] }{'type'} =~ /just/i ) {
                $t = $keys[$i];
                insert_block( \$t, \@cmd, "-", 2 );    # move into past

            }
            else {
                # if enough time for warm up
                if ( ( $keys[$i] - $prev_time ) > $time2warmup ) {
                    $t = $keys[$i] - $time2warmup;
                    insert_block( \$t, \@cmd, "-", 2 );    # move into past
                }

# if not then for first obs poweron at global start. For others power on before prev obs, i.e. not after.
                else {
                    if ( $i == 0 ) {
                        $t = $global_start_sec + 5 * 60;
                        insert_block( \$t, \@cmd, "+", 2 );   # move into future
                    }
                    else {
                        $t = $S{ $keys[ $i - 1 ] }{'start'};
                        insert_block( \$t, \@cmd, "-", 2 );    # move into past
                    }
                }
            }
        }
    }

    #     print $S{$keys[$i]}{'obscode'}, " warmup time = ", $time2warmup,"\n";

    # POWEROFF
    if ( scalar @poweroff_now ) {
        print "OBS = ", $S{ $keys[$i] }{'obscode'}, " \t powerOFF  ",
          join( " ", @poweroff_now ), "\n"
          if $debug;
        $t = (
            defined $GSHA{ $S{ $keys[$i] }{'stop'} }
            ? $GSHA{ $S{ $keys[$i] }{'stop'} }
            : $S{ $keys[$i] }{'stop'} + 5 * 60
        );

# v19 . for yust poweroff should be done right after $S{$keys[$i]}{'stop'}, since it already accounts for GSH time
        if ( $S{ $keys[$i] }{'type'} eq 'just' ) {
            $t = $S{ $keys[$i] }{'stop'};
        }

        my @super_uniq_now = super_uniq(@poweroff_now);
        print "poweroff now:\n", join( "\t", @super_uniq_now ), "\n";
        foreach my $r (@super_uniq_now) {
            my @cmd = read_file( uc($r) . "1/" . lc($r) . "1_power_off" );

# v18
# for CH sessions there is no need to switch off TRST-6 after the CH-observation, since is should be switched off 30 min in advance of the CH-obs.
# GRAV inly
            if ( $S{ $keys[$i] }{'ts_mode'} =~ m/ch/i  and $S{$_}{'obscode'} =~ m/(?:puts|gbts|grts|raks19)/i) {		
                for my $j ( 0 .. $#cmd ) {
                    if ( $cmd[$j] =~ m/3132.*TRST/i ) {
                        splice @cmd, $j, 1;
                        last;
                    }
                }
            }
            insert_block( \$t, \@cmd, "+", 2 );
            $t += 30;    # 30 sec
        }
    }
}

# die 58;

# 10. initial common commands

#print Dumper(\%times);

my @mm = minmax( sort { $a <=> $b } keys %times );

## initial common commands
print "initial common commands\n";
print "to this moment min time is $mm[0] =  ", &print_time( $mm[0] ), "\n";

# print "to this moment min time is ", min(keys %times)," =  ",&print_time(min(keys %times)),"\n";

if ( $S{$firstobskey}{'type'} eq 'just' ) {

    print "to this moment min JUST time is $firstobskey =  ",
      &print_time($firstobskey), "\n";

    $t = $firstobskey - 300;
}
else {
    $t = $mm[0];
}

my @cmd = read_file("COM/com_start");

# Formatter regime in the beginning

if ( $S{ $keys[0] }{'fmode'} =~ m/f3\/f3/i ) {

    push @cmd, "1\t10\t3240,0000009E\t// otkl.kanalov FGSVCH";
    push @cmd, "1\t10\t3240,00000021\t// otkl. get FGTCH";
    push @cmd, "1\t10\t3240,0000001F\t// vkl get. 258 MHz";
    push @cmd, "1\t10\t3220,000020B5\t// Work, 72 Mbod, F3/F3 USTM ON";
    push @cmd, "1\t30\t866-130\t// PFK-5, 32kbod";
    $regim_f = "f3/f3";

    #		$t=$S{$st}{'start'}+$S{$st}{'ts_bef'}*60;
    #		$t=$GSHB{$st};
    #		insert_block(\$t,\@cmd,"-",2);
    #		@cmd=();
    print "Switch to f3/f3\tCode: ", $S{ $keys[0] }{'obscode'}, " Start: ",
      &print_time($t), "\n";

}
elsif ( $S{ $keys[0] }{'fmode'} =~ m/f2\/f2/i ) {

    #switch to f2/f2
    push @cmd, "1\t10\t3240,0000009E\t// otkl.kanalov FGSVCH";
    push @cmd, "1\t10\t3240,00000021\t// otkl. get FGTCH";
    push @cmd, "1\t10\t3240,0000001E\t// vkl get. 254 MHz";
    push @cmd, "1\t10\t3220,00002075\t// Work, 72 Mbod, F2/F2 USTM ON";
    push @cmd, "1\t30\t866-130\t// PFK-5, 32kbod";
    $regim_f = "f2/f2";

    #		$t=$S{$st}{'start'}+$S{$st}{'ts_bef'}*60;
    #		$t=$GSHB{$st};
    #		insert_block(\$t,\@cmd,"-",2);
    #		@cmd=();
    print "Switch to f2/f2\tCode: ", $S{ $keys[0] }{'obscode'}, " Start: ",
      &print_time($t), "\n";

}

my @rep_cmd = repeat_block( \@cmd, 2 );
unshift @rep_cmd, "1\t" . $dt . "\t866-34\t// vkl zapis ZU";
unless ( $S{ $keys[0] }{'type'} eq 'just' ) {
    push @rep_cmd, "1\t" . $dt . "\t808\t// otkl zapis ZU";
}
insert_block( \$t, \@rep_cmd, "-", 1 );

# print Dumper(%times);

# v16++
# TODO: put the FGSVCh , FGTCh etc. power on/off commands for the periods of more than 5 hours inactivity.

# The following should imply only if number of rec periods is more than 1. (i.e. there is at least one gap longer than 5 hours )
if ( ( scalar @rec_periods ) > 1 ) {

    print "\@" x 50, "\n";

    # same as above in the beginning
    my $time_of_prev_stop1;
    my %receiver_poweroff1;
    my %receiver_poweron1;
    my $prev_obs1 = $firstobskey;
    foreach ( sort keys %S ) {

        # skip non-observational stuff
        if (   $S{$_}{'type'} ne "obs"
            && $S{$_}{'type'} ne "just"
            && $S{$_}{'type'} ne "just_virk" )
        {
            next;
        }

        # skip first
        if ( abs( $_ - $firstobskey ) < 1 ) {
            $time_of_prev_stop1 = $S{$_}{'stop'};
            $prev_obs1          = $_;
            next;
        }

        # find all period of > 5 hours between observations
        if (   $S{$_}{'type'} eq "obs"
            || $S{$_}{'type'} eq "just"
            || $S{$_}{'type'} eq "just_virk" )
        {
            my $time_of_this_start = $S{$_}{'start'};
            if ( $time_of_this_start - $time_of_prev_stop1 >= 5 * 3600 ) {
                $receiver_poweroff1{$prev_obs1} = 'all';
                $receiver_poweron1{$_}          = 'all';
            }
        }
        $time_of_prev_stop1 = $S{$_}{'stop'};
        $prev_obs1          = $_;
    }

    # TODO: introduce proper warmup time.
    #
    # 	my $time2warmup = 7000;
    # 	if(any {  m/k/i } @poweron_now){$time2warmup = 7000;}
    # 	else{$time2warmup = 5700;}
    #
    #

    print "POWER ON rec:\n";
    foreach ( sort keys %receiver_poweron1 ) {

        # skip the first obs since it should already be handled
        if ( abs( $_ - $firstobskey ) < 1 ) { next; }

        print "in advance before ", print_time($_), " power on \n";
        $t = $_ - 7000;

        my @cmd = read_file("COM/com_start");

        # Formatter regime

        if ( $S{ $keys[0] }{'fmode'} =~ m/f3\/f3/i ) {
            push @cmd, "1\t10\t3240,0000001F\t// vkl get. 258 MHz";
            push @cmd, "1\t10\t3220,000020B5\t// Work, 72 Mbod, F3/F3 USTM ON";
            push @cmd, "1\t30\t866-130\t// PFK-5, 32kbod";
            $regim_f = "f3/f3";
            print "Switch to f3/f3\tCode: ", $S{ $keys[0] }{'obscode'},
              " Start: ", &print_time($t), "\n";
        }
        elsif ( $S{ $keys[0] }{'fmode'} =~ m/f2\/f2/i ) {

            #switch to f2/f2
            push @cmd, "1\t10\t3240,0000001E\t// vkl get. 254 MHz";
            push @cmd, "1\t10\t3220,00002075\t// Work, 72 Mbod, F2/F2 USTM ON";
            push @cmd, "1\t30\t866-130\t// PFK-5, 32kbod";
            $regim_f = "f2/f2";
            print "Switch to f2/f2\tCode: ", $S{ $keys[0] }{'obscode'},
              " Start: ", &print_time($t), "\n";
        }

        my @rep_cmd = repeat_block( \@cmd, 2 );
        insert_block( \$t, \@rep_cmd, "-", 1 );
    }

    print "POWER OFF rec:\n";
    foreach ( sort keys %receiver_poweroff1 ) {

        # skip the last one obs
        if ( abs( $_ - $lastobskey ) < 1 ) { next; }

        print "after ", print_time( $S{$_}{'stop'} ), " power off \n";
        $t = $S{$_}{'stop'} + 10 * 60;

        my @cmd = ();
        push @cmd, "1\t10\t3240,00000021\t// otkl kanalov FGTCh";
        push @cmd, "1\t10\t3151\t// vkl pitanie BIK";
        my @rep_cmd = repeat_block( \@cmd, 2 );
        insert_block( \$t, \@rep_cmd, "+", 1 );

    }

}

## common commands in the end
print "end common commands\n";
print "to this moment max time is $mm[1] =  ", &print_time( $mm[1] ), "\n";

$t = $mm[1];

my @cmd = read_file("COM/com_end");
my @rep_cmd = repeat_block( \@cmd, 2 );

unless ( $S{ $keys[-1] }{'type'} eq 'just' ) {
    unshift @rep_cmd, "1\t" . $dt . "\t866-34\t// vkl zapis ZU";
}
push @rep_cmd, "1\t" . $dt . "\t808\t// otkl zapis ZU";
insert_block( \$t, \@rep_cmd, "+", 1 );

# final checks
my @mm = minmax( sort { $a <=> $b } keys %times );

if ( $mm[0] < $global_start_sec ) {
    print print_time( $mm[0] ), " ", $times{ $mm[0] }, "\n";

    # 	print Dumper(\%times);

    my @keys2print = sort keys %times;
    for ( 0 .. 20 ) {
        print print_time( $keys2print[$_] ), "\t", $times{ $keys2print[$_] },
          "\n";
    }

    die
"First command occures before preceeding SNS_COMMAND ends.\nFATAL ERROR. EXIT with no output written.\n";
}
if ( $mm[1] > $global_stop_sec ) {
    print print_time( $mm[1] ), " ", $times{ $mm[1] }, "\n";

    # print
    foreach my $i ( sort { $a <=> $b } keys %times ) {
        printf( "%s     SRT  PLAZMAPZ   PLAZMA=KK %s\n",
            print_time($i), $times{$i} );
    }
    die
"Last command occures after trailing SNS_COMMAND starts.\nFATAL ERROR. EXIT with no output written.\n";
}

# v18
# 2017-02-14
# if C-band TRST was powered on before the Coherent observation => power off 30 m in advance
# if C-band is to be used in <= 5 hours after CH observation, switch on TRST

my @keys4ch = sort { $a <=> $b } keys %S;
for ( my $k = 0 ; $k < scalar @keys4ch ; $k++ ) {
    my $n = $keys4ch[$k];
    if (    $S{$n}{'type'} ne 'obs'
        and $S{$n}{'type'} ne 'just'
        and $S{$n}{'type'} ne 'just_virk' )
    {
        next;
    }
    if ( $S{$n}{'ts_mode'} =~ m/ch/i  and $S{$n}{'obscode'} =~ m/(?:puts|gbts|grts|raks19)/i) {		# for GRAVITATIONAL observations only

        # check before
        foreach my $j ( 0 .. $k - 1 ) {
            if (    $keys4ch[$k] - $keys4ch[$j] < 5 * 3600
                and $S{ $keys4ch[$j] }{'bands'} =~ m/c/i )
            { # previous C-band observation was within 5 hours before the CH observations => need to power off TRST-6cm
                $t = $S{$n}{'start'} - 30 * 60;
                my @cmd;

                # 1	10	3132		// otkl. TRST-6
                push @cmd, "1\t" . $dt . "\t3132\t// otkl. TRST-6";
                insert_block( \$t, \@cmd, "-", 1 );
            }
        }

        # check after
        foreach my $j ( $k + 1 .. $#keys4ch ) {
            if (    $keys4ch[$j] - $S{ $keys4ch[$k] }{'stop'} < 5 * 3600
                and $S{ $keys4ch[$j] }{'bands'} =~ m/c/i )
            { # next C-band observation is within 5 hours after the CH observation => need to power on TRST-6cm back
                $t = $keys4ch[$j] - 3600 * 1.5;
                my @cmd;

                # 1	10	3130		// vkl TRST 6-1
                push @cmd, "1\t" . $dt . "\t3130\t// vkl TRST 6-1";
                insert_block( \$t, \@cmd, "-", 1 );
            }
        }
    }
}

# check the whole cyclogramm for duplicate ZU on/ off commands
# doesn't work properly yet
#
#
# my $zuon=0;
# my $zuoff=0;
# foreach (sort keys %times){
#
#
# if ($zuon == 0 and $times{$_}=~m/866\-34.*?vkl\s+zapis\s*ZU/i){
#     $zuon=1;
#
# }
# if ($zuon == 1 and $times{$_}=~m/866\-34.*?vkl\s+zapis\s*ZU/i){
#     $zuon=1;
#     delete $times{$_};
# }
#
# if ($zuoff == 0 and $times{$_}=~m/808.*?otkl\s+zapis\s*ZU/i){
#     $zuoff=1;
#     $zuon=0;
# }
# if ($zuoff == 1 and $times{$_}=~m/808.*?otkl\s+zapis\s*ZU/i){
#     $zuoff=1;
#     $zuon=0;
#     delete $times{$_};
# }
#
#
#
#
# }
#
#
#

# printing

my $nachalo = &print_time( $mm[0] );
$nachalo =~ tr/\.: //d;
my $konec = &print_time( $mm[1] );
$konec =~ tr/\.: //d;

if ($debug) {
    open O, ">", "ready_cyclogramm";
    print "Writing cyclogramm to ready_cyclogramm\n";
}
else {
    open O, ">", "ra$nachalo-$konec.01.035";
    print "Writing cyclogramm to ra$nachalo-$konec.01.035\n";
}

END {
    unless ($debug) { `python2 cyclogram_rb_ch.py ra$nachalo-$konec.01.035` }
    else{`python2 cyclogram_rb_ch.py ready_cyclogramm`}
}

# HEADER
my @today = Today();
my @now   = Now();
my $ver   = "01";

printf( O "//%02d%02d%02d.%s\n", @today, $ver );
print O "//", &print_time( $mm[0] ), " - ", &print_time( $mm[1] ), "\n";

my $today_readable =
  sprintf( "%02d.%02d.%02d", $today[0], $today[1], $today[2] );
my $now_readable = sprintf( "%02d:%02d:%02d", $now[0], $now[1], $now[2] );
print O
"//The file was created by Mikhail Lisakov on $today_readable $now_readable\n";
print O "//Input schedule file: $sogl, script file: $0 \n";
print O "//\n";

my $w40 = my $w4 = 0;
foreach ( keys %S ) {
    if ( $S{$_}{'power'} == 4 )  { $w4  = 1; }
    if ( $S{$_}{'power'} == 40 ) { $w40 = 1; }
}

if    ( $w40  && !$w4 ) { print O "// Regim 40W, HM\n"; }
elsif ( !$w40 && $w4 )  { print O "// Regim 4W, HM\n"; }
elsif ( $w40  && $w4 )  { print O "// Regim 4W, 40W, HM\n"; }

print O "// Vkl PFK5 \n";
print O "// Zapustit poletnoe zadanie (PZ)\n";
print O "// Otkluchit BAKIS\n//\n//\n";

my $ch = 1;
foreach ( sort keys %S ) {

    if ( $S{$_}{'type'} eq 'obs' ) {

# 	    my $comline="// Chapter $ch\n// Obscode= ".$S{$_}{'obscode'}."\n// ".$S{$_}{'source'}." ".$S{$_}{'ra'}." ".$S{$_}{'dec'}."\n// start= ".print_time($S{$_}{'start'})."\n// stop = ".print_time($S{$_}{'stop'})."\n// SunVector_deflection=    .0deg\n// TS = ".$S{$_}{'ts'}." ".$S{$_}{'ts_bef'}." ".$S{$_}{'ts_aft'}."\n// PRM = ".$S{$_}{'bands'}."\n// power = ".$S{$_}{'power'}."\n// fmode = ".$S{$_}{'fmode'}."\n//\n//";
        my $comline =
            "// Chapter $ch\n// Obscode= "
          . $S{$_}{'obscode'} . "\n// "
          . $S{$_}{'source'} . " "
          . $S{$_}{'ra'} . " "
          . $S{$_}{'dec'}
          . "\n// start= "
          . print_time( $S{$_}{'start'} )
          . "\n// stop = "
          . print_time( $S{$_}{'stop'} )
          . "\n// SunVector_deflection=    .0deg\n// TS = "
          . $S{$_}{'ts_string'}
          . "\n// PRM = "
          . $S{$_}{'bands'}
          . "\n// power = "
          . $S{$_}{'power'}
          . "\n// fmode = "
          . $S{$_}{'fmode'}
          . "\n// CFREQ = "
          . $S{$_}{'cfreq1'} . " "
          . $S{$_}{'cfreq2'}
          . "\n//\n//";

=c
	print O "// Chapter $ch
//Obscode= ",$S{$_}{'obscode'},"
//",$S{$_}{'source'}," ",$S{$_}{'ra'}," ",$S{$_}{'dec'},"
//start= ",print_time($S{$_}{'start'}),"
//stop = ",print_time($S{$_}{'stop'}),"
//SunVector_deflection=    .0deg
//TS = ",$S{$_}{'ts'}," ",$S{$_}{'ts_bef'}," ",$S{$_}{'ts_aft'},"
//PRM = ",$S{$_}{'bands'},"
//power = ",$S{$_}{'power'},"
//fmode = ",$S{$_}{'fmode'},"
//\n//\n";
=cut

        $times{ $S{$_}{'start'} + 60 } = $comline;
        $ch++;
    }

    if ( $S{$_}{'type'} eq 'just_virk' ) {
        my $comline =
"// Chapter $ch\n// Obscode= justirovka_VIRK  $S{$_}{'obscode'}\n// var = "
          . $S{$_}{'var'} . "\n// "
          . $S{$_}{'source'} . " "
          . $S{$_}{'ra'} . " "
          . $S{$_}{'dec'}
          . "\n// start= "
          . print_time( $S{$_}{'start'} )
          . "\n// stop = "
          . print_time( $S{$_}{'stop'} )
          . "\n// beginscan = "
          . print_time( $S{$_}{'beginscan'} )
          . "\n// endscan ="
          . print_time( $S{$_}{'endscan'} )
          . "\n// PRM = "
          . $S{$_}{'bands'}
          . "\n// TS = "
          . $S{$_}{'ts'} . " "
          . $S{$_}{'ts_bef'} . " "
          . $S{$_}{'ts_aft'}
          . "\n// power = "
          . $S{$_}{'power'}
          . "\n//\n//";

        $times{ $S{$_}{'start'} - 1 } = $comline;
        $ch++;
    }

    if ( $S{$_}{'type'} eq 'just' ) {
        my $comline =
            "// Chapter $ch\n// Obscode= justirovka\n// var = "
          . $S{$_}{'var'} . "\n// "
          . $S{$_}{'source'} . " "
          . $S{$_}{'ra'} . " "
          . $S{$_}{'dec'}
          . "\n// start= "
          . print_time( $S{$_}{'start'} )
          . "\n// stop = "
          . print_time( $S{$_}{'stop'} )
          . "\n// beginscan = "
          . print_time( $S{$_}{'beginscan'} )
          . "\n// endscan ="
          . print_time( $S{$_}{'endscan'} )
          . "\n// PRM = "
          . $S{$_}{'bands'}
          . "\n//\n//";

=c
	print O "// Chapter $ch
//Obscode= justirovka
//var = ",$S{$_}{'var'},"
//",$S{$_}{'source'}," ",$S{$_}{'ra'}," ",$S{$_}{'dec'},"
//start= ",print_time($S{$_}{'start'}),"
//stop = ",print_time($S{$_}{'stop'}),"
//beginscan = ",print_time($S{$_}{'beginscan'}),"
//endscan =",print_time($S{$_}{'endscan'}),"
//PRM = ",$S{$_}{'bands'},"
//\n//\n";
=cut

        $times{ $S{$_}{'beginscan'} - 1 } = $comline;
        $ch++;
    }

}

#$ch=1;
#foreach(sort keys %chasti){
#	print O "// Chast $ch\n";
#	print O $chasti{$_};
#	$ch++;
#}

# BODY
# add comments on observations
foreach ( sort keys %S ) {
    if ( $S{$_}{'type'} eq 'obs' ) {
        my $ts;
        if    ( $S{$_}{'ts'} eq 'GB_TS' )   { $ts = "GreenBank"; }
        elsif ( $S{$_}{'ts'} eq 'PUSH_TS' ) { $ts = "Pushchino"; }
        else                                { $ts = uc( $S{$_}{'ts'} ); }
        $times{ $S{$_}{'start'} + 59 } =
            "//\n// Observing source "
          . $S{$_}{'source'}
          . ". Bands: "
          . $S{$_}{'bands'}
          . ". ONA na "
          . $ts . " "
          . print_time( $S{$_}{'start'} + $S{$_}{'ts_bef'} * 60 ) . " - "
          . print_time( $S{$_}{'stop'} + $S{$_}{'ts_aft'} * 60 ) . "\n//";
    }
    elsif ( $S{$_}{'type'} eq 'just_virk' ) {
        my $ts;
        if    ( $S{$_}{'ts'} eq 'GB_TS' )   { $ts = "GreenBank"; }
        elsif ( $S{$_}{'ts'} eq 'PUSH_TS' ) { $ts = "Pushchino"; }
        else                                { $ts = uc( $S{$_}{'ts'} ); }
        $times{ $S{$_}{'beginscan'} + 59 } =
            "//\n// Observing source "
          . $S{$_}{'source'}
          . ". Bands: "
          . $S{$_}{'bands'}
          . ". ONA na "
          . $ts . " "
          . print_time( $S{$_}{'beginscan'} + $S{$_}{'ts_bef'} * 60 ) . " - "
          . print_time( $S{$_}{'endscan'} + $S{$_}{'ts_aft'} * 60 ) . "\n//";
    }
    if ( $S{$_}{'type'} eq 'just' ) {
        $times{ $S{$_}{'beginscan'} - 2 } =
            "//\n// JUSTIROVKA on source "
          . $S{$_}{'source'}
          . ". Bands: "
          . $S{$_}{'bands'} . "\n//";
    }

}

# add block separators
foreach ( sort { $a <=> $b } keys %T ) {
    $times{ $T{$_} + 1 } = "//" if not exists $times{ $T{$_} + 1 };
}

# print
foreach my $i ( sort { $a <=> $b } keys %times ) {
    if ( $times{$i} =~ m/^\// ) {
        print O $times{$i}, "\n";
    }
    else {
        #		printf(O "%s %s     SRT  PLAZMAPZ   PLAZMA=KK %s\n",$ddd,$ttt,$v);

        printf( O "%s     SRT  PLAZMAPZ   PLAZMA=KK %s\n",
            print_time($i), $times{$i} );

        #		print O print_time($i),"\t",$times{$i},"\n";
    }
}
close O;

print "ALL BLOCKS\n";
foreach ( sort { $a <=> $b } keys %T ) {

    print print_time($_), "\t", print_time( $T{$_} ), "\n";

}
##############################################################################################
##############################################################################################
##############################################################################################
# SUBROUTINES
##############################################################################################
##############################################################################################
##############################################################################################

# sub to reorder HIGH and LOW gsh
# INPUT: $bands, @block of GSH commands (typically gsh-off, gsh-high-on,gsh-off,gsh-low-on,gsh-off) for 2 bands
# OUTPUT: @reordered block

sub reorder_gsh {

    my ( $bands, @cmd ) = @_;
    my @res;

    # should be a simple case
    # if bands are not K-bands
    # need only to change blocks of n/2 commands
    if ( $bands !~ m/k/i ) {

        # i.e.
        #1	5	3240,0000004D	// vybor GSh visokiy 6-1
        #1	5	3240,00000069	// vybor GSh visokiy 18-2
        #1	5	3240,0000004B	// vkl GSh 6-1
        #1	35	3240,00000067	// vkl GSh 18-2
        #1	5	3240,0000004C	// otkl GSh 6-1
        #1	35	3240,00000068	// otkl GSh 18-2
        #1	5	3240,0000004E	// vybor GSh nizk 6-1
        #1	5	3240,0000006A	// vybor GSh nizk 18-2
        #1	5	3240,0000004B	// vkl GSh 6-1
        #1	35	3240,00000067	// vkl GSh 18-2
        #1	5	3240,0000004C	// otkl GSh 6-1
        #1	35	3240,00000068	// otkl GSh 18-2

        my $n = scalar @cmd;    # number of commands. Should be EVEN.
        if ( $n % 2 == 0 ) {
            @res =
              ( @cmd[ ( $n / 2 ) .. ( $n - 1 ) ], @cmd[ 0 .. ( $n / 2 - 1 ) ] );
            return @res;
        }
    }

    # dual k-band KK
    # need to exchange string 2 and 4
    elsif ( $bands =~ m/kk/i ) {

        # i.e.
        #1	5	3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA
        #1	45	3230,2443A060   // 2F0 7/8dB GSH-1 visokiy U 7.5mA	<-----|
        #1	45	3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA		      |
        #1	45	3230,2443A020   // 2F0 7/8dB GSH-1 nizkiy U 7.5mA	<-----|
        #1	45	3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA

        @res = ( @cmd[ 0, 3, 2, 1, 4 ] );
        return @res;
    }

    #the case of Kband with other band
    # i.e. CK, KL etc.
    # Must treat differently LK and KL for example.
    else {

        # case of KL, KC, KP
        if ( $bands =~ m/^k/i ) {

            #1	5	3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA
            #1	5	3240,00000069	// vybor GSh visokiy 18-2		%|
            #1	5	3230,2443A060   // 2F0 7/8dB GSH-1 visokiy U 7.5mA	%|
            #1	35	3240,00000067	// vkl GSh 18-2				%|<-----|
            #1	5	3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA		%|	|
            #1	35	3240,00000068	// otkl GSh 18-2			%|	|
            #1	5	3240,0000006A	// vybor GSh nizk 18-2			*|	|
            #1	5	3230,2443A020   // 2F0 7/8dB GSH-1 nizkiy U 7.5mA	*|	|
            #1	35	3240,00000067	// vkl GSh 18-2				*|<-----|
            #1	5	3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA		*|
            #1	35	3240,00000068	// otkl GSh 18-2			*|

            @res = @cmd[ 0, 6 .. 10, 1 .. 5 ];
            return @res;

        }

        # case of CK, PK, LK
        elsif ( $bands =~ m/k$/i ) {

#1	5	3240,0000004D	// vybor GSh visokiy 6-1		<-----|
#1       5       3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA		      |
#1	5	3240,0000004B	// vkl GSh 6-1				      |
#1       35      3230,2443A060   // 2F0 7/8dB GSH-1 visokiy U 7.5mA	      |	<-------|
#1	5	3240,0000004C	// otkl GSh 6-1				      |		|
#1       35      3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA		      |		|
#1	5	3240,0000004E	// vybor GSh nizk 6-1			<-----|		|
#1	5	3240,0000004B	// vkl GSh 6-1						|
#1       35      3230,2443A020   // 2F0 7/8dB GSH-1 nizkiy U 7.5mA		<-------|
#1	5	3240,0000004C	// otkl GSh 6-1
#1       35      3230,2443A000   // 2F0 7/8dB GSH-otkl U 7.5mA

            @res = @cmd[ 6, 1, 2, 8, 4, 5, 0, 7, 3, 9, 10 ];
            return @res;
        }
    }
    return 0;

}

# read file with commands and write it to an array skipping blank and commented lines
# INPUT: filename, mode (all, part)
# part reads till first hash-commented line
# OUTPUT: array
sub read_file() {

    my $file = shift;
    my $mode = shift;
    $mode = 'all' unless $mode;

    my @arr = ();

    open F, $file or die "Cannot open $file. LINE: ". __LINE__."\n";
    while ( my $l = <F> ) {
        if ( $l =~ m/^\*/ ) { next; }
        chomp $l;
        if ( $mode eq 'all' ) {
            if   ( $l =~ m/^#/ || $l =~ m/^\s*$/ ) { next; }
            else                                   { push @arr, $l; }
        }
        elsif ( $mode eq 'part' ) {
            if    ( $l =~ m/^\s*$/ ) { next; }
            elsif ( $l =~ m/^#/ )    { last; }
            else                     { push @arr, $l; }
        }
    }
    close F;

    return @arr;

}

# calculate duration of a block of commands
# INPUT: reference to an array. Each line contains after command time and command itself
# OUTPUT: duration of a command block in seconds
sub block_duration() {
    my $ar_ref   = $_[0];
    my $duration = 0;

    foreach (@$ar_ref) {
        if ( substr( $_, 0, 1 ) eq "#" ) {
            next;
        }    # added on 22 NOV. Allows commented lines
        ( my $n, my $delay, my $cmd, my $comment ) = split /\t+/, $_;
        $duration += $delay;
    }

    return $duration;
}

# return unique values from array preserving the order. This sub is used to determine receivers to be powered on and their order.
# INPUT: array
# OUTPUT: array of unique values

sub uniq {
    my %seen = ();
    my @r    = ();
    my @ar   = @_;
    foreach my $val (@ar) {
        $val =~ s/\s+//g;
        if ( !$val ) { next; }
        unless ( $seen{$val} ) {
            push @r, $val;
            $seen{$val} = 1;
        }
    }
    return @r;
}

# return unique values from array preserving the order. This sub is used to determine receivers to be powered on and their order.
# INPUT: array
# OUTPUT: array of unique values

sub super_uniq {
    my %seen = ();
    my @r    = ();
    my @ar   = @_;
    foreach my $val (@ar) {
        $val =~ s/\s+//g;
        $val =~ s/[12]//g;
        if ( !$val ) { next; }
        unless ( $seen{$val} ) {
            push @r, $val;
            $seen{$val} = 1;
        }
    }
    return @r;
}

# sub to repeat block line by line. Useful to calculate duration.
# INPUT: ref to array, number of repeats
# OUTPUT: repeated array
sub repeat_block() {

    my $ar_ref = shift;
    my $repeat = shift;

    my @rep_array = ();

    foreach my $i (@$ar_ref) {
        ( my $n, my $delay, my $cmd, my $comment ) = split /\s+/, $i, 4;
        print "comment = $comment\n" if $debug2;
        if ( length($cmd) <= 8 ) {
            my $new =
                $n . "\t"
              . $delay . "\t"
              . $cmd . "\t"
              . $comment;    # 	WITH COMMENTS
            push @rep_array, $new;
            next;
        }    # short commands are not to be repeated

        if ( $repeat == 1 ) {
            my $new =
                $n . "\t"
              . $delay . "\t"
              . $cmd . "\t"
              . $comment;    # 	WITH COMMENTS
            push @rep_array, $new;
        }    # number 1

        elsif ( $repeat == 2 ) {
            my $new =
              $n . "\t" . $dt . "\t" . $cmd . "\t" . $comment;  # 	WITH COMMENTS
            push @rep_array, $new;
            my $new =
                $n . "\t"
              . ( ( $delay - $dt ) > $dt ? ( $delay - $dt ) : $dt ) . "\t"
              . $cmd . "\t"
              . "//";    # 	WITHout COMMENTS
            push @rep_array, $new;
        }
        else {
            my $new =
              $n . "\t" . $dt . "\t" . $cmd . "\t" . $comment;  # 	WITH COMMENTS
            push @rep_array, $new;

            for my $j ( 2 .. ( $repeat - 1 ) ) {
                my $new = $n . "\t" . $dt . "\t" . $cmd . "\t" . "//";
                push @rep_array, $new;
            }
            my $new =
              $n . "\t"
              . (
                  ( $delay - $dt * ( $repeat - 1 ) ) >= $dt
                ? ( $delay - $dt * ( $repeat - 1 ) )
                : $dt
              )
              . "\t"
              . $cmd . "\t" . " //";
            push @rep_array, $new;

        }
    }

    return @rep_array;
}

# this sub inserts block of commands
# INPUT: reference to global time, ref to array with commands, direction to move, how many times to repeat
# OUTPUT:
sub insert_block() {    # of commands
    ( my $t_ref, my $ar_ref, my $dir, my $repeat ) = @_;    # read inputs
    my $shift = $dt;
    if ( !$repeat ) { $repeat = 1; }    # check if we need to repeat
    if ( $dir eq "-" ) {
        $shift = -$dt;
    } # choose a direction to move block in case of overlapping with existing commands. A value of the shift is assigned here as well
    my @rep_array =
      &repeat_block( $ar_ref, $repeat );    # same array with repeated values
    my @keys = keys %times;                 # keys of global times hash array

    print join( "\n", @rep_array ), "\n" if $debug2;

    my $d_t     = &block_duration($ar_ref);
    my $d_t_rep = &block_duration( \@rep_array );

    print "block duration = $d_t\n"                  if $debug2;
    print "block duration with repeats = $d_t_rep\n" if $debug2;

    my $conflict = 0;

    foreach my $c ( sort keys %T ) {
        if (
            ( $$t_ref >= $c && $$t_ref <= $T{$c} )
            || (   ( $$t_ref + $d_t_rep ) >= $c
                && ( $$t_ref + $d_t_rep ) <= $T{$c} )
            || ( $c >= $$t_ref && $T{$c} <= ( $$t_ref + $d_t_rep ) )
          )
        {
            $conflict = 1;
        }
    }

    # move until no conflict
  OUTER: while ($conflict) {

        print "conf = $conflict\n"                           if $debug2;
        print "block start\tstarttime\tstoptime\tblockend\n" if $debug2;
        foreach my $c ( sort keys %T ) {

            print print_time_only($c), "\t", print_time_only($$t_ref), "\t",
              print_time_only( $$t_ref + $d_t_rep ), "\t",
              print_time_only( $T{$c} ), "\n"
              if $debug2;

            if (
                ( $$t_ref >= $c && $$t_ref <= $T{$c} )
                || (   ( $$t_ref + $d_t_rep ) >= $c
                    && ( $$t_ref + $d_t_rep ) <= $T{$c} )
                || ( $c >= $$t_ref && $T{$c} <= ( $$t_ref + $d_t_rep ) )
              )
            {
                $conflict = 1;

#print "insert_block: conflict with\n\t\t",print_time($c),"( block duration ",$d_t_rep," )\n" if $debug;
#print "t-ref was ",$$t_ref,"\t",print_time($$t_ref),"\n";
                $$t_ref += $shift;

                #print "t-ref became ",$$t_ref,"\t",print_time($$t_ref),"\n";
                next OUTER;
            }
            else {
                $conflict = 0;
            }
        }

    }

    print "conf = $conflict\n" if $debug2;

    # fill %times

    my $lt = $$t_ref;    # local time
    foreach my $i (@rep_array) {
        ( my $n, my $delay, my $cmd, my $comment ) = split /\t+/, $i;
        $times{$lt} = $cmd . ( length($cmd) > 8 ? "\t" : "\t\t" ) . $comment;

        $lt += $delay;
    }

    #$comments{qq($$t_ref+3)}="//\n";

    $T{$$t_ref} = $lt;

    print "block borders: start= ", print_time($$t_ref), "\tstop= ",
      print_time($lt), "\n"
      if $debug2;
    print "block duration = ", $lt - $$t_ref, " sec\n" if $debug2;

    $$t_ref = $lt;

}

####################################################################################################################################
####################################################################################################################################
####################################################################################################################################
#################################      ORIGINAL VARIANT BELOW     ##################################################################

# this sub inserts block of commands
# INPUT: reference to global time, ref to array with commands, direction to move, how many times to repeat
# OUTPUT:
sub insert_block0() {    # of commands
    ( my $t_ref, my $ar_ref, my $dir, my $repeat ) = @_;    # read inputs
    my $shift = $dt;
    if ( !$repeat ) { $repeat = 1; }    # check if we need to repeat
    if ( $dir eq "-" ) {
        $shift = -$dt;
    } # choose a direction to move block in case of overlapping with existing commands. A value of the shift is assigned here as well

    my @rep_array =
      &repeat_block( $ar_ref, $repeat );    # same array with repeated values

    my @keys = keys %times;                 # keys of global times hash array

    print join( "\n", @rep_array ), "\n" if $debug2;

    my $d_t     = &block_duration($ar_ref);
    my $d_t_rep = &block_duration( \@rep_array );

    print "block duration = $d_t\n";
    print "block duration with repeats = $d_t_rep\n";

    my $conflict = 0;

    # check fo conflicts with exsisting blocks
    foreach my $k ( sort keys %times ) {
        if ( $k >= $$t_ref && $k <= ( $$t_ref + $d_t_rep ) ) { $conflict = 1; }
    }

    my $new_conflict = 0;

    foreach my $c ( sort keys %T ) {
        if ( $$t_ref >= $c && $$t_ref <= $T{$c} ) { $new_conflict = 1; }
    }

    print "conf = $conflict, new_conf = $new_conflict\n" if $debug;

    # move until no conflict
  OUTER: while ($conflict) {

        print "conf = $conflict, new_conf = $new_conflict\n" if $debug;

        foreach my $kk ( sort { $a <=> $b } grep { $_ == $_ } keys %times )
        {    # loop over numerical fields of %times sorted in acsending order
            for (
                my $i = $$t_ref ;
                $i <= ( $$t_ref + $d_t_rep ) ;
                $i = $i + $dt
              )
            {
                if ( $kk == $i ) {
                    print "insert_block: conflict with\n\t\t", $times{$kk},
                      "\n\t\tat ", print_time($kk), "( block duration ",
                      $d_t_rep, " from ", print_time_only($$t_ref), " to ",
                      print_time_only( $$t_ref + $d_t_rep ), " )\n"
                      if $debug;
                    $conflict = 1;
                    $$t_ref += $shift;
                    next OUTER;
                }
                else { $conflict = 0; }
            }
        }
    }

    print "conf = $conflict, new_conf = $new_conflict\n" if $debug;

    # fill %times

    my $lt = $$t_ref;    # local time
    foreach my $i (@rep_array) {
        ( my $n, my $delay, my $cmd, my $comment ) = split /\t+/, $i;
        $times{$lt} = $cmd . ( length($cmd) > 6 ? "\t" : "\t\t" ) . $comment;

        $lt += $delay;
    }

    #$comments{qq($$t_ref+3)}="//\n";

    $T{$$t_ref} = $lt;

    $$t_ref = $lt;

}

# place k_band receiver first
# INPUT: ref to array
sub kfirst() {
    my $arref = shift;
    my $k     = 0;
    for my $i ( 0 .. $#$arref ) {    # delete K1 and K2
        if ( $$arref[$i] =~ m/k/i ) {
            splice @$arref, $i, 1;
            $k = 1;
            redo;
        }
    }
    if ($k) { unshift @$arref, "K1"; }    # place K1 in the beginning
    return @$arref;
}

#sub to power on receivers
# INPUTS: ref to array with recs.
# OUTPUT: ref to array with cmds, need to be properly placed
sub poweron {
    my $ref  = shift;
    my @recs = @$ref;
    my @allcmd;

    my $flag = 0;    # to get rid of extra P1 power on
    if ( any { $_ =~ m/p1/i } @uniq_to_poweron ) {
        $flag += 2;
    }
    if ( any { $_ =~ m/p2/i } @uniq_to_poweron ) {
        $flag -= 1;
    }

    # flag = 0 if p1 and p2 are not used
    # flag = 2 if p1 is used
    # flag = -1 if p2 is used
    # flag = 1 if p1 and p2 are used

    foreach my $r (@recs) {
        my @cmd = &read_file( uc($r) . "/" . lc($r) . "_power_on" );
        if ( $r =~ m/c1/i ) {
            push @cmd, &read_file("C1/c1_att");
        }
        if ( $r =~ m/c2/i ) {
            push @cmd, &read_file("C2/c2_att");
        }
        if ( $r =~ m/p2/i and $flag == -1 ) {
            push @cmd, &read_file( "P1/p1_power_on", 'part' );
        }
        push @allcmd, @cmd;
    }

    return \@allcmd;

}

# For debug purposes. Die reporting firs 50 commands.
sub die_smart {
    my @mm = minmax( sort { $a <=> $b } keys %times );
    print "to this moment min time is $mm[0] =  ", &print_time( $mm[0] ), "\n";
    my @keys2print = sort keys %times;
    for ( 0 .. 50 ) {
        print print_time( $keys2print[$_] ), "\t", $times{ $keys2print[$_] },
          "\n";
    }
    die 53;

}






# this sub simulates an insertion of a block of commands
# INPUT: reference to global time (will not change), ref to array with commands, direction to move, how many times to repeat
# OUTPUT: global time of a block start.
sub simulate_insert_block() {    # of commands
    ( my $t_ref, my $ar_ref, my $dir, my $repeat ) = @_;    # read inputs
    
    my $LOCAL_T = $$t_ref;		# local copy of the global time variable. Will return this.
    
    my $shift = $dt;
    if ( !$repeat ) { $repeat = 1; }    # check if we need to repeat
    if ( $dir eq "-" ) {
        $shift = -$dt;
    } # choose a direction to move block in case of overlapping with existing commands. A value of the shift is assigned here as well
    my @rep_array =
      &repeat_block( $ar_ref, $repeat );    # same array with repeated values
    my @keys = keys %times;                 # keys of global times hash array

    print join( "\n", @rep_array ), "\n" if $debug2;

    my $d_t     = &block_duration($ar_ref);
    my $d_t_rep = &block_duration( \@rep_array );

    print "block duration = $d_t\n"                  if $debug2;
    print "block duration with repeats = $d_t_rep\n" if $debug2;

    my $conflict = 0;

    foreach my $c ( sort keys %T ) {
        if (
            ( $LOCAL_T >= $c && $LOCAL_T <= $T{$c} )
            || (   ( $LOCAL_T + $d_t_rep ) >= $c
                && ( $LOCAL_T + $d_t_rep ) <= $T{$c} )
            || ( $c >= $LOCAL_T && $T{$c} <= ( $LOCAL_T + $d_t_rep ) )
          )
        {
            $conflict = 1;
        }
    }

    # move until no conflict
  OUTER: while ($conflict) {

        print "conf = $conflict\n"                           if $debug2;
        print "block start\tstarttime\tstoptime\tblockend\n" if $debug2;
        foreach my $c ( sort keys %T ) {

            print print_time_only($c), "\t", print_time_only($LOCAL_T), "\t",
              print_time_only( $LOCAL_T + $d_t_rep ), "\t",
              print_time_only( $T{$c} ), "\n"
              if $debug2;

            if (
                ( $LOCAL_T >= $c && $LOCAL_T <= $T{$c} )
                || (   ( $LOCAL_T + $d_t_rep ) >= $c
                    && ( $LOCAL_T + $d_t_rep ) <= $T{$c} )
                || ( $c >= $LOCAL_T && $T{$c} <= ( $LOCAL_T + $d_t_rep ) )
              )
            {
                $conflict = 1;

#print "insert_block: conflict with\n\t\t",print_time($c),"( block duration ",$d_t_rep," )\n" if $debug;
#print "t-ref was ",$LOCAL_T,"\t",print_time($LOCAL_T),"\n";
                $LOCAL_T += $shift;

                #print "t-ref became ",$LOCAL_T,"\t",print_time($LOCAL_T),"\n";
                next OUTER;
            }
            else {
                $conflict = 0;
            }
        }

    }

    print "conf = $conflict\n" if $debug2;

    # fill %times

    my $lt = $LOCAL_T;    # local time
    foreach my $i (@rep_array) {
        ( my $n, my $delay, my $cmd, my $comment ) = split /\t+/, $i;
#         $times{$lt} = $cmd . ( length($cmd) > 8 ? "\t" : "\t\t" ) . $comment;

        $lt += $delay;
    }

    #$comments{qq($LOCAL_T+3)}="//\n";

    $T{$LOCAL_T} = $lt;

    print "block borders: start= ", print_time($LOCAL_T), "\tstop= ",
      print_time($lt), "\n"
      if $debug2;
    print "block duration = ", $lt - $LOCAL_T, " sec\n" if $debug2;

    $LOCAL_T = $lt;
    
    return $LOCAL_T;

}





exit 0;

