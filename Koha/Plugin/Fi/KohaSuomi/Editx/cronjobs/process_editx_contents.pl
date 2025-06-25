#!/usr/bin/perl
use Modern::Perl;
use Try::Tiny;

use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use Koha::Plugins;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator;



my $config = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
my $settings = $config->getSettings();
my $logPath;

if (defined $settings->{'settings'}->{'log_directory'}) {
    $logPath = $settings->{'settings'}->{'log_directory'};
} else {
    die('The log_directory not set in config.');
}

my $logger = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger->new($logPath);
my $orderProcessor = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;
my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();

$logger->log("Started Koha::Procurement", 1);

my $pending_contents = $db->get_pending_contents() // [];



if (@$pending_contents) {
    foreach my $content (@$pending_contents) {
        my $content_id = $content->{id};

        try {
            $logger->log("Started processing order with ID $content_id");
            Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($content_id);

            $orderProcessor->process($content->{content});

            $db->mark_order_as_completed($content_id);
            $logger->log("Ended processing content with ID $content_id");
        } catch {
            $db->mark_order_as_failed($content_id);
            my $failMsg = "Failed to process content with ID $content_id.";
            $logger->log($failMsg);
            $logger->logError($failMsg);
            $logger->logError("Error was: $_");
        }
    }
} else {
    $logger->log("no penfing orders found in the database.");
}


$logger->log("Ended Koha::Plugin::Fi::KohaSuomi::Editx::Procurement", 1);








