#!/usr/bin/perl
use Modern::Perl;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;


my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();

my $pending_contents = $db->get_pending_contents();

foreach my $content (@$pending_contents) {
    eval {
        $content->process();
        print "Order ID " . $content->id . " processed successfully.\n";
    };
    if ($@) {
        warn "Failed to process order ID " . $content->id . ": $@";
    }
}


print "All pending orders processed.\n";



