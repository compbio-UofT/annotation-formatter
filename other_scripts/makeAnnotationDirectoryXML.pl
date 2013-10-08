#!/usr/bin/perl -w
#Generates the main xml file containing the directory of all annotations.
#This should be run last, after assembleZips.pl.  It will scan the given input directory
#for zip files, extract information about each annotation from the XML file contained within the zip file,
#and output a new XML.
#
# USAGE: makeAnnotationDirectoryXML.pl <input directory> <sdk-version> <output xml> <url prefix>
# This script should be run from the directory with URL <url prefix>, and the input directory should be 
# specified as a relative path.  For example, makeAnnotationDirectoryXML.pl packaged 1.0.1 /path/to/annotations.xml http://medsavant.com/annotations
# will look in the 'packaged' subdirectory for .zip files, and create URLS like http://medsavant.com/annotations/packaged/hg19/gerp++gt2.zip 
#
# Requires cpan module XML::Simple. 

use XML::Simple;

sub trim($)
{

        my $string = shift;
  if($string){

        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
    }
        return $string;
}


sub getXMLForFile($$$){
	my $filename = shift(@_);
	my $refMap = shift(@_);
	my $sdkVersion = shift(@_);



	my $xmlFilename = $filename;
	if($xmlFilename =~ /.*\/(.*)\.zip/){
		$xmlFilename = $1.'.xml';
		print "getting xml for zip file $filename\n";
	}else{
		print "Skipping non-zip file $filename\n";
		return;
	}
	my $cmd = "unzip -p $filename $xmlFilename";
	my $xmlText = `$cmd`;
	my $xml = new XML::Simple;
	my $xmlHash = $xml->XMLin($xmlText);

	my $ref = "";
	if(defined $xmlHash->{'reference'}){
		$ref = $xmlHash->{'reference'};
	}	#Note that blank references are allowed

	my $s = "";
	if(defined $refMap->{$ref}){
		$s = $refMap->{$ref};
	}

	my $name;
	if(defined $xmlHash->{'name'}){
		$name = $xmlHash->{'name'};	
	}elsif(defined $xmlHash->{'program'}){
		$name = $xmlHash->{'program'};
	}else{
		die("Unable to determine annotation name for $filename\n");
	}

	my $version;
	if(defined $xmlHash->{'version'}){
		$version = $xmlHash->{'version'};
	}else{
		die("Unable to determine version for $filename\n");
	}

	my $description = "";
	if(defined $xmlHash->{'description'}){
		$description = $xmlHash->{'description'};
	}

	$url = $URL_PREFIX.$filename;

	$s .= "\t\t\t<annotation name=\"$name\" version=\"$version\" description=\"$description\" url=\"$url\" />\n";
	$refMap->{$ref} = $s;
}

#Taken from http://www.perlmonks.org/?node_id=136482
sub getFiles($);
sub getFiles($) {
    my $path = shift;

    opendir (DIR, $path)
        or die "Unable to open $path: $!";

    # We are just chaining the grep and map from
    # the previous example.
    # You'll see this often, so pay attention ;)
    # This is the same as:
    # LIST = map(EXP, grep(EXP, readdir()))
    my @files =
        # Third: Prepend the full path
        map { $path . '/' . $_ }
        # Second: take out '.' and '..'
        grep { !/^\.{1,2}$/ }
        # First: get all files
        readdir (DIR);

    closedir (DIR);

    for (@files) {
        if (-d $_) {
            # Add all of the new files from this directory
            # (and its subdirectories, and so on... if any)
            push @files, getFiles ($_);

        } else {
            # Do whatever you want here =) .. if anything.
        }
    }
    # NOTE: we're returning the list of files
    return @files;
}


if(@ARGV < 3){
	print "USAGE: makeAnnotationDirectoryXML.pl <input directory> <sdk-version> <output xml> <url prefix>\n";
	exit;
}

my $inputDir = shift(@ARGV);
my $sdkVersion = shift(@ARGV);
my $outputXML = shift(@ARGV);
our $URL_PREFIX = shift(@ARGV);
my @inputFiles = getFiles($inputDir);

#Maps RefName => annotation elements  
#(e.g. hg19 => (<annotation name="whatever" version="1.0.0" description="" url="http://something" /><annotation name=.... />...)
my $m = {}; 
for($i = 0; $i < @inputFiles; ++$i){
	if(-f $inputFiles[$i]){
		getXMLForFile($inputFiles[$i], $m, $sdkVersion);
	}
}

$xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n";
$xml = "<annotations>\n";
$xml = "\t<version name=\"$sdkVersion\">\n";
while(my ($ref, $val) = each %$m){
	$xml .= "\t\t<reference name=\"$ref\">\n";
	$xml .= $val;
	$xml .= "\t\t</reference>\n";
}
$xml .="\t</version>\n";
$xml .="</annotations>\n";

=pod
if(-f $outputXML){
	open(OUT, ">/tmp/tmp_annotationDirectory.xml") or die("Can't open temporary file /tmp/tmp_annotationDirectory.xml for writing\n");
	
	my $xml = new XML::Simple;
	my $xmlHash = $xml->XMLin($outputXML);

	$ver = $xmlHash->{'annotations'}->{'version'}->{'name'};
	if($ver

	open(IN, "<$outputXML") or die("Can't open existing file $outputXML for reading (permissions?)\n");
	while(<IN>){
		my $line = trim($_);
		if($line =~ /
	}
	$outputXML = "/tmp/tmp_annotationDirectory.xml";	
	
	print "Modified $outputXML";
}else{
=cut
	open(OUT, ">$outputXML") or die("Can't write to output file $outputXML\n");
	print OUT "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n";
	print OUT "<annotations>\n$xml</annotations>\n";
	close(OUT);
	print "Wrote $outputXML\n";
#}









