#!/usr/bin/perl

use strict;
use warnings;
use Modern::Perl;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

use C4::Context;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

use constant PLUGIN_CLASS => 'Koha::Plugin::Fi::KohaSuomi::Editx';

my @PATH_KEYS = qw(
    import_tmp_path
    import_load_path
    import_archive_path
    import_failed_path
    import_failed_archived_path
);

my $force = grep { $_ eq '--force' } @ARGV;

my $config   = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new->loadConfigXml();
my $settings = $config->{settings} || {};

my $dbh = C4::Context->dbh;

my $filled   = 0;
my $skipped  = 0;
my $missing  = 0;

for my $key (@PATH_KEYS) {
    my $value = $settings->{$key};
    if ( !defined $value || ref $value || $value eq '' ) {
        say "skip $key: not present in procurement-config.xml";
        $missing++;
        next;
    }

    my $plugin_key = "procurement_$key";
    my ($current) = $dbh->selectrow_array(
        "SELECT plugin_value FROM plugin_data WHERE plugin_class = ? AND plugin_key = ?",
        undef, PLUGIN_CLASS, $plugin_key
    );

    if ( !$force && defined $current && $current ne '' ) {
        say "keep $plugin_key = $current (already set; use --force to overwrite)";
        $skipped++;
        next;
    }

    $dbh->do(
        "INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE plugin_value = ?",
        undef, PLUGIN_CLASS, $plugin_key, $value, $value
    );
    say "set $plugin_key = $value";
    $filled++;
}

say "Done: $filled set, $skipped kept, $missing missing from XML.";