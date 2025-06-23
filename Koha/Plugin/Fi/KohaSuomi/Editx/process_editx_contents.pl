#!/usr/bin/perl
use Modern::Perl;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;



## This script processes pending Editx contents form the database
## It retrieves all pending contents, processes them, and handles any errors that may occur

my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();

my $pending_contents = $db->get_pending_contents() // [];

foreach my $content (@$pending_contents) {
    my $content_id = $content->id // 'undefined';
    eval {
        $content->process();
        print "Order ID $content_id processed successfully.\n";
    };
    if ($@) {
        warn "Failed to process order ID $content_id: $@";
    }
}


print "All pending orders processed.\n";



