#!/usr/bin/perl -w
if(@ARGV < 2){
		die("USAGE: annovar2medsavant.pl <annotation list (filename)> <version> {path to scripts}\n");
}

$SIG{'INT'} = \&death;

#TEMP dir for unix sort

our $SORT_BUFFER_SIZE = "2G";

#Can be different disk than database files, which should make everything run a bit faster (no trailing slash)
our $DISK2_TMP = "/home/jim/disk3/jim/tmp";

#Can be same disk as database files. (no trailing slash)
our $DISK1_TMP = "/mnt/annovar/tmp";

our $PROGRAM = "annovar";
my $afile = shift(@ARGV);
our $VERSION = shift(@ARGV);
my $path = ".";
if(@ARGV){
	$path = shift(@ARGV);
}
our $ANNOTATION_FORMATTER = "java -Xmx8192M -jar ".$path.'/'."annotationFormatter.jar "; 


my $annovar = $path."/annotate_variation.pl";
my $aj = $path."/aj.pl";

sub death{
	die("CTRL-C Pressed, Aborting...\n");	
}

# Trim function to remove whitespace from the start and end of the string
sub trim($)
{

	my $string = shift;
  if($string){

	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
    }
  	return $string;
}

sub syscmd($){
	my $cmd = shift(@_);
	print "EXECUTING: $cmd\n";
	return system($cmd);
}

sub makeTabix(){
	my $dir = $DISK1_TMP.'/';
	opendir(DIR, $dir);
	while(my $file = readdir(DIR)){
		next unless (-d $dir.$file);
		
		my $ver = $file;
		opendir(INNERDIR, $dir.$file);
		while(my $innerfile = readdir(INNERDIR)){
			next unless (-f $dir.$file.'/'.$innerfile);
			
			my $type;
			if(index($innerfile, 'position') != -1){
				$type = 'position';
			}else{
				$type = 'interval';
			}
			
			#TODO: Determine type=interval or type=position.
			runAnnotationFormatter($dir.$file.'/'.$innerfile, $ver, $type);	
		}
			
	}
	close(DIR);
}

sub runAnnotationFormatter($$$){
	my $pathToFile = shift(@_);
	my $refgenome = shift(@_);
	my $type= shift(@_); #interval or position

	my $prefix = $pathToFile;
	$prefix =~ /.*\/(.*)\.tsv.*\.sorted.*/i;
	$prefix = $1;

	if($prefix){			
		syscmd("mkdir -p output/$refgenome");
		
		print "got prefix $prefix\n";		
		my $fx = 
		my $args = "$pathToFile output/$refgenome/$prefix.xml -fixTabix $DISK2_TMP/$refgenome/$prefix -o version=$VERSION -o program=$PROGRAM -o type=$type -o chr=chrom -o refgenome=$refgenome";		
		if($type eq "position"){
			$args .= " -o position=start";	
		}				
		
		my $p = "output/$refgenome/$prefix.xml";
		if(-e $p){
			print "WARNING: $p already exists.  SKIPPING\n";
			return;
		}
		
		my $cmd =$ANNOTATION_FORMATTER." ".$args; 
		syscmd($cmd);
		
		#Uncomment the following to clean up intermediate files.		
		#syscmd("rm -f $pathToFile");
		print "Generated XML output/$refgenome/$prefix.xml, Tabix $DISK2_TMP/$refgenome/$prefix.gz\n";
	}	 
	
	 
}

sub convertToTSV($$){
	print "Converting databases to tabix-like TSV and sorting\n";
	my $afile = shift(@_);
	my $aj = shift(@_);
	open(IN, "<$afile") or die("Can't open $afile for reading\n");
	<IN>; #skip header	
	while(<IN>){
		my $line = trim($_);
		if(!$line){
			next;
		}
		my @t = split(/\t/, $line);
		
		my $ver = trim($t[0]);
		my $db = trim($t[1]);
		my $prefix = trim($t[2]);
		my $dbtype = trim($t[3]);
		my $type = lc(trim($t[4]));
		my $done = trim($t[5]);		 
		if($done eq "1"){
			next;
		}
		my $simpletype = "position";
		syscmd("mkdir -p $DISK2_TMP/$ver");
		syscmd("mkdir -p $DISK1_TMP/$ver");
		my $outfile = "$DISK2_TMP/$ver/".$prefix.".tsv";
		my $sorted_outfile_prefix = "$DISK1_TMP/$ver/".$prefix.".tsv";

		my $args = "--buildver $ver -comment -medsavantfile $outfile ";
		if( ($type eq "variant") || ($type eq "variant_other") || ($type eq "variant_snp") || ($type eq "variant_1000g")){
			$args .= "-colsWanted all -filter -dbtype $dbtype humandb/$ver/";
			$simpletype = "position";
		}elsif($type eq "gene"){
			$args .= "humandb/$ver/";
			$simpletype = "interval";
		}elsif($type eq "region" || $type eq "region_bed" || $type eq "region_ucsc" || $type eq "region_gff"){
			$args .= "-regionanno -dbtype $dbtype humandb/$ver/";
			$simpletype = "interval";
		}else{
			die("Unrecognized type $type in annotation list.\n");
		}
		
		my $cmd = $aj." ".$args;
		
		syscmd($cmd);
		
		
		#If the type is 'position', then it is a variant file and we sort by chromosome, position, ref, alt.
		#otherwise, we sort by chromosome, position (start).
		if($simpletype eq "position"){
			$cmd = "(head -n 1 $outfile && tail -n +2 $outfile |sort --buffer-size=$SORT_BUFFER_SIZE -T $DISK1_TMP -t".'$'."'\\t'"." -k 1,1V -k 2,2n -k 4,4 -k 5,5) >$sorted_outfile_prefix.$simpletype.sorted";
		}else{
			$cmd = "(head -n 1 $outfile && tail -n +2 $outfile |sort --buffer-size=$SORT_BUFFER_SIZE -T $DISK1_TMP -t".'$'."'\\t'"." -k 1,1V -k 2,2n) >$sorted_outfile_prefix.$simpletype.sorted";
		}
		
		my @c = ("bash", "-c", $cmd);
		print "EXECUTING: $cmd\n";		
		system(@c);
		#Uncomment if you want to clean up intermediate files. 					
		#system("rm -f $outfile");	#remove unsorted files from first disk.	
	}	
	close(IN);
}

sub downloadDatabases($$){
	print "Downloading databases\n";
	my $afile = shift(@_);
	my $annovar = shift(@_);
	

	open(IN, "<$afile") or die("Can't open $afile for reading\n");
	<IN>; #skip header
	while(<IN>){
		my $line = trim($_);
		if(!$line){
			next;
		}
		my @t = split(/\t/, $line);
		my $ver = trim($t[0]);
		my $db = trim($t[1]);
		my $prefix = trim($t[2]);
		my $dbtype = trim($t[3]);
		my $type = lc(trim($t[4]));
		my $done = trim($t[5]);		 
		if($done eq "1"){
			next;
		}
		print "Downloading $db\n";
		syscmd("mkdir -p humandb/$ver");		
		syscmd($annovar." -buildver $ver -downdb $db -webfrom annovar humandb/$ver");
		print "\n";
	}
	close(IN);
}

# You may want to execute each of these functions separately by commenting the other two out, so that you can 
# check intermediate files.
# As of Oct. 2013, you'll need about 800GB of disk space -- preferably split between two physical disks. (in which case one of the disks 
# (DISK1_TMP) will need 500GB)
downloadDatabases($afile, $annovar);
convertToTSV($afile, $aj);
makeTabix();


