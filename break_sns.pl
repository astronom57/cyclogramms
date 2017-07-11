
# script to break monthly soglasnov style schedule into single files. 1 per cyclogramm

use Date::Calc qw(:all);
use Getopt::Long;
($year,$month,$day, $hour,$min,$sec) = Today_and_Now(); 
$dateandtime=sprintf("%04d.%02d.%02d %02d:%02d:%02d",$year,$month,$day, $hour,$min,$sec);

open F,$ARGV[0] or die "No schedule file specified. Exit doing nothing.\nUSAGE perl break_sns.pl schedule_file\n";
@f=<F>;
close F;

my $obs_n=0;
my $sns_n=0;
my $just_n=0;

for $l (@f){
	
	if($l=~m/observation/i){$obs_n++;}
	if($l=~m/SNS_COMMAND/i){$sns_n++;}
	if($l=~m/justirovka/i){$just_n++;}
	

}

print "This month contains $obs_n observations\n$just_n justirovok and $sns_n command sessions\n";

# handle a case when in a monthly schedule observations go before any SNS_COMMAND

$sns_first=0;

for (my $i=0;$i<=$#f;$i++){
	if($f[$i]=~m/SNS_COMMAND/i){$sns_first=0; last;}
	if($f[$i]=~m/observation/i){$sns_first=1; last;}
	if($f[$i]=~m/justirovka/i){$sns_first=-1; last;}
}


if($sns_first!=0){
	
	print "\nIn this monthly schedule $ARGV[0] there are some observations or justirovka before any SNS_COMMAND. This means that you have to handle this case manually (copy the end of previous month and catenate it with the beginning ot current month). Please confirm that you have read this statement carefully and understood it by pressing ENTER\[RETURN\]\n";
	<STDIN>;
}








for (my $i=0;$i<=$#f;$i++){
	if($f[$i]=~m/SNS_COMMAND/i){
		push @is,$i;
	}
}

print join(" ", @is),"\n" if $debug;

for(my $j=0;$j<$#is;$j++){
my $num=sprintf("%02d",$j+1);
$file=$ARGV[0]."_".$num ;
open O,">",$file or die "Cannot open file $file to write\n";
print "Writing to $file\n";
	print O "/- Schedule part for one cyclogramm.
/- Generated on $dateandtime. Script $0
/- written by Mikhail Lisakov from ASC lisakov\@asc.rssi.ru.\n";	
	print O "/- Part no. ",$j+1," read from file $ARGV[0] line no. $is[$j]\n";
	
	for(my $k=$is[$j];$k<=$is[$j+1]+2;$k++){
		print O "$f[$k]";
	}
close O;
}








exit 0;
