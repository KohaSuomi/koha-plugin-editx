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
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice;

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

my $parser = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser((
    'objectFactory', new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice((
            'schemaPath','/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/'
        ))
    ));
my $libraryShipNoticePath;
    if(defined $settings->{'settings'}->{'import_load_path'}){
    $libraryShipNoticePath = $settings->{'settings'}->{'import_load_path'};
}


my $pending_orders = $db->get_pending_contents();
foreach my $order_row (@$pending_orders) {
    try {
        
        $logger->log("Started processing order ID " . $order_row->{id});

        #Debugging:
        $logger->log("Debug: Order row content: " . Dumper($order_row->{content}));

        # Create an order object from the database content
        my $order_object = $parser->parseDb($order_row->{content});

        $logger->log("Debug: Order object: " . Dumper($order_object));

        if(!$order_object) {
            $logger->logError("Failed to create order object from content for order ID " . $order_row->{id});
            return;
        }


        # Process the order object
        $orderProcessor->process($order_object);

        # Päivitä tilauksen tila tietokannassa
        $db->mark_order_as_completed($order_row->{id});

        $logger->log("Ended processing order ID " . $order_row->{id});
    } catch {
        my $failMsg = "Order processing failed for ID " . $order_row->{id};
        $logger->log($failMsg);
        $logger->logError($failMsg);
        $logger->logError("Error was: $_");
        $db->mark_order_as_failed($order_row->{id});
    }
}

$logger->log("Ended Koha::Procurement from database", 1);