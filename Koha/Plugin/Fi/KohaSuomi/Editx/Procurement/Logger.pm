#!/usr/bin/perl
package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger;

use C4::Context;
use Data::Dumper;
use POSIX qw(strftime);

my $singleton;
my $logFolder = 0;
my $errorLogPath;
my $transactionLogPath;

sub new {
    my $class = shift;
    if(! $logFolder){
        $logFolder = $_[0];
        if(-d $logFolder){
            $logFolder = $1 if($logFolder=~/(.*)\/$/);
            $logFolder = $logFolder . '/';
            $transactionLogPath = $logFolder . "transaction.log";
            $errorLogPath = $logFolder . "error.log";

            unless(open FILE, '>>'. $transactionLogPath) {
                warn "Unable to create $transactionLogPath\n";
                $transactionLogPath = undef;
            }

            unless(open FILE, '>>'. $errorLogPath) {
                warn "Unable to create $errorLogPath\n";
                $errorLogPath = undef;
            }
        }
    }

    $singleton ||= bless {}, $class;
}

sub log{
    $self = shift;
    my $message = $_[0];
    my $useEcho = $_[1];
    $self->writeToFile($transactionLogPath, $message);

    if($useEcho){
        print "$message\n";
    }
}

sub logError{
    $self = shift;
    my $message = $_[0];
    my $useEcho = $_[1];
    $self->writeToFile($errorLogPath, $message);

    if($useEcho){
        warn  "$message\n";
    }
}

sub writeToFile{
    $self = shift;
    my $filePath = $_[0];
    my $message = $_[1];

    return unless defined $filePath;

    if(-f $filePath && $message ){
        if(open(my $fh, '>>', $filePath)){
            $message = $self->getTimeStamp() . " -- " . $message . "\n";
            print $fh "$message";
            close $fh;
        } else {
            warn "Unable to write to $filePath: $!\n";
        }
    }
}

sub getTimeStamp {
    my $self = shift;
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

1;
