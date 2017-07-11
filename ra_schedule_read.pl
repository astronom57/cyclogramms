# collection of subroutines to read different RadioAstron related schedules:
# BLOCK schedule
# SOGLASNOV-STYLE
# lASER RANGING SESSIONS
# COMMAND SESSIONS
# singledish observations
# etc.

use strict;
use Data::Dumper;


use Getopt::Long;
#use Date::Calc qw(Date_to_Time Delta_Days Time_to_Date Today_and_Now Day_of_Year Add_Delta_DHMS);
use Date::Calc qw(:all);
use List::MoreUtils ();
use Carp;
use Data::Dumper;

our $strict=0;


# read information from SNS_command file
sub read_cmd(){
	my %cmd_status;
	my $cmd_c;my @cmd_err;
	my ($ar_ref,$hash_ref)=@_;
	for my $i(0..$#{$ar_ref}){
		my $l=$$ar_ref[$i];
		$l=~s/\R//g;
		chomp($l);
		if($l=~m/^\s*#/){
			push @cmd_err,"Commented line no. $i skipped: $l";
			next;
		}
		#01.03.2013 8:00:00 - 01.03.2013 11:15:00
		if($l=~m/(\d+\.\d+\.\d+)\s+(\d+:\d+:\d+)\s*-\s*(\d+\.\d+\.\d+)\s+(\d+:\d+:\d+)/){
			my $d1=$1;my $t1=$2;my $d2=$3;my $t2=$4;
			my $start_cmd_sec=Date_to_Time(reverse(split(/\./,$d1)),split(/:/,$t1));
			my $stop_cmd_sec=Date_to_Time(reverse(split(/\./,$d2)),split(/:/,$t2));
			${$hash_ref}{$start_cmd_sec}={"type"=>"sns_cmd","start"=>$start_cmd_sec,"stop"=>$stop_cmd_sec};
			$cmd_c++;
		}
	}

	$cmd_status{'num_c'}=$cmd_c;

	return ($cmd_c,@cmd_err);
	#return (%cmd_status,@cmd_err);

}


# read laser ranging schedule from an array (which is usually contains lines of a file)
# expected format 
# dd.mm.yyyy hh.mm - hh.mm STATION_NAME
# but date could be reveresed (X_X)
# yyyy.mm.dd
# INPUTS: reference to an array with lines $ar_ref, reference to a global hash-of-hashes (hoh) with predefined keys $hash_ref
# OUTPUTS: number of laser ranging sessions read, error message array; hoh modified

sub read_ll(){

	my $ll_c; my @ll_err;
	my ($ar_ref,$hash_ref)=@_;

	for my $i(0..$#{$ar_ref}){
		chomp(${$ar_ref}[$i]);
		${$ar_ref}[$i]=~s/\R//g;
		if(${$ar_ref}[$i]=~m/^\s*#/){
			push @ll_err,"Commented line no. $i skipped: ${$ar_ref}[$i]";
			next;
		}
		${$ar_ref}[$i]=~s/\s+-\s+/ /g;
		my ($date_ll,$start_ll,$stop_ll,$ll_station)=split /\s+/,${$ar_ref}[$i];
		#print "in read_ll date_ll = ",$date_ll,"\n";

		if(!check_d($date_ll)){
			push @ll_err,"Bad date $date_ll, line no. $i skipped: ${$ar_ref}[$i]";
			next;
		}
	
		my @temp=split(/[\.]/,$date_ll);
		my @temp2;
		if($temp[2]>2000){@temp2=reverse(@temp);}
		else{@temp2=@temp;}
		my $start_ll_sec=Date_to_Time(@temp2,split(/:/,$start_ll),0);
		my $stop_ll_sec=Date_to_Time(@temp2,split(/:/,$stop_ll),0);

		$stop_ll_sec+=86400 if $stop_ll_sec<=$start_ll_sec; 	

		${$hash_ref}{$start_ll_sec}={"type"=>"sns_ll","start"=>$start_ll_sec,"stop"=>$stop_ll_sec,"grt"=>$ll_station};
		$ll_c++;
	}

return ($ll_c,@ll_err);


}



# read BLOCK schedule from an array (which usually contains lines of a file)
# expected format 
# .. is too complex to describe, e.g.
#
# Observational code: raes03nc
# GBT project: 12B-262, 13A-252 
# Task: AGN fringe survey
# Start(UT): 28.02.2013 10:00:00
# Stop(UT) : 28.02.2013 10:40:00
# Band: CK
# Pcal: ON, noise diode: ON
# Source: 1641+399
# GRT: Gb(K), Wb(C), Ev(C), Mc(K), Sv(K), Ys(C)
# Comments: 7xED
# Comments: Wb will observe if operators manage to change Mk5 modules
# Comments: central frequency 22228 MHz
#
# Subroutine searches for "observational", "start", "stop", "band", "source", "grt", "comments ... XXxED", "comments central freq 22228"
#
# INPUTS: reference to an array with lines $ar_ref, reference to a global hash-of-hashes (hoh) with predefined keys $hash_ref
# hash of option %opt. 
# OUTPUTS: none, but hoh modified




sub read_block(){

my @block_err=();	# array for error messages output
my @errors=();		# to replace previous one
my @warnings=();
my %block_options=();	# options output

my ($ar_ref,$hash_ref,%opt)=@_;	# inputs
my @block=@{$ar_ref};	# I don't like to use references here
chomp(@block);

my $debug=$strict=0;	# special modes off by default
# $debug=1;
if(exists $opt{'debug'}){$debug=1;}
if(exists $opt{'strict'}){$strict=1;}
my $debug2=0;


my $count=0;
my $obs_c=0;
my @beg_strs=();
my $ver;

# read version
for (my $i=0;$i<=$#block;$i++){
	if($block[$i]=~m/^Version\s+/i){
		$ver = $';
		print $ver,"\n" if $debug ;
		$block_options{'version'}=$ver;
		last;
	}
}


# find line numbers which start single observation description
for (my $i=0;$i<=$#block;$i++){
	if($block[$i]=~m/^observational/i){
		$obs_c++; 
		push @beg_strs,$i;
	}
}


# to mark the end of last observation at the first empty line found after observational code containing line
my $found_last=0;
my $end_last;
for(my $i=$beg_strs[-1];$i<=$#block;$i++){
	if($block[$i]=~m/^\s*$/  or $block[$i]=~m/^[=\*]/){$end_last=$i; $found_last=1;last;}
}
unless($found_last){$end_last=$#block+1;}

push @beg_strs,$end_last;
print "$obs_c observations in this schedule\n" if $debug;
$block_options{'num_i'}=$obs_c;



my @start_obs_sex;
my @stop_obs_sex;


my @baselines;
my @start_d;
my @stop_d;
my @bands;
my @sources;
my @grts;
my @fmodes;
my @switch_num;
my @switch_bands;
my @switch_starts;
my @switch_stops;
my @obscodes;
my @tss;
my @pcals;
my @noises;
my @pas;

my @proposalss;
my @tasks;

###############################################################
# read block schedule file
for(my $s=0;$s<$#beg_strs;$s++){	# loop over observations
	

	print "\n\n\n" if $debug;
	print "String numbers: obs. index=",$s,"\tbeg. str= ",$beg_strs[$s],"\tnext beg. str=",$beg_strs[$s+1],"\n" if $debug;


my $obscode_found=0;
my $start_found =0;	
my  $stop_found=0;	
my  $band_found=0;	
my  $source_found=0;	
my  $grt_found=0;	
my  $baseline_found=0;	
my  $fmode_found=0;	
my $proposals_found=0;
my $task_found =0;


my $band_switch=0;


my $obscode;
my $source;my $grt;
my $alias;
my $band;
	my ($baseline,$band_switch,$pa);
	my ($proposals, $task);
	my $fmode="F3/F3";
	my @sw_start;my @sw_stop; my @sw_bands;
	my $sourcenum=0;
	my $band2use;
my ($stop_date,$stop_time);
my ( $start_date, $start_time);

my ($stop_date_d,$stop_time_d);
my ( $start_date_d, $start_time_d);
my $ts;
my $pcal;
my $noise;

#my @bands;
			my $start_obs_sec;
			my $stop_obs_sec;


	INNER:for(my $i=$beg_strs[$s];$i<=$beg_strs[$s+1]-1;$i++){		# loop over lines in each observation

	my $line=$block[$i];
	$line=~s/\R//g;

		if($line=~m/^#/){next INNER;}	# skip comments

		# Observational code
		if($obscode_found==0 && $line=~m/^observational/i){
			my $code_here=$';
			my $n=$code_here=~m/:/g;
			print "n=",$n,"\n" if $debug2;
			if($n==1){$obscode=$';
				$obscode=~tr/ //d;
				$obscode_found=1;
				print "..$obscode..\n" if $debug2;
				# move to checkable place later
				$count++;
			}
		}	
		elsif($obscode_found==1 && $line=~m/^observational/i){
			die "Observational code string found twice. It is impossible! Exit. \n" if $strict;	
			push @block_err,"Observational code string found twice. Line no. ",$i+1;
			
		}

		# start 	
		if($start_found==0 && $line=~m/^start/i){
			$line=~s/\R//g;
			$line=~tr/A-Za-z()//d; # delete all letters
			$line=~s/^:\s*//;
			$line=~s/\s*\Z//;
			print "--$line--","\n" if $debug2;
			my $n=$line=~m/\s+/g;
			if($n==1){
				( $start_date, $start_time)=split(/\s+/,$line);
			

				print "--$start_date--\n" if $debug2;
				print "==$start_time==\n" if $debug2;
			
				if($start_date!~m/\b\d\d\.\d\d\.\d{4}\b/){
					die "Start date for obscode $obscode looks weird.\n$start_date\nCheck carefully. Line no. ",$i+1,"\nEXIT.\n" if $strict;
					push @block_err,"Start date for obscode $obscode looks weird.\n$start_date Check carefully.";
				}
				if($start_time!~m/\b\d\d:\d\d:[\d\.]+\b/){
					die "Start time for obscode $obscode looks weird.\n$start_time\nCheck carefully. EXIT.\n" if $strict;
					push @block_err,"Start time for obscode $obscode looks weird\n$start_time Check carefully.";
				}
			
				my ($day, $month,$year)=split(/\./,$start_date);
				my ($hour,$min,$sec)=split(/\:/,$start_time);

				# converted to ONBOARD time 		
				my ($year_d,$month_d,$day_d,$hour_d,$min_d,$sec_d)=Add_Delta_DHMS($year,$month,$day, $hour,$min,$sec,0,3,0,0);
				# TIMES	

				$start_obs_sec=Date_to_Time($year_d,$month_d,$day_d,$hour_d,$min_d,$sec_d);
				push @start_obs_sex,$start_obs_sec;
				$start_date_d=sprintf("%02d.%02d.%04d",$day_d,$month_d,$year_d);
				$start_time_d=sprintf("%02d:%02d:%02d",$hour_d,$min_d,$sec_d);
	
				#${$hash_ref}{$start_obs_sec}{'start'}=$start_obs_sec;

				$start_found=1;
			}
			elsif($n!=1){
				die "Start date and time string for obscode $obscode looks weird.\n$line\nCheck carefully. EXIT.\n" if $strict;
				push @block_err,"Start date and time string for obscode $obscode looks weird.\n$line Check carefully.";
			}
		
		}
		elsif($start_found==1 && $line=~m/^start/i){
			die "Start string found twice.\nline:$i\n$block[$i]\nIt is impossible! Exit. \n" if $strict;
			push @block_err,"Start string found twice.\nline:$i\n$block[$i]";
		}


		# Stop
		if($stop_found==0 && $line=~m/^stop/i){
			
			$line=~tr/A-Za-z()//d; # delete all letters
			$line=~s/^\s*:\s*//;
			$line=~s/\s*\Z//;
			print "--$line--","\n" if $debug2;
			my $n=$line=~m/\s+/g;
			if($n==1){($stop_date,$stop_time)=split(/\s+/,$line);
			

				print "--$stop_date--\n" if $debug2;
				print "==$stop_time==\n" if $debug2;
			
				if($stop_date!~m/\b\d\d\.\d\d\.\d{4}\b/){
					die "stop date for obscode $obscode looks weird.\n$stop_date\nCheck carefully. EXIT.\n" if $strict;
					push @block_err,"Stop date for obscode $obscode looks weird.\n$stop_date Check carefully.";
				}
				if($stop_time!~m/\b\d\d:\d\d:[\d\.]+\b/){
					die "stop time for obscode $obscode looks weird.\n$stop_time\nCheck carefully. EXIT.\n" if $strict;
					push @block_err,"Stop time for obscode $obscode looks weird\n$stop_time Check carefully.";
				}
			
				my ($day,$month,$year)=split(/\./,$stop_date);
				my ($hour,$min,$sec)=split(/\:/,$stop_time);

				# converted to ONBOARD time 		
				my ($year_d,$month_d,$day_d,$hour_d,$min_d,$sec_d)=Add_Delta_DHMS($year,$month,$day, $hour,$min,$sec,0,3,0,0);

			$stop_obs_sec=Date_to_Time($year_d,$month_d,$day_d,$hour_d,$min_d,$sec_d);
			push @stop_obs_sex,$stop_obs_sec;

				$stop_date_d=sprintf("%02d.%02d.%04d",$day_d,$month_d,$year_d);
				$stop_time_d=sprintf("%02d:%02d:%02d",$hour_d,$min_d,$sec_d);

			#${$hash_ref}{$start_obs_sec}{'stop'}=$stop_obs_sec;

				$stop_found=1;
			}
			elsif($n!=1){
				die "stop date and time string for obscode $obscode looks weird.\n$line\nCheck carefully. EXIT.\n" if $strict;
				push @block_err,"Stop date and time string for obscode $obscode looks weird.\n$line Check carefully.";
			}
		
		}
		elsif($stop_found==1 && $line=~m/^stop/i){
			die "stop string found twice.\nline:$i\n$block[$i]\nIt is impossible! Exit. \n" if $strict;
			push @block_err,"Stop string found twice.\nline:$i\n$block[$i]";
		}


		# one string date handling

		# 2012.11.20 04:00-04:40 UT
		if($line=~m/(\d+\.\d+\.\d+)\s+(\d+:\d+)\s*\D*\s*-\s*(\d+:\d+)/gi && $stop_found==0 && $start_found==0 ){
			my @d=split(/\./,$1);
			if($d[0]>2000){ # year goes first
				$start_obs_sec=Date_to_Time(@d,split(":",$2),0)+3*3600;	# converted to BShV
				$stop_obs_sec=Date_to_Time(@d,split(":",$3),0)+3*3600;
			}
			elsif($d[2]>2000){ # day goes first
				$start_obs_sec=Date_to_Time(reverse(@d),split(":",$2),0)+3*3600;
				$stop_obs_sec=Date_to_Time(reverse(@d),split(":",$3),0)+3*3600;
			}
			$start_found=1;
			$stop_found=1;
			push @start_obs_sex,$start_obs_sec;
			push @stop_obs_sex,$stop_obs_sec;
		#	${$hash_ref}{$start_obs_sec}{'start'}=$start_obs_sec;
		#	${$hash_ref}{$start_obs_sec}{'stop'}=$stop_obs_sec;
		}
		

		# 2012.11.20 04:00- 2012.11.21 04:40 UT

		if($line=~m/(\d+\.\d+\.\d+)\s+(\d+:\d+)\s*\D*\s*-+\s*(\d+\.\d+\.\d+)\s+(\d+:\d+)/gi && $stop_found==0 && $start_found==0 ){
			my @d1=split(/\./,$1);
			my @d2=split(/\./,$3);

			if($d1[0]>2000){ # year goes first
				$start_obs_sec=Date_to_Time(@d1,split(":",$2),0)+3*3600;
				$stop_obs_sec=Date_to_Time(@d2,split(":",$4),0)+3*3600;
			}
			elsif($d1[2]>2000){ # day goes first
				$start_obs_sec=Date_to_Time(reverse(@d1),split(":",$2),0)+3*3600;
				$stop_obs_sec=Date_to_Time(reverse(@d2),split(":",$4),0)+3*3600;
			}
			$start_found=1;
			$stop_found=1;
			push @start_obs_sex,$start_obs_sec;
			push @stop_obs_sex,$stop_obs_sec;
		#	${$hash_ref}{$start_obs_sec}{'start'}=$start_obs_sec;
		#	${$hash_ref}{$start_obs_sec}{'stop'}=$stop_obs_sec;
		}


		# bands
		if($band_found==0 && $line=~m/^\s*(?:bands\s*:\s+|band\s*:\s+)/i){
			$band=$';
			$band2use=$band;
			my $n=()=$band=~m/[clpk]/ig;
			if($band=~m/,/ && $n>2){$band_switch=$n/2-1;}
			else{$band_switch=0;}

			print "Number of bands used = ",$n,"\n" if $debug;
			# no bands switching
			if($band_switch==0){
				$band=~tr/ :\,;\&//d;
				$band=~s/and//gi;
				$band=~s/\s//g;
				$band2use=$band;
				#print "-$band-\n";
				
				if($band=~m/[^plkc]/i){
					die "Don't understand what BANDs you want: $band\nline $i\n$line\nObscode: $obscode\n" if $strict;
					push @block_err,"Don't understand what BANDs you want: $band\nline $i\n$line\nObscode: $obscode";
				}		
				$band_found=1;
				if(length($band)==1){$band.=$band;}
				

					#	{"type","source","ra","dec","start","stop","ts","ts_bef","ts_aft","grt","bands","baseline","obscode","power","fmode"};

			}
			# bands switching
			elsif($band_switch>0){
				my @bands_switch=split /\s*,\s*/,$band;
				
				for $a(0..$#bands_switch){
					# times only
					#$bands_switch[$a]=~m/([klcp]+)\s*\((\d+:\d+)\s*-*\s*(\d+:\d+)\)/ig;
					# dates and times
#					print  $bands_switch[$a],"\n" ;
					#			bands            beg_date         beg_time          end_date           end_time
					$bands_switch[$a]=~m/([klcp]+)\s*\((\d+\.\d+\.\d+)\s+(\d+:\d+:\d+)\s*-*\s*(\d+\.\d+\.\d+)\s+(\d+:\d+:\d+)\)/ig;

					my	$band;
					my	$beg_date;
					my	$beg_time;
					my	$end_date;
					my	$end_time;





					if($1 and $2 and $3 and $4 and $5){
						$band=$1;
						$beg_date=$2;
						$beg_time=$3;
						$end_date=$4;
						$end_time=$5;
					}
					else{
						#  times only          band         beg_time         end_time
						$bands_switch[$a]=~m/([klcp]+)\s*\((\d+:\d+)\s*-*\s*(\d+:\d+)\)/ig;
						$band=$1;
						$beg_time=$2;
						$end_time=$3;
						$beg_date=$start_date;
						$end_date=$stop_date;

					}
					#print "$obscode band = $band beg_date = $beg_date beg_time = $beg_time  $end_date $end_time\n" if $debug;
					#print "tochka",substr($beg_date,4,1),"\n";

					if(substr($beg_date,4,1) eq "."){$beg_date=join(reverse(split(/\./,$beg_date)));}
					if(substr($end_date,4,1) eq "."){$end_date=join(reverse(split(/\./,$end_date)));}




					print "$obscode band = $band beg_date = $beg_date beg_time = $beg_time  $end_date $end_time\n" if $debug;

					my @tempstarttime=split(/:/,$beg_time);
					if ($#tempstarttime == 1){	# if time in format HH:MM
						push @tempstarttime,"0";
					}
					
					my @tempstoptime=split(/:/,$end_time);
					if ($#tempstoptime == 1){	# if time in format HH:MM
						push @tempstoptime,"0";
					}
					


					print $obscode,"\t",join(" ",reverse(split(/\./,$beg_date)))," @tempstarttime\n" if $debug2;
					
# 					print "$beg_date\n\n\n@tempstarttime\n\n";
					
					my $beg_time_sec=Date_to_Time(reverse(split(/\./,$beg_date)),@tempstarttime)+3*3600;
					my $end_time_sec=Date_to_Time(reverse(split(/\./,$end_date)),@tempstoptime)+3*3600;


					push @sw_bands,$band;
					push @sw_start,$beg_time_sec;
					push @sw_stop,$end_time_sec;
				$band_found=1;
				}

			}

		}



		# added in 2014
		# Pcal: OFF, noise diode: ON

		if ($line=~m/(pcal|noise\s+diode)/i){
		    my $n;
		    $n=$line =~ m/p\-*cal.*?(on|off)/i;
		    if(defined $n){$pcal = uc($1);}
		    $n=$line =~ m/noise\s*diode.*?(on|off)/i;
		    if(defined $n){$noise = uc($1);}
		    		
		}

	
		# Source
	
		if($source_found==0 && $line=~m/^\s*(?:source(\d+)|sources|source)\s*:\s*/i){

			if($1){$sourcenum=$1;}
			
			$source=$';
			chomp $source;
			if($source=~m/\(/){
				$source=~m/([\w\.\+\-]+)\s*\(([\w\s\.\+\-]+)\)/i;
				$source=$1;
				$alias=$2;
			}
			$source=~tr/ //d;
			$alias=~tr/ //d;
			
			#print "SOURCE = ",$source,"\n\n";
			#print "ALIAS = ",$alias,"\n\n";




			$source_found=1;


			if($sourcenum){
				push @block_err,"SOURCE seems to be not the only one in this obs.\nline:$i\n$block[$i]";
			}


		}	
		elsif($source_found==1 && $line=~m/^\s*(?:sources|source)\s*:\s*/i){
			die "SOURCE string found twice.\nline:$i\n$block[$i]\nIt is impossible! Exit. \n" if $strict;	
			push @block_err,"SOURCE string found twice.\nline:$i\n$block[$i]";

		}
	
		# GRT
		if($grt_found==0 && ($line=~m/^grt\s*:\s*/i || $line=~m/^telescop.*?\s*:\s*/i)){
			$grt=$';
			$grt_found=1;
		}
		elsif($grt_found==1 && $line=~m/^grt\s*:\s*/i){
			die "GRT string found twice.\nline:$i\n$block[$i]\nIt is impossible! Exit. \n" if $strict;
			push @block_err,"GRT string found twice.\nline:$i\n$block[$i]";
		}



		# tracking station. In BLOCK SCHEDULE since sep 2013
		if($line=~m/^TS\s*:\s*(PU|GB)/i ){
			$ts=$1;
			print "line=$line\t TS = $ts\n" if $debug;

		}








		# comment : baseline
		if($baseline_found==0 && $line=~m/([\d\.]+)\s*(?:xED|ED|D_Earth|xD_Earth)/i){
			$baseline=$1;
			$baseline_found=1;
			my $n = $line=~m/pa\s*=\+*\s*([\-\.\d]+)/i;
			if($n == 1){$pa=$1;}
			else{$pa=0;}

		}
		elsif($baseline_found==1 && $line=~m/([\d\.]+)\s*(?:xED|ED)/){
			print "Baseline string found twice.\nline:$i\n$block[$i]\nIt is strange! Continue. \n" if $strict;
			push @block_err,"Baseline string found twice.\nline:$i\n$block[$i]\nIt is strange!";
		}


		# 22228 MHz -> F2/F2
		if($line=~m/22228/){
			$fmode="F2/F2";
			push @block_err,"Fmode f2/f2 found, freq = 22228 MHz line: $i. $line";
		}
		if($line=~m/1660/){
			$fmode="F2/F2";
			push @block_err,"Fmode f2/f2 found, freq = 1660 MHz line: $i. $line";
		}
		
		if($line =~m/Proposals\s*\:(.*)$/i){
			$proposals = $1;
			$proposals_found = 1;
		}
		
		if($line =~ m/task\s*\:(.*)$/i){
			$task = $1;
			$task_found=1;
		}
		
		
	}  # INNER

	#print "$obscode $band $source $grt\n", print_time($start_obs_sec),"\n",print_time($stop_obs_sec),"\n" if $debug;
	print "Records found flags: ",$obscode_found, $start_found, $stop_found,$band_found, $source_found, $grt_found,"\n" if $debug;

#	if($obscode_found==1 && $start_found==1 && $stop_found==1 && $band_found==1 && $source_found==1 && $grt_found==1){
	if($obscode_found==1 && $start_found==1 && $stop_found==1 && $band_found==1 && $source_found==1){
	
		print "Seems that all required info about observation is provided.\nNow filliing all arrays.\n" if $debug2;
	

		my  $different_obscodes=0;
		if(List::MoreUtils::any {$_ =~ m/$obscode/i} @obscodes   and  $different_obscodes==1){
		#if(any {$_ eq $obscode} @obscodes){
			my $n=List::MoreUtils::true {$_ =~m/$obscode/i} @obscodes;	# count number ob such obscodes already present in schedule
			push @obscodes,$obscode."==".$n;		# modify obscode name
		}
		else{
			push @obscodes,$obscode;
		}

		push @start_d,$start_date_d." ".$start_time_d;
		push @stop_d , $stop_date_d." ".$stop_time_d;
		push @bands, $band2use;
		push @sources,$source;
		push @grts,$grt;		
		if($baseline){push @baselines,$baseline;}
		else{push @baselines, "0";}
		# before 2012.12.09 01:00:00 F2/F2 formatter regime was default one for all observations except pulsar ones
		if($start_obs_sec < &Date_to_Time(2012,12,9,1,0,0)){
			if($obscode=~m/06/ || $band=~m/P/i){		# for pulsar measurements
				$fmode="F3/F3";
			}
			else{				# for other measurements
				$fmode="F2/F2";
			}

		}
		push @fmodes,$fmode;

		if(defined $ts){
			push @tss,$ts;
		}
		else{
			push @tss,'PU';
		}
		
		push @pcals,$pcal;
		push @noises,$noise;
		push @pas, $pa;
		##
		push @proposalss, $proposals;
		push @tasks, $task;
		##
		
	
		print "Bands switch = ",$band_switch,"\n" if $debug;

		push @switch_num, $band_switch;
		push @switch_bands, [@sw_bands];
		push @switch_starts, [@sw_start];
		push @switch_stops,  [@sw_stop];


		#print "\@switch_num = ",join(" ",@switch_num),"\n";
		#print "    \@sw_bands = ",join(" ",@sw_bands),"\n";
		#print "\@switch_bands = ",join(" ",@{$switch_bands[$s]}),"\n";
		#print "\@switch_starts = ",join(" ",@{$switch_starts[$s]}),"\n";


		if($switch_num[$s]>0){
			for my $sw(0..$switch_num[$s]){
				print "$s $obscode ",$switch_bands[$s][$sw]," $source $grt\n", print_time($switch_starts[$s][$sw]),"\n",print_time($switch_stops[$s][$sw]),"\n" if $debug;
			}
		}
		else{
			print "$s $obscode $band $source $grt\n", print_time($start_obs_sec),"\n",print_time($stop_obs_sec),"\n" if $debug;
		}
		
		
		# popullate @block_err with messages on smth not found;
		unless($proposals_found){push @block_err, "-W: Proposals keyword not found. Obscode = $obscode";}
		unless($task_found){push @block_err, "-W: Task keyword not found. Obscode = $obscode";}
		unless($grt_found){push @block_err, "*E: GRT keyword not found. Obscode = $obscode";}
		
		
		

	}
	else {
		die "Something went wrong (and wasn't captured before) for observation $obscode.\nCannot proceed further. Exit.\n" if $strict;
		push @block_err,"Something went wrong (and wasn't captured before) for observation $obscode.\nCannot proceed further.";
	}

}


my @ras;
my @decs;


# find coordinates
foreach my $s (@sources){

my $ra_found=0;
my $dec_found=0;
INNER2:	for (my $i=$#block;$i>0;$i--){
		my $line=$block[$i];
		if($line=~m/^#/){next INNER2;}	# skip comments
		if($line=~m/^comment/i){next INNER2;}
	
		my $sour=join("\\s*",split("",$s));
		$sour=~s/\+/\\\+/g;	

		if($line=~m/^$sour/i){
			my $coord_here=$';		
			$coord_here=~s/^\s+//;
			my @coord_temp=split(/\s+/,$coord_here);

			$ra_found=0;
			$dec_found=0;
			
			foreach my $p (@coord_temp){
				if($p!~m/\d\d:\d\d:[\d\.]+/){
					print "$p\tthis field appeared not to be RA\n" if $debug2;
				next;}
				my $t;
				if ($p=~m/(\d\d:\d\d:[\d\.]+)/ && $ra_found==0){

						$p=~m/(\d\d:\d\d):([\d\.]+)/;
						$t=sprintf("%s:%09.6f",$1,$2);
						push @ras,$t;
						$ra_found=1;
						#print $1,"\n" if $debug;
				}
				if ($p=~m/([\+-]+\d\d:\d\d:[\d\.]+)/ && $ra_found==1 && $dec_found==0){
						$p=~m/([\+-]+\d\d:\d\d):([\d\.]+)/;
						$t=sprintf("%s:%08.5f",$1,$2);
						push @decs,$t;
						$dec_found=1;
						#print $1,"\n" if $debug;
				}
				if($ra_found && $dec_found){last;}
			}
		}
	}
if(!$ra_found && !$dec_found){push @ras,'00:00:00.00000'; push @decs, '+00:00:00.00000';}

}

for my $i(0..$#sources){
	${$hash_ref}{$start_obs_sex[$i]}={"type"=>"obs","source"=>$sources[$i],"ra"=>$ras[$i],"dec"=>$decs[$i],"start"=>$start_obs_sex[$i],"stop"=>$stop_obs_sex[$i],"ts"=>$tss[$i],"ts_bef"=>0,"ts_aft"=>0,"grt"=>$grts[$i],"bands"=>$bands[$i],"baseline"=>$baselines[$i],"obscode"=>$obscodes[$i],"power"=>0,"fmode"=>$fmodes[$i]};
	${$hash_ref}{$start_obs_sex[$i]}{'bands_num'}=$switch_num[$i];
	${$hash_ref}{$start_obs_sex[$i]}{'bands0'}=${$hash_ref}{$start_obs_sex[$i]}{'bands'};
	${$hash_ref}{$start_obs_sex[$i]}{'start0'}=${$hash_ref}{$start_obs_sex[$i]}{'start'};
	${$hash_ref}{$start_obs_sex[$i]}{'stop0'}=${$hash_ref}{$start_obs_sex[$i]}{'stop'};
	${$hash_ref}{$start_obs_sex[$i]}{'pcal'}=(defined $pcals[$i]?$pcals[$i]:"n/a");
	${$hash_ref}{$start_obs_sex[$i]}{'noise'}=(defined $noises[$i]?$noises[$i]:"n/a");
	${$hash_ref}{$start_obs_sex[$i]}{'pa'}=(defined $pas[$i]?$pas[$i]:0.0);


		for my $j(0..$switch_num[$i]){
			if($switch_bands[$i][$j]){${$hash_ref}{$start_obs_sex[$i]}{'bands'.$j}=$switch_bands[$i][$j];}
			else{${$hash_ref}{$start_obs_sex[$i]}{'bands'.$j}=$bands[$i];}

			if($switch_starts[$i][$j]){${$hash_ref}{$start_obs_sex[$i]}{'start'.$j}=$switch_starts[$i][$j];}
			else{${$hash_ref}{$start_obs_sex[$i]}{'start'.$j}=$start_obs_sex[$i];}

			if($switch_stops[$i][$j]){${$hash_ref}{$start_obs_sex[$i]}{'stop'.$j}=$switch_stops[$i][$j];}
			else{${$hash_ref}{$start_obs_sex[$i]}{'stop'.$j}=$stop_obs_sex[$i];}
		}


		
		
		
}

#	{"type","source","ra","dec","start","stop","ts","ts_bef","ts_aft","grt","bands","baseline","obscode","power","fmode"};



# 	print 	Dumper($hash_ref),"\n\n\n";



return (\%block_options,\@block_err);

}










####################################################### ####################################################### 
####################################################### ####################################################### 
# READ SOGLASNOV-STYLE SCHEDULE
####################################################### ####################################################### 
####################################################### ####################################################### 

sub read_soglasnov(){

my %srt_options=();
my @srt_err=();
my $count_l;
my $count_s;
my $count;
my $count_o;
my $count_j;
my $num_of_correct=0;
my @beg_strs=my @beg_strs_sns=my @beg_strs_ll=();
my ($ar_ref,$hash_ref, %opt)=@_;

my $debug=my $strict=my $combine=0;	# special modes off by default
if(exists $opt{'debug'}){$debug=1;}
if(exists $opt{'strict'}){$strict=1;}
if(exists $opt{'combine'}){$combine=1;}

$debug =0;

my @f=@{$ar_ref};
chomp(@f);


	for(my $index=0;$index<=$#f+1;$index++){
		if($f[$index]=~m/observation/i){push @beg_strs,$index; $count++;$count_o++;}
		elsif($f[$index]=~m/JUSTIROVKA/i){push @beg_strs,$index; $count++;$count_j++;}
		elsif($f[$index]=~m/sns_command/i){push @beg_strs_sns,$index; $count_s++;}
		elsif($f[$index]=~m/sns_ll/i){push @beg_strs_ll,$index; $count_l++;}
	}
	
	
# 	carp Dumper(\@beg_strs);
# 	carp Dumper(\@beg_strs_sns);

	
$srt_options{'num_a'}=$count;		# all
$srt_options{'num_i'}=$count_o;		# interferometric observations
$srt_options{'num_j'}=$count_j;		# justirovka
$srt_options{'num_c'}=$count_s;		# command sessions
$srt_options{'num_l'}=$count_l;		# laser ranging sessions





# print "beg_strs[-1]  = ", $beg_strs[-1],"\n\n";



# what is the last line of the last observation
# temp = first string of last cmd session , first line of the last obs|just , first line of last ll
my @temp=((defined $beg_strs_sns[-1]?$beg_strs_sns[-1]:0),(defined $beg_strs[-1]?$beg_strs[-1]:0),(defined $beg_strs_ll[-1]?$beg_strs_ll[-1]:0));

# print Dumper(\@temp);



@temp=sort {$a<=>$b} @temp;
if($beg_strs[-1] == $temp[0]){push @beg_strs,$temp[1];}
elsif($beg_strs[-1] == $temp[1]){push @beg_strs,$temp[2];}
elsif($beg_strs[-1] == $temp[2]){push @beg_strs,$#f+1;}


# print Dumper(\@temp);
# carp Dumper(\@beg_strs);


# SNS command
if($count_s){


	# loop over all command sessions
	for(my $s=0;$s<=$#beg_strs_sns;$s++){
	my $start_found=my $stop_found=0;

my $start_cmd_sec;
my $stop_cmd_sec;

	# loop over lines
	for(my $index=$beg_strs_sns[$s];$index<$beg_strs_sns[$s]+3;$index++){

		my $line=$f[$index];
		$line=~s/\R//g;
	

		if($line=~m/^start\s*=\s*/i && $start_found==0){
			$line=~tr/a-zA-Z=//d;
			$line=~s/^\s+//;
			my ($d,$t)=split(/\s+/,$line);
			if (&check_d($d) && &check_t($t)){
				#$start=$d." ".$t;
				#print "SNS_COMMAND in the end START = $start\n";
				$start_found=1;
				$start_cmd_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
				#print "global stop sec = $global_stop_sec\n";
			}
			else{
				die "Do not understand a line where start date and time should be.\nline:  ",($index+1),"\nEXIT.\n" if $strict;
				push @srt_err, "Do not understand a line where CMD start date and time should be. line: ",($index+1);
				
			}
		}
		if($line=~m/^stop\s*=\s*/i && $stop_found==0){
			$line=~tr/a-zA-Z=//d;
			$line=~s/^\s+//;
			my ($d,$t)=split(/\s+/,$line);
			if (&check_d($d) && &check_t($t)){
				#$stop=$d." ".$t;
				#print "SNS_COMMAND in the beginning STOP = $stop\n";
				$stop_found=1;
				$stop_cmd_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
				#print "global start sec = $global_start_sec\n";
			}
			else{
				die "Do not understand a line where stop date and time should be.\nline:  ",($index+1),"\nEXIT.\n" if $strict;
				push @srt_err, "Do not understand a line where CMD stop date and time should be. line: ",($index+1);
			}
		}
	}
	${$hash_ref}{$start_cmd_sec}={"type"=>"sns_cmd","start"=>$start_cmd_sec,"stop"=>$stop_cmd_sec};
	}
}

# SNS LL
if($count_l){



	for(my $s=0;$s<=$#beg_strs_ll;$s++){
	my $start_found=my $stop_found=my $grt_found=0;
	my $grt;
		my $start_ll_sec;
		my $stop_ll_sec;
	for(my $index=$beg_strs_ll[$s];$index<$beg_strs_ll[$s]+4;$index++){




		my $line=$f[$index];
		$line=~s/\R//g;
	
		if($line=~m/^start\s*=\s*/i && $start_found==0){
			$line=~tr/a-zA-Z=//d;
			$line=~s/^\s+//;
			my ($d,$t)=split(/\s+/,$line);
			if (&check_d($d) && &check_t($t)){
				my $start=$d." ".$t;
				$start_found=1;
				$start_ll_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
			}
			else{
				die "Do not understand a line where start date and time should be.\nline:  ",($index+1),"\nEXIT.\n" if $strict;
				push @srt_err, "Do not understand a line where LL start date and time should be. line: ",($index+1);
			}
		}
		if($line=~m/^stop\s*=\s*/i && $stop_found==0){
			$line=~tr/a-zA-Z=//d;
			$line=~s/^\s+//;
			my ($d,$t)=split(/\s+/,$line);
			if (&check_d($d) && &check_t($t)){
				my $stop=$d." ".$t;
				$stop_found=1;
				$stop_ll_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
			}
			else{
				die "Do not understand a line where stop date and time should be.\nline:  ",($index+1),"\nEXIT.\n" if $strict;
				push @srt_err, "Do not understand a line where LL stop date and time should be. line: ", ($index+1);
			}
		}

		# GRT
		if($line=~m/^grt\s*=\s*/i){
			$grt=$';
			$grt_found=1;
		}

	}
	${$hash_ref}{$start_ll_sec}={"type"=>"sns_ll","start"=>$start_ll_sec,"stop"=>$stop_ll_sec,"grt"=>$grt};
	}

}#if






# carp Dumper($hash_ref);





# OBservations and justirovkas
for(my $s=0;$s<$#beg_strs;$s++){

# nothing found yet
my $cfreq_found=my $beginscan_found=my $obs_type_found=my $ts_found=my $obscode_found=my $start_found=my $stop_found=my $band_found=my $source_found=my $grt_found=my $baseline_found=my $ra_found=my $dec_found=my $epoch_found=my $power_found=my $fmode_found=0;
my $var_found=my $endscan_found;

my $obs_type;
my ($ra,$dec);
my $band_switch;
my @sw_bands=my @sw_start=my @sw_stop=();
my $fmode="F3/F3";
my $power;

my $band=my $beg_time_sec=my $end_time_sec=0;
my $source;
my $alias;
my $var;
my $obscode;
my $start; my $stop;
my $start_sec;
my $stop_sec;
my $beginscan;
my $endscan;
my $beginscan_sec;
my $endscan_sec;
my $ts_bef;
my $ts_aft;
my $ts_mode;
my $ts_bef_sec;
my $ts_aft_sec;
my $ts;
my $b1;
my $b2;
my $grt;
my $baseline;
my $cfreq1;
my $cfreq2;
my $ts_string;
my $pa;



my @obs_types;
my @obscodes;
my @sources;
my @ras;
my @decs;
my @start_ts;
my @stop_ts;
my @tss;
my @before_time_sex;
my @after_time_sex;
my @freqs;
my @freq1s;
my @freq2s;
my @beginscan_secs;
my @endscan_secs;
my @vars;
my @regim40;
my @fmodes;
my @cfreqs1;
my @cfreqs2;
my @ts_modes;
my @ts_strings;








#INNER:for(my $index=$beg_strs[$s];$index<(($beg_strs[$s+1]-1)<($beg_strs[$s]+13)?$beg_strs[$s+1]-1:($beg_strs[$s]+13));$index++){
INNER:for(my $index=$beg_strs[$s];$index<( defined $beg_strs[$s+1] ? $beg_strs[$s+1]-1 :  $beg_strs_sns[-1]  );$index++){
	my $line=$f[$index];
	chomp($line);
	$line=~s/\R//g;
	if($line=~m/^\//){next INNER;}




	# observation
	if($line=~m/observation/i && $source_found==0){
		$obs_type="i";
		#	print "\n\n\n obs_type= $obs_type\n\n\n";
		$index++;		# next line
		$line=$f[$index];
		chomp($line);
		my @l=split(/\s+/,$line);
		if($l[1]=~m/\d\d:\d\d:[\d\.]+/ && $l[2]=~m/[\+-]\d\d:\d\d:[\d\.]+/ && $source_found==0){
			# [0] - source name, [1] - RA, [2] - DEC, [3]- Epoch
			$source=$l[0];
			$ra=$l[1];
			$dec=$l[2];
			$source_found=1;
		}

		elsif($line=~m/[\(\)]/i && $source_found==0){
			# [0]- source name,[1] - alias,  [2] - RA, [3] - DEC, [4]- Epoch
#print "LINE=",$line,"\n";
			$line=~s/\(([\w\s\.]*?)\)//i;
			$alias=$1;

#print "$index ALIAS = $alias\n";
		#	$line=~s/\(\w+?\)//ig;


			@l=split(/\s+/,$line);		
			$source=$l[0];
			$ra=$l[1];
			$dec=$l[2];
			$source_found=1;
		}
		
		elsif($l[2]=~m/\d\d:\d\d:[\d\.]+/ && $l[3]=~m/[\+-]\d\d:\d\d:[\d\.]+/ && $source_found==0){
			# [0] [1] - source name, [2] - RA, [3] - DEC, [4]- Epoch
			$source=$l[0]." ".$l[1];
			$ra=$l[2];
			$dec=$l[3];
			$source_found=1;
		}
		else {
			die "Do not understand a line where source name and coordinates should be.\nline:  ",($index+1),"\nEXIT\n" if $strict;
			push @srt_err, "Do not understand a line where source name and coordinates should be. line: ".($index+1);
		}
	}



	# Justirovka
	if($line=~m/JUSTIROVKA/i){


		$obs_type="j";
		#print "\n\n\n obs_type= $obs_type\n\n\n";
		#read next line to find source with its coordinates
		$index++;		# next line
		$line=$f[$index];
		chomp($line);
		my @l=split(/\s+/,$line);
		if($l[1]=~m/\d\d:\d\d:[\d\.]+/ && $l[2]=~m/[\+-]\d\d:\d\d:[\d\.]+/ && $source_found==0){
			# [0] - source name, [1] - RA, [2] - DEC, [3]- Epoch
			$source=$l[0];
			$ra=$l[1];
			$dec=$l[2];
			$source_found=1;
		}
		elsif($l[2]=~m/\d\d:\d\d:[\d\.]+/ && $l[3]=~m/[\+-]\d\d:\d\d:[\d\.]+/ && $source_found==0){
			# [0] [1] - source name, [2] - RA, [3] - DEC, [4]- Epoch
			$source=$l[0]." ".$l[1];
			$ra=$l[2];
			$dec=$l[3];
			$source_found=1;
		}
		else {
			die "Do not understand a line where source name and coordinates should be.\nline:  ",($index+1),"\nEXIT\n"  if $strict;
			push @srt_err, "Do not understand a line where source name and coordinates should be. line: ".($index+1);
		}
	
		# read justirovka variant
		$index++;		# next line
		$line=$f[$index];
		$line=~s/\R//i;
		$var=$line;
		chomp($var);
		$var=~tr/a-zA-Z //d;
		#print "var = ++$var---\n";
		$var_found=1;
	}	




	# start time
	if($line=~m/^start/i && $start_found==0){
		$line=~tr/a-zA-Z=//d;
		$line=~s/^\s+//;
		my ($d,$t)=split(/\s+/,$line);
		if (&check_d($d) && &check_t($t)){
			$start=$d." ".$t;
			$start_found=1;
			$start_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
								
		}
		else{
			die "Do not understand a line where start date and time should be.\nline:  ",($index+1),"\nEXIT.\n" if $strict;
			push @srt_err, "Do not understand a line where start date and time should be. line: ".($index+1);
		}
	}



	# stop time
	if($line=~m/^stop/i && $stop_found==0){
		$line=~tr/a-zA-Z=//d;
		$line=~s/^\s+//;
		my ($d,$t)=split(/\s+/,$line);
		if (&check_d($d) && &check_t($t)){
			$stop=$d." ".$t;
			$stop_found=1;
			$stop_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
								
		}
		else{
			die "Do not understand a line where stop date and time should be.\nline:  ",($index+1),"\nEXIT.\n" if $strict;
			 push @srt_err, "Do not understand a line where stop date and time should be. line: ".($index+1);
		}
	}



	# beginscan for justirovka
	if($line=~m/^beginscan\s*=\s*/i && $beginscan_found==0){
				
# 		print "\nCAPTURED beginscan\n\n" if $debug;
		if($obs_type ne "j"){
			die "beginscan found for non justirovka.\n$line\nline:  ",($index+1),"\nEXIT\n" if $strict;
			push @srt_err, "Beginscan found for non justirovka. line: ".($index+1);
		}		
		
		my $t1=$';
		my ($d,$t)=split(/\s+/,$t1);
		#print "d= $d\nt=$t\n";
		if (&check_d($d) && &check_t($t)){
			$beginscan=$d." ".$t;
			$beginscan_found=1;
			$beginscan_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
		}
	}



	# endscan for justirovka
	if($line=~m/^endscan\s*=\s*/i && $endscan_found==0){
				
		print "\nCAPTURED endscan\n\n" if $debug;
# 		die;
		if($obs_type ne "j"){
			die "end found for non justirovka.\n$line\nline:  ",($index+1),"\nEXIT\n" if $strict;
			push @srt_err, "Endscan found for non justirovka. line: ".($index+1);
		}		
		
		my $t1=$';
		my ($d,$t)=split(/\s+/,$t1);
		#print "d= $d\nt=$t\n";
		if (&check_d($d) && &check_t($t)){
			$endscan=$d." ".$t;
			$endscan_found=1;
			$endscan_sec=Date_to_Time(reverse(split(/\./,$d)),split(/:/,$t));
		}
	}



	# tracking station
	if($line=~m/^TS\s*=\s*/ && $ts_found==0 && $stop_found==1 && $start_found==1){
		$ts_string = $';
		($ts,$ts_bef,$ts_aft, $ts_mode)=split(/\s+/,$');
		if($ts_mode =~m/(?:push_ts|gb_ts)/i){
		  push @srt_err, "Multiple TS. Stereo session?? line: ". ($index+1);
		  $ts_mode = "HM";
		}
		if((!defined $ts_mode or $ts_mode =~m/^$/) and $obs_type eq "i" ){
		  push @srt_err, "No ts_mode information. Old schedule?? line: ". ($index+1);
		  $ts_mode = "HM";
		}
		$ts_mode = uc($ts_mode);
			
				
		my $tmp_ts = $ts;
		$tmp_ts=~s/\s//g;
		if ($tmp_ts eq "" and $obs_type eq "i"){
			$ts=0;
			push @srt_err, "TS string is empty. line: ". ($index+1);			
		}
	
		$ts_found=1;
		$ts_bef_sec=$start_sec+$ts_bef*60;
		$ts_aft_sec=$stop_sec+$ts_aft*60;
	}



	# bands
	if($line=~m/PRM\s*=\s*/ && $band_found==0){

			$band=$';
			chomp($band);

			# avoid CK (6+1.35cm) style
			# but not exclude times in brackets


			if($band=~m/[\(\)]/){	# if () found
				my @tmp=$band=~m/(\(.*?\))/ig;

				foreach(@tmp){
					if ($_=~m/cm|\+/i){
						$band=~s/\Q$_\E//i;
					}
				}
				print "new band = ",$band,"\n" if $debug;

			}


			#$band=~s/\s+//g;
			$b=$band;
			
			# added 2017-02-09 to trap the '--'
# 			if($band eq "--"){die "PRM =  '--'\n";}
			
			my $n=()=$band=~m/[clpk]/ig;
			if($band=~m/,/ && $n>2){$band_switch=$n/2-1;}
			else{$band_switch=0;}

			print $n,"\n" if $debug;
			# no bands switching
			if($band_switch==0){
				$band=~tr/ :,;&//d;
				$band=~s/and//gi;
				if($band=~m/[^plkc\-\+0-4]/i){
					die "Don't understand what BANDs you want: $band\nline $index\n$line\nObscode: $obscode\n" if $strict;
					push @srt_err,"Don't understand what BANDs you want: $band\nline: ",($index+1),"\n$line\nObscode: $obscode";
				}		
				$band_found=1;

				$b1=substr($b,0,1)."1";
				$b2=substr($b,1,1)."2";

				push @sw_bands,$band;
				push @sw_start,$start_sec;
				push @sw_stop,$stop_sec;



				#	{"type","source","ra","dec","start","stop","ts","ts_bef","ts_aft","grt","bands","baseline","obscode","power","fmode"};

			}


			# bands switching
			elsif($band_switch>0){
				my @bands_switch=split /\s*\,\s*/,$band;
				my $debug=0;
				print "BAND SWITCHING = ",$band_switch,"\n" if $debug;
				push @srt_err, "Band switching detected. line: ".($index+1);

				for my $a(0..$#bands_switch){
					# dates and times
					print  $bands_switch[$a],"\n" if $debug;
					#			bands            beg_date         beg_time          end_date           end_time
					$bands_switch[$a]=~m/([klcp\-\+0-4]+)\s*\((\d+\.\d+\.\d+)\s+(\d+:\d+:\d+)\s*-*\s*(\d+\.\d+\.\d+)\s+(\d+:\d+:\d+)\)/ig;
					my $band=$1;
					my $beg_date=$2;
					my $beg_time=$3;
					my $end_date=$4;
					my $end_time=$5;
					print "band=$band bd=$beg_date bt=$beg_time  ed=$end_date et=$end_time\n" if $debug;
		

					my @tempstarttime=split(/:/,$beg_time);
					if ($#tempstarttime == 1){	# if time in format HH:MM
						push @tempstarttime,"0";
					}
					
					my @tempstoptime=split(/:/,$end_time);
					if ($#tempstoptime == 1){	# if time in format HH:MM
						push @tempstoptime,"0";
					}
					

					my $beg_time_sec=Date_to_Time(reverse(split(/\./,$beg_date)),@tempstarttime);
					my $end_time_sec=Date_to_Time(reverse(split(/\./,$end_date)),@tempstoptime);

					print "here in band determination routine  ",print_time($beg_time_sec), "  " ,print_time($end_time_sec),"\n" if $debug;
					push @sw_bands,$band;
					push @sw_start,$beg_time_sec;
					push @sw_stop,$end_time_sec;
					$band_found=1;
				}

			}

		}



	# obscode
	if($line=~m/obscode\s*=\s*/i && $obscode_found==0){
		$obscode=$';
		$obscode=~tr/ //d;
		$obscode_found=1;
	}



	# power
	if($line=~m/power\s*=\s*/i && $power_found==0){
		$power=$';
		#$power=~tr/a-zA-Z //d;
		$power=~m/([40]+)/;
		$power=$1;
		$power_found=1;
	}	



	# fmode
	if($line=~m/fmode\s*=\s*/i && $fmode_found==0){
		my $t1=$';
		if($t1=~m/2/){$fmode="f2/f2"; $fmode_found=1;}
		elsif($t1=~m/3/){$fmode="f3/f3"; $fmode_found=1;}
		else{
			die "Unknown formatter regime.\n$t1\nEXIT.\n" if $strict;
			push @srt_err, "Unknown formatter regime: $t1. line: ".($index+1);
		}
	}


	# GRT
	if($line=~m/^grt\s*=\s*/i){
		my $g=$';
		chomp($g);
		if ($g =~ m/^$/ and $obs_type eq "i" and $source ne "home"){
			$grt=0;
			push @srt_err, "GRT string is empty. line: ".($index+1);
		}
		else{
			$grt=$g;
		}
		$grt_found=1;
	}

	
	# CFREQ
	# i.e. CFREQ = 4836 22236
	if($line=~m/^cfreq\s*=\s*/i){
		my $cf=$';
		chomp($cf);
		if ($cf eq ""){
			$cfreq1=0;
			$cfreq2=0;
			push @srt_err, "CFREQ string is empty. line: ".($index+1);
		}
		else{
			($cfreq1, $cfreq2) = split(/\s+/,$cf)
		}
		$cfreq_found=1;
	}



	# baseline
	if($line=~m/^\s*baseline\s*=\s*/i){
	
		$line=~m/^\s*baseline\s*=\s*([\d\.]+)\s*(?:xED|ED|D_Earth|xD_Earth)/i;	
		$baseline=$1;
		if($baseline eq ""){$baseline =0; }
		my $n = $line=~m/pa\s*=\+*\s*([\-\.\d]+)/i;
		if($n == 1){$pa=$1;}
		else{$pa=0;}
	
	
	
	}
	
	
}







print "
obscode_found = $obscode_found
start_found = $start_found
stop_found = $stop_found
band_found = $band_found
ts_found = $ts_found
power_found = $power_found
fmode_found = $fmode_found
var_found = $var_found
beginscan_found = $beginscan_found
endscan_found = $endscan_found
cfreq_found = $cfreq_found\n" if $debug;

#	if($obs_type eq "i" && $obscode_found && $start_found && $stop_found && $ts_found && $band_found && $power_found && $fmode_found){
	if($obs_type eq "i" && $start_found && $stop_found && $ts_found && $band_found){

print "I'm in strict mode somewhy\n" if ($strict and $debug);


		print "
Obscode=$obscode
start=$start
stop =$stop
PRM = $b
TS = $ts $ts_bef $ts_aft
power = $power
fmode = $fmode
source=$source
cfreq1 = $cfreq1
cfreq2 = $cfreq2
\n" if $debug;

		# FILL ARRAYS
		push @obs_types,$obs_type;
		if($obscode=~m/^$/){
			push @srt_err, "obscode = test, read value of obscode = -$obscode-";
			$obscode='test';
		}	
		push @obscodes,$obscode;
		push @sources,$source;
		push @ras,$ra;
		push @decs,$dec;
		push @start_ts,$start_sec;
		push @stop_ts,$stop_sec;
		push @tss,$ts;
		push @before_time_sex,$ts_bef_sec;
		push @after_time_sex,$ts_aft_sec;
		push @freqs,lc($b);
		push @freq1s,lc($b1);
		push @freq2s,lc($b2);
		push @cfreqs1, $cfreq1;
		push @cfreqs2, $cfreq2;
		push @ts_modes, $ts_mode;
		push @ts_strings, $ts_string;
		
		
		#
		push @beginscan_secs,0;
		push @endscan_secs,0;
		push @vars,0;
		#@ts_start=Time_to_Date($ts_bef_sec);
		#@ts_stop=Time_to_Date($ts_aft_sec);
		my $start_t_print=&print_time($start_sec);
		my $stop_t_print=&print_time($stop_sec);


		if($strict && $power_found && $fmode_found && $obscode_found){
			$num_of_correct++;
			push @regim40, $power;
			push @fmodes,$fmode;
		}
		elsif($strict && (!$power_found || !$fmode_found || !$obscode_found)){
			push @regim40, $power;
			push @fmodes,$fmode;
		}
		elsif(!$strict){
			$num_of_correct++;
			push @regim40, $power;
			push @fmodes,$fmode;
		}
		if(!defined $baseline){$baseline=0;}
		${$hash_ref}{$start_sec}={"type"=>"obs",
		"source"=>$source,"ra"=>$ra,"dec"=>$dec,
		"start"=>$start_sec,"stop"=>$stop_sec,
		"ts"=>$ts,"ts_bef"=>$ts_bef,"ts_aft"=>$ts_aft, "ts_mode"=>$ts_mode, "ts_string"=>$ts_string,
		"grt"=>$grt,"bands"=>$b,"baseline"=>$baseline,
		"obscode"=>$obscode,
		"power"=>$power,"fmode"=>$fmode, 
		"cfreq1"=>$cfreq1, "cfreq2"=>$cfreq2};

		${$hash_ref}{$start_sec}{'bands_num'}=$band_switch;
#print "band_switch = ",$band_switch,"\n";
#print "sw_bands: @sw_bands\n";
#print "sw_start: @sw_start\n";
#print "sw start: ",print_time($sw_start[0])," ",print_time($sw_start[1]),"\n";
#print "sw_stop: @sw_stop\n";
#print "sw stop: ",print_time($sw_stop[0])," ",print_time($sw_stop[1]),"\n";

		for my $j(0..$band_switch){
			if($sw_bands[$j]){${$hash_ref}{$start_sec}{'bands'.$j}=$sw_bands[$j];}
			if($sw_start[$j]){${$hash_ref}{$start_sec}{'start'.$j}=$sw_start[$j];}
			if($sw_stop[$j]){${$hash_ref}{$start_sec}{'stop'.$j}=$sw_stop[$j];}
		}
	}
	elsif($obs_type eq "j" && $var_found && $start_found && $stop_found && ($beginscan_found or $var ==0) && $band_found ){

		$num_of_correct++;
# $debug =1;
		print "Obscode=justirovka
		var$var
		start=$start
		stop =$stop
		beginscan= $beginscan
		endscan=$endscan
		PRM = $b
		source=$source
		power = $power
		TS = $ts
		fmode=$fmode\n" if $debug;

	# FILL ARRAYS
		push @obs_types,$obs_type;

		push @sources,$source;
		push @ras,$ra;
		push @decs,$dec;
		
		#push @start_ts,$beginscan_sec;
		push @start_ts,$start_sec;

######### unneded after may 2013
		if($var==1){
			push @stop_ts,$beginscan_sec+3600+42*60; #1h 42m
		}
		elsif($var==2){
			push @stop_ts,$beginscan_sec+47*60; #47m
		}
		elsif($var==3){
			push @stop_ts,$beginscan_sec+3600+45*60; # 1h 45m
		}
		elsif($var==4){
			push @stop_ts,$beginscan_sec+3600+25*60; # 1h 25m
		}
		else{
			push @stop_ts,$stop_sec; #
		}
##############

		push @stop_ts,$stop_sec;
#		push @stop_ts,$endscan_sec;
		

		push @beginscan_secs,$beginscan_sec;
		push @endscan_secs,$endscan_sec;
		push @vars,$var;
		
		if($ts){
			push @tss,$ts;
# 			push @ts_modes ,$ts_mode;
			push @before_time_sex,$ts_bef_sec;
			push @after_time_sex,$ts_aft_sec;
			push @regim40, $power;
			push @fmodes,$fmode;
			push @obscodes,(defined $obscode ? $obscode : "just_virk" );
		}
		else{
			push @obscodes,(defined $obscode ? $obscode : "just" );
			push @tss,0;
			push @before_time_sex,$start_sec;
			push @after_time_sex,$stop_sec;
			push @regim40, 0;
			push @fmodes,0
		}
		push @freqs,lc($b);
		push @freq1s,lc($b1);
		push @freq2s,lc($b2);

		#@ts_start=Time_to_Date($ts_bef_sec);
		#@ts_stop=Time_to_Date($ts_aft_sec);
		#@beg_scan=Time_to_Date($beginscan_sec);
		#@end_scan=Time_to_Date($beginscan_sec);

#		my $start_t_print=&print_time($beginscan_sec);
		my $start_t_print=&print_time($start_sec);
		my $stop_t_print=&print_time($stop_sec);
		my $beginscan_t_print=&print_time($beginscan_sec);
		#$chasti{qq($beginscan_sec)}="//JUSTIROVKA\n//$source $ra\t$dec\n//start= $start_t_print\n//stop = $stop_t_print\n//Beginscan = $beginscan_t_print\n//PRM=".uc($b)."\n"."//\n";

		$stop_t_print=&print_time($stop_ts[-1]);


		#$comments{qq($beginscan_sec)}=sprintf ("//\n// Justirovka on source %s. Bands: %s. Beginscan %02d.%02d.%02d at %02d:%02d:%02d. Stop %s\n//\n",$source, uc($b), $beg_scan[2],$beg_scan[1],$beg_scan[0],$beg_scan[3],$beg_scan[4],$beg_scan[5],$stop_t_print);
		if(!defined $baseline){$baseline=0;}



		if(!$ts){
			${$hash_ref}{$start_sec}={"type"=>"just",     "source"=>$source,"ra"=>$ra,"dec"=>$dec,"start"=>$start_sec,"stop"=>$stop_sec,"ts"=>$ts,"ts_bef"=>$ts_bef,"ts_aft"=>$ts_aft,"grt"=>$grt,"bands"=>$b,"baseline"=>$baseline,"obscode"=>$obscode,"power"=>$power,"fmode"=>$fmode,'var'=>$var,"beginscan"=> $beginscan_sec,"endscan"=> $endscan_sec};
		}
		else{
		
# 			print Dumper($obscode);
		
			${$hash_ref}{$start_sec}={"type"=>"just_virk","source"=>$source,"ra"=>$ra,"dec"=>$dec,"start"=>$start_sec,"stop"=>$stop_sec,"ts"=>$ts,"ts_bef"=>$ts_bef,"ts_aft"=>$ts_aft,"grt"=>$grt,"bands"=>$b,"baseline"=>$baseline,"obscode"=>$obscode,"power"=>$power,"fmode"=>$fmode,'var'=>$var,"beginscan"=> $beginscan_sec,"endscan"=> $endscan_sec};
			
# 			print Dumper(${$hash_ref}{$start_sec});
			
		}
		${$hash_ref}{$start_sec}{'bands_num'}=$band_switch;

		for my $j(0..$band_switch){
			if($sw_bands[$j]){${$hash_ref}{$start_sec}{'bands'.$j}=$sw_bands[$j];}
			if($sw_start[$j]){${$hash_ref}{$start_sec}{'start'.$j}=$sw_start[$j];}
			if($sw_stop[$j]){${$hash_ref}{$start_sec}{'stop'.$j}=$sw_stop[$j];}
		}


		# TODO:add chasti and comments for VIRK  justirovkas

	}
	
	
}












print "count_o = $count_o
count_j = $count_j
count = $count
num_of_correct= $num_of_correct\n" if $debug;

# $debug=1;
if($debug){

foreach my $i (sort keys %$hash_ref){

if($$hash_ref{$i}{'type'} eq 'obs'){
print uc($$hash_ref{$i}{'type'})," ", $$hash_ref{$i}{'var'}," ",  $$hash_ref{$i}{'obscode'}," ",  $$hash_ref{$i}{'source'}," ",  $$hash_ref{$i}{'ra'}," ",  $$hash_ref{$i}{'dec'},"
start = ", print_time($$hash_ref{$i}{'start'})," ",  print_time($$hash_ref{$i}{'stop'}),"
ts = ",  $$hash_ref{$i}{'ts'}," ",  $$hash_ref{$i}{'ts_bef'}," ",  $$hash_ref{$i}{'ts_aft'},"  ",  $$hash_ref{$i}{'ts_mode'},"
power = ",  $$hash_ref{$i}{'power'}," ",  $$hash_ref{$i}{'fmode'},"
prm = ",  $$hash_ref{$i}{'bands'},"  ",$$hash_ref{$i}{'cfreq1'} ," ",$$hash_ref{$i}{'cfreq2'},"\n\n";
}

if($$hash_ref{$i}{'type'} eq 'sns_ll'){
print $$hash_ref{$i}{'type'},"
start = ", print_time($$hash_ref{$i}{'start'})," ",  print_time($$hash_ref{$i}{'stop'}),"
grt = ",  $$hash_ref{$i}{'grt'},"\n\n";
}


if($$hash_ref{$i}{'type'} eq 'sns_cmd'){
print $$hash_ref{$i}{'type'},"
start = ", print_time($$hash_ref{$i}{'start'})," ",  print_time($$hash_ref{$i}{'stop'}),"\n\n";
}


if($$hash_ref{$i}{'type'} eq 'just'){
print $$hash_ref{$i}{'type'}," ", $$hash_ref{$i}{'var'}," ",  $$hash_ref{$i}{'obscode'}," ",  $$hash_ref{$i}{'source'}," ",  $$hash_ref{$i}{'ra'}," ",  $$hash_ref{$i}{'dec'},"
start = ", print_time($$hash_ref{$i}{'start'})," ",  print_time($$hash_ref{$i}{'stop'}),"
beginscan = ", print_time($$hash_ref{$i}{'beginscan'}),"
endscan = ",  print_time($$hash_ref{$i}{'endscan'}),"
prm = ",  $$hash_ref{$i}{'bands'},"\n\n";
}


if($$hash_ref{$i}{'type'} eq 'just_virk'){
print $$hash_ref{$i}{'type'}," ", $$hash_ref{$i}{'var'}," ",  $$hash_ref{$i}{'obscode'}," ",  $$hash_ref{$i}{'source'}," ",  $$hash_ref{$i}{'ra'}," ",  $$hash_ref{$i}{'dec'},"
start = ", print_time($$hash_ref{$i}{'start'})," ",  print_time($$hash_ref{$i}{'stop'}),"
beginscan = ", print_time($$hash_ref{$i}{'beginscan'}),"
endscan = ",  print_time($$hash_ref{$i}{'endscan'}),"
ts = ",  $$hash_ref{$i}{'ts'}," ",  $$hash_ref{$i}{'ts_bef'}," ",  $$hash_ref{$i}{'ts_aft'},"
power = ",  $$hash_ref{$i}{'power'}," , ",  $$hash_ref{$i}{'fmode'},"
prm = ",  $$hash_ref{$i}{'bands'},"\n\n";
}


}









#	for(my $i=0;$i<=$#obs_types;$i++){
#	print "$obs_types[$i] $vars[$i] $obscodes[$i] $sources[$i] $ras[$i] $decs[$i]
#	start = $start_ts[$i] stop = $stop_ts[$i]
#	beginscan = $beginscan_secs[$i]
#	endscan = $endscan_secs[$i]
#	ts = $tss[$i] $before_time_sex[$i] $after_time_sex[$i]
#	power = $regim40[$i] $fmodes[$i]
#	prm = $freqs[$i] $freq1s[$i] $freq2s[$i]\n";
#	}
}


# combine multi-part observations into a single one. Could be useful for KPT-SVLBI comparison


if($combine){

	# save all obscodes
	my @obscodes;
	foreach my $i (sort keys %$hash_ref){
		push @obscodes, $$hash_ref{$i}{'obscode'};
	}

	# make an array with obscodes that are not uniq
	my %seen;
	my @obscodes_tmp;
	foreach my $string (@obscodes) {
		next unless $seen{$string}++;
		push @obscodes_tmp,$string;
	}
	@obscodes_tmp = List::MoreUtils::uniq @obscodes_tmp;
	my @obscodes_repeated;

	foreach (@obscodes_tmp){
		
		if($_ !~ m/\w/i ) {next;}
		else{
			chomp;
			s/\s+//g;
			push @obscodes_repeated,$_;
		}

	}

	print "-",join("-",@obscodes_repeated),"-\n";



	# run over all observations and modify 
	foreach my $o (@obscodes_repeated){

		my @starts_2combine=();
		my @stops_2combine=();

		foreach my $i (sort keys %$hash_ref){
			if ($$hash_ref{$i}{'obscode'} ne $o){next;}
			else {
				push @starts_2combine,$$hash_ref{$i}{'start'};
				push @stops_2combine,$$hash_ref{$i}{'stop'};
			}
			# push @obscodes, $$hash_ref{$i}{'obscode'};
		}
		@starts_2combine = sort @starts_2combine;
		@stops_2combine = sort @stops_2combine;

		#print "starts: ",join("  ", @starts_2combine),"\n";
		#print "the smallest is ",$starts_2combine[0],"\n";

		# minimum start time - beginning of the whole thing
		# set for this observatio the maximum stop time
		# then delete all other observations with the same obscode from the output
		$$hash_ref{$starts_2combine[0]}{'stop'} = $stops_2combine[-1];

	
		foreach my $i (sort keys %$hash_ref){
			if ($$hash_ref{$i}{'obscode'} eq $o and $i!=$starts_2combine[0]){
				delete($$hash_ref{$i});
			}
		}

		push @srt_err, "KPT: obscode $o was found to be multi-part and was collapsed to a single obs";



	}

}





return (\%srt_options,\@srt_err);
}





#### end reading schedule information
###############################################################################################



# check if time string looks usable
sub check_t(){
	my $l=$_[0];
	if ($l!~m/\b\d\d:\d\d:[\d\.]+/){return 0;}
	else{
		$l=~m/\b(\d\d):(\d\d):([\d\.]+)/;
		if($1>24 || $2>60 || $3>60){return 0;}
	}
	return 1;
}

# check if date string looks usable
sub check_d(){
	my $l=$_[0];
	if ($l!~m/\d\d\.\d\d\.\d{4}/ && $l!~m/\d{4}\.\d\d\.\d\d/){return 0;}
	elsif($l=~m/(\d\d)\.(\d\d)\.(\d{4})/){
		if($1>31 || $2>12) {
	return 0;}
	}
	elsif($l=~m/(\d{4})\.(\d\d)\.(\d\d)/){
		if($3>31 || $2>12) {return 0;}
	}

	return 1;
}


## return time stamp as a string
# dd.mm.yyyy hh:mm:ss
sub print_time(){
	my $tt=$_[0];
	my ($year,$month,$day, $hour,$min,$sec)=Time_to_Date($tt);
	my $ddd=sprintf("%02d.%02d.%d",$day,$month,$year);
	my $ttt=sprintf("%02d:%02d:%02d",$hour,$min,$sec);	
	my $str=sprintf("%s %s",$ddd,$ttt);
	return $str;

}

sub print_time_only(){
	my $tt=$_[0];
	my ($year,$month,$day, $hour,$min,$sec)=Time_to_Date($tt);
	my $ddd=sprintf("%02d.%02d.%d",$day,$month,$year);
	my $ttt=sprintf("%02d:%02d:%02d",$hour,$min,$sec);	
	my $str=sprintf("%s",$ttt);
	return $str;
}

sub print_time_only_short(){
	my $tt=$_[0];
	my ($year,$month,$day, $hour,$min,$sec)=Time_to_Date($tt);
	my $ddd=sprintf("%02d.%02d.%d",$day,$month,$year);
	my $ttt=sprintf("%02d:%02d",$hour,$min);	
	my $str=sprintf("%s",$ttt);
	return $str;
}

sub print_date_only(){
	my $tt=$_[0];
	my ($year,$month,$day, $hour,$min,$sec)=Time_to_Date($tt);
	my $ddd=sprintf("%02d.%02d.%d",$day,$month,$year);
	my $ttt=sprintf("%02d:%02d:%02d",$hour,$min,$sec);	
	my $str=sprintf("%s",$ddd);
	return $str;

}

sub print_datetime_mysql(){
	my $tt=$_[0];
	my ($year,$month,$day, $hour,$min,$sec)=Time_to_Date($tt);
	my $ddd=sprintf("%d-%02d-%02d",$year,$month,$day);
	my $ttt=sprintf("%02d:%02d:%02d",$hour,$min,$sec);	
	my $str=sprintf("%s %s",$ddd,$ttt);
	return $str;

}

sub print_date_sql(){
	my $tt=$_[0];
	my ($year,$month,$day, $hour,$min,$sec)=Time_to_Date($tt);
	my $ddd=sprintf("%d-%02d-%02d",$year,$month,$day);
	return $ddd;
}


# remove band switching observations with single band ones
# INPUT: hash array with SRT schedule
# OUTPUT: hash array with 

sub expand_multiband(){

my $tmp=shift;
my $debug=shift;

print "expand_multiband routine\n" if $debug;
my %out;


my %in=%$tmp;

foreach my $i (sort keys %in){
#print "i=",$i,"=",&print_time($i),"\n";

#print "type=",$in{$i}{'type'},"\n";


if($in{$i}{'type'} eq 'obs' || $in{$i}{'type'} eq 'just' || $in{$i}{'type'} eq 'just_virk' ){

#	print "bands_num=",$in{$i}{'bands_num'},"\n";

	if($in{$i}{'bands_num'} > 0){

#		print "MULTIBAND is to be expanded\n";
	
		for my $j (0..$in{$i}{'bands_num'}){

			#print "TIME=",&print_time($in{$i}{'start'.$j}),"\n";

			my $k=$in{$i}{'start'.$j};

			%{$out{$k}}=%{$in{$i}};
			$out{$k}{'bands'}=$in{$i}{'bands'.$j};
			$out{$k}{'bands_num'}=0;


			
			if($j==0){				# first
				$out{$k}{'start'}=$in{$i}{'start'};
				$out{$k}{'stop'}=$in{$i}{'stop'.$j};
				$out{$k}{'ts_bef'}=$in{$i}{'ts_bef'};
				$out{$k}{'ts_aft'}=0;
				$out{$k}{'beginscan'}=$in{$i}{'beginscan'};
				$out{$k}{'endscan'}  =$in{$i}{'stop'.$j};

			}
			elsif($j==$in{$i}{'bands_num'}){	# last
				$out{$k}{'start'}=$in{$i}{'start'.$j};
				$out{$k}{'stop'}=$in{$i}{'stop'};
				$out{$k}{'ts_bef'}=0;
				$out{$k}{'ts_aft'}=$in{$i}{'ts_aft'};
				$out{$k}{'beginscan'}=$in{$i}{'start'.$j};
				$out{$k}{'endscan'}  =$in{$i}{'endscan'};


			}
			else{					# in between
				$out{$k}{'start'}=$in{$i}{'start'.$j};
				$out{$k}{'stop'}=$in{$i}{'stop'.$j};
				$out{$k}{'ts_bef'}=0;
				$out{$k}{'ts_aft'}=0;
				$out{$k}{'beginscan'}=$in{$i}{'start'.$j};
				$out{$k}{'endscan'}  =$in{$i}{'stop'.$j};
			}

		
### TODO ts_bef and ts_aft



			#print &print_time($out{$k}{'start'}),"\t",&print_time($k),"\n";
			#print &print_time($out{$k}{'stop'}),"\t",&print_time($k),"\n";
			#print $out{$k}{'bands'},"\t",$k,"\n";

		}
	}
	else{
		$out{$i}=$in{$i};
			#print &print_time($out{$i}{'start'}),"\t",&print_time($in{$i}{'start'.$j}),"\n";
			#print &print_time($out{$i}{'stop'}),"\t",&print_time($in{$i}{'stop'.$j}),"\n";
			#print $out{$i}{'bands'},"\t",$in{$i}{'bands'.$j},"\n";



	}
}
else{
		$out{$i}=$in{$i};
}

}


#foreach (sort keys %out){
#print "start=",&print_time($_),"  stop=",&print_time($out{$_}{'stop'})," bands=",$out{$_}{'bands'},"\n";
#}


return \%out;

}

# sub to generate CONTROL WORD (UKS) for 1.35 receivers
# INPUT: channel 1 ([k|f]number), channel 2 (i.e. f0, k0-2 etc), attenuator 1 in dB, att 2, time to wait after UKS (basically this is already beyond the UKS itself), gsh{1} = off|high|low (turn different GSH on/off),  gsh{2} = off|high|low  
# OUTPUT: UKS with comment as a single line

sub uks(){

(my $ch1,my $ch2,my $att1, my $att2,my $time,my %gsh)=@_;		# channel 1,  channel 2, GSH state and choice
$time=10 unless $time;

$ch1=~m/[fk](.*)/i;
my $b1;
if($1 eq ""){	$b1="F0";}
else{	$b1="F".$1;}

$ch2=~m/[fk](.*)/i;
my $b2;
if($1 eq ""){	$b2="F0";}
else{	$b2="F".$1;}



my $huks=0x20000000;
my $str;		# return string
my $c="// ";		# comments
#$ch1=uc($ch1);
#$ch2=uc($ch2);



if($ch1 eq $ch2){$c.="2$b1";}
else{$c.=$b1."/".$b2;}
$c.=" ".$att1."/".$att2."dB ";



# channels

if($ch1 =~ m/^[fk][0]*$/i){$huks=$huks|0x24000000;}
if($ch2 =~ m/^[fk][0]*$/i){$huks=$huks|0x20400000;}

if($ch1 =~ m/^[fk]1$/i){$huks=$huks|0x25000000;}
if($ch2 =~ m/^[fk]1$/i){$huks=$huks|0x20500000;}

if($ch1 =~ m/^[fk]2$/i){$huks=$huks|0x26000000;}
if($ch2 =~ m/^[fk]2$/i){$huks=$huks|0x20600000;}

if($ch1 =~ m/^[fk]3$/i){$huks=$huks|0x27000000;}
if($ch2 =~ m/^[fk]3$/i){$huks=$huks|0x20700000;}

if($ch1 =~ m/^[fk]\-1$/i){$huks=$huks|0x23000000;}
if($ch2 =~ m/^[fk]\-1$/i){$huks=$huks|0x20300000;}

if($ch1 =~ m/^[fk]\-2$/i){$huks=$huks|0x22000000;}
if($ch2 =~ m/^[fk]\-2$/i){$huks=$huks|0x20200000;}

if($ch1 =~ m/^[fk]\-3$/i){$huks=$huks|0x21000000;}
if($ch2 =~ m/^[fk]\-3$/i){$huks=$huks|0x20100000;}

if($ch1 =~ m/^[fk]\-4$/i){$huks=$huks|0x20000000;}
if($ch2 =~ m/^[fk]\-4$/i){$huks=$huks|0x20000000;}

if($ch1 =~ m/^[fk]0\-1$/i){$huks=$huks|0x28000000;}
if($ch2 =~ m/^[fk]0\-1$/i){$huks=$huks|0x20800000;}

if($ch1 =~ m/^[fk]0\-2$/i){$huks=$huks|0x29000000;}
if($ch2 =~ m/^[fk]0\-2$/i){$huks=$huks|0x20900000;}

if($ch1 =~ m/^[fk]0\-3$/i){$huks=$huks|0x2A000000;}
if($ch2 =~ m/^[fk]0\-3$/i){$huks=$huks|0x20A00000;}


# gsh

$c.="GSH";

if($gsh{'1'} =~ m/off/i){$huks=$huks|0x00000000;$c.="-1 otkl ";}
if($gsh{'1'} =~ m/high/i){$huks=$huks|0x00000060;$c.="-1 visokiy";}
if($gsh{'1'} =~ m/low/i){$huks=$huks|0x00000020;$c.="-1 nizkiy";}

$c.=" GSH";
if($gsh{'2'} =~ m/off/i){$huks=$huks|0x00000000;$c.="-2 otkl";}
if($gsh{'2'} =~ m/high/i){$huks=$huks|0x00000180;$c.="-2 visokiy";}
if($gsh{'2'} =~ m/low/i){$huks=$huks|0x00000080;$c.="-2 nizkiy";}


# attenuators
$att1=$att1 << 15;
$att2=$att2 << 10;
$huks=$huks|$att1;
$huks=$huks|$att2;


$c.=" U 7.5mA";		# defaults

$str=sprintf("1\t%d\t3230,%X\t%s",$time,$huks,$c);

#printf "%X\n", $huks if $debug;
#a


return $str;



}

# sub to convert everything in a hash array with a schedule from DMV to UTC (subtract 3 hours)
# This means modifying primary keys and secondary ones: start and stop;
# INPUTS :  ref to HoH (hash of hashes) with times in DMV
# OUTPUT:  HoH with times in UT

sub dmv2ut(){
    my $hoh_in = $_[0];	# ref to HoH
    my %hoh_out;

    foreach my $primary (sort keys %$hoh_in){

	$hoh_out{$primary-3*3600} = $$hoh_in{$primary};

	$hoh_out{$primary-3*3600}{'start'} = $$hoh_in{$primary}{'start'} - 3*3600;
	$hoh_out{$primary-3*3600}{'stop'} = $$hoh_in{$primary}{'stop'} - 3*3600;

    }

return %hoh_out;    
}
1;
