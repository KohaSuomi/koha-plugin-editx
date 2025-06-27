#!/usr/bin/perl

use strict;
use warnings;
use Modern::Perl;
use Try::Tiny;
use Data::Dumper;

use Koha::Database;
use Koha::Plugins;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;

my $config = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
my $settings = $config->getSettings();
my $logPath;

if (defined $settings->{'settings'}->{'log_directory'}) {
    $logPath = $settings->{'settings'}->{'log_directory'};
} else {
    die('The log_directory not set in config.');
}

my $logger = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger($logPath);
my $orderProcessor = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;

# Initialize the database object
my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();

$logger->log("Started Koha::Procurement from database", 1);

my $pending_orders = $db->get_pending_contents();
my $order_row;
while ($order_row = $pending_orders->next) {
    try {
        
        $logger->log("Started processing order ID " . $order_row->id);
        $orderProcessor->process($order_row);

        # Päivitä tilauksen tila tietokannassa
        $order_row->update({ status => 'processed' });

        $logger->log("Ended processing order ID " . $order_row->id);
    } catch {
        my $failMsg = "Order processing failed for ID " . $order_row->id;
        $logger->log($failMsg);
        $logger->logError($failMsg);
        $logger->logError("Error was: $_");
    }
}

$logger->log("Ended Koha::Procurement from database", 1);