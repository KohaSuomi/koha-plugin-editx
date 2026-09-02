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
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage;

my $schema = Koha::Database->new->schema;
my $edi_message = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage->new();
my $orderProcessor = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor->new();

my $parser = new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser((
    'objectFactory', new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice((
            'schemaPath','/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/'
        ))
    ));

my @new_messages = $schema->resultset('EdifactMessage')->search(
    {
        message_type => 'EDItX',
        status       => 'NEW',
    }
)->all;

foreach my $message (@new_messages) {
    try {
        my $claimed = $edi_message->claimForProcessing($message->id);
        next unless $claimed;

        my $order_object = $parser->parseDb($message->raw_msg);

        if (!$order_object) {
            die "Failed to parse XML content\n";
        }

        $order_object->setFileName($message->filename);

        $orderProcessor->process($order_object);
        $edi_message->update($message->id, 'OK');

    }
    catch {
        $edi_message->addToErrorLog($message->id, $_);
        $edi_message->update($message->id, 'FAILED');
    };
}

