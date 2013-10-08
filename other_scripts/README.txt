These scripts support loading annovar annotations and creating the annotation directory
XML.

aj.pl: modified version of annovar used to create tab delimited files that can be processed by annotationFormatter.  This will probably not need to be called directly, but is instead invoked by annovar2medsavant.pl

annovar2medsavant.pl: Wrapper script that performs 3 functions:  1) Downloads annovar databases 2) Converts the databases to tab delimited format using aj.pl, then sorts them using the unix 'sort' command (by chromosome, then start, then ref, then alt).  3) Invokes annotationFormatter to convert the sorted tab delimited files to tabix format, and output appropriate XML annotation descriptors.

assembleZips.pl: Given two input directories consisting of the XML annotation descriptors and tabix files (annovar2medsavant.pl outputs the tabix files to one directory, and the XML descriptors to another), this program will assemble .zip files suitable for use by medsavant.

makeAnnotationDirectoryXML.pl: This should be run on the webserver, in a URL accessible directory somewhere above where the zip files are deployed.  It will generate a directory of XML files.

annovar_files.txt: List of annovar databases, used by annovar2medsavant.pl.  This file minimally contains 5 columns:  The reference genome, the 'name' that should be passed to annovar to download the database, the name of the 'program' that should be recorded in the plugin descriptor xml, the 'dbtype' that should be passed to annovar (usually the same as 'name' above, but differs in some cases -- e.g. 1000genomes projects), and the 'type'.  The type should be 'gene', 'variant', or 'region'.  Various other synonyms (e.g. variant_other, region_bed, etc.) are accepted, but it's best just to use one of these three.


