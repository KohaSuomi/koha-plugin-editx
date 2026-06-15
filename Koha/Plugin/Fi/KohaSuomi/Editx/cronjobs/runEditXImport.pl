#!/usr/bin/perl

use strict;
use warnings;
use Modern::Perl;
use Try::Tiny;
use File::Slurp;
use File::Copy;
use XML::LibXML;

use Koha::Plugins;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage;

my $config = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new;
my $settings = $config->getSettings();

my $logPath    = $settings->{'settings'}->{'log_directory'} // die('log_directory not set');
my $tmpPath    = $settings->{'settings'}->{'import_tmp_path'} // die('import_tmp_path not set');
my $archivePath = $settings->{'settings'}->{'import_archive_path'} // die('import_archive_path not set');
my $failedPath = $settings->{'settings'}->{'import_failed_path'} // die('import_failed_path not set');

$tmpPath =~ s/\/$//;
$tmpPath .= '/';
$archivePath =~ s/\/$//;
$archivePath .= '/';
$failedPath =~ s/\/$//;
$failedPath .= '/';

my $logger = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger->new($logPath);
my $edi_message = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage->new;

$logger->log("Started runEditXImport", 1);

opendir(my $dh, $tmpPath) or die "Cannot open directory $tmpPath: $!";
my @files = grep { /\.xml$/i && -f "$tmpPath$_" } readdir($dh);
closedir $dh;

foreach my $file (@files) {
    if (!-s "$tmpPath$file") {
        $logger->log("File $file is empty, moving to failed");
        move("$tmpPath$file", "$failedPath$file") or die "Could not move file $file to failed: $!";
        next;
    }

    my $size1 = (stat "$tmpPath$file")[7];
    sleep(1);
    my $size2 = (stat "$tmpPath$file")[7];
    if ($size1 != $size2) {
        $logger->log("File $file is still being written, skipping until next run");
        next;
    }

    my $content = read_file("$tmpPath$file");
    my $xml = XML::LibXML->new()->parse_string($content);
    my $filename = $edi_message->constructFilename($xml, undef);
    print "Processing file $file, constructed filename: $filename\n";
    if ($edi_message->duplicateExists($filename)) {
        $logger->log("File $file already exists as $filename in DB, moving to failed");
        move("$tmpPath$file", "$failedPath$file") or die "Could not move file $file to failed directory: $!";
        next;
    }

    try {
        my $vendor_id = $edi_message->findVendorId($xml);

        if (!$vendor_id) {
            die "Could not find matching vendor for file $file";
        }

        $edi_message->create($content, $filename, $vendor_id);
        move("$tmpPath$file", "$archivePath$file") or die "Could not move file $file to archive: $!";
        $logger->log("File $file saved as $filename to edifact_messages and archived");
    }
    catch {
        $logger->logError("Failed to process file $file: $_");
        move("$tmpPath$file", "$failedPath$file") or die "Could not move file $file to failed directory: $!";
        $edi_message->addToErrorLog($file, $_);
    };
}

$logger->log("Ended runEditXImport", 1);
