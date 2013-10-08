#!/usr/bin/perl -w

if(@ARGV < 3){
	print "USAGE: assemblezips.pl <xml directory> <tabix directory> <output directory>\n";
	exit;
}
my $xmlDir = shift(@ARGV);
my $tabixDir = shift(@ARGV);
my $outputDir =  shift(@ARGV);

system("mkdir -p $outputDir");

opendir(DIR, $xmlDir) or die("Can't open $xmlDir\n");
while(my $innerfile = readdir(DIR)){
	next unless(-f $xmlDir.'/'.$innerfile);

	#extract filename without extension.
	my $prefix = $innerfile;
	$prefix =~ /(.*)\.xml/i;
	$prefix=$1;
#	print "match $1 for file $innerfile\n";
#	$prefix = $1;

	my $tabixFile = $tabixDir.'/'.$prefix.'.gz';
	my $indexFile = $tabixDir.'/'.$prefix.'.gz.tbi';
	my $xmlFile = $xmlDir.'/'.$innerfile;

	if(-f $tabixFile){
		if(-f $indexFile){
			print "zip -j -0 $outputDir/$prefix.zip $tabixFile $indexFile $xmlFile\n";
		}else{
			print "Couldn't locate index for $tabixFile\n";
		}
	}else{
		print "Couldn't locate tabix file $tabixFile for $xmlFile\n";
	}
}
