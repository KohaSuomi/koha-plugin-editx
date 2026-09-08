#!/usr/bin/perl

use strict;
use warnings;
use Modern::Perl;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

use C4::Context;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

use constant PLUGIN_CLASS => 'Koha::Plugin::Fi::KohaSuomi::Editx';

my @SETTING_KEYS = qw(
    import_tmp_path
    import_load_path
    import_archive_path
    import_failed_path
    import_failed_archived_path
    authoriser
    allowed_locations
    productform_alternative_triggers
    automatch_biblios
    use_finna_materialtype
);
my @NOTIFICATION_KEYS = qw( mailto mailfrom );

my $config         = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new->loadConfigXml();
my $xml_settings   = $config->{settings} || {};
my $xml_notif      = $config->{notifications} || {};

my $dbh = C4::Context->dbh;
my $rows = $dbh->selectall_arrayref(
    "SELECT plugin_key, plugin_value FROM plugin_data WHERE plugin_class = ?",
    { Slice => {} },
    PLUGIN_CLASS
);
my %db = map { $_->{plugin_key} => $_->{plugin_value} } @$rows;

my $from_db = 0;
my $from_xml = 0;

printf "%-34s %-36s %s\n", "SETTING", "SOURCE", "VALUE / NOTE";

for my $key ( @SETTING_KEYS, @NOTIFICATION_KEYS ) {
    my $db_key    = ( $key eq 'mailto' || $key eq 'mailfrom' )
        ? "procurement_notification_$key"
        : "procurement_$key";
    my $xml_value = $key eq 'mailto' || $key eq 'mailfrom'
        ? $xml_notif->{$key}
        : $xml_settings->{$key};
    $xml_value = '' if !defined $xml_value || ref $xml_value;

    my $db_value = $db{$db_key} // '';

    my ( $source, $value );
    if ( $db_value ne '' ) {
        $source = 'plugin_data';
        $value  = $db_value;
        $from_db++;
    }
    elsif ( $xml_value ne '' ) {
        $source = $db{$db_key} ? 'XML (empty DB row -> copied on load)' : 'XML (no DB row)';
        $value  = $xml_value;
        $from_xml++;
    }
    else {
        $source = $db{$db_key} ? 'empty' : 'not set';
        $value  = '';
    }

    my $note = $value;
    if ( $key =~ /^import_/ && $value ne '' ) {
        $note .= -d $value ? '    [dir ok]' : '    [DIR MISSING]';
    }
    printf "%-34s %-36s %s\n", $key, $source, $note;
}

my $logdir = ( C4::Context->config('logdir') || '' ) . "/editx";
printf "%-34s %-36s %s\n", 'log_directory', 'computed (koha-conf logdir)', $logdir;

say "";
say "Summary: $from_db setting(s) from plugin_data, $from_xml from XML, log_directory always computed.";