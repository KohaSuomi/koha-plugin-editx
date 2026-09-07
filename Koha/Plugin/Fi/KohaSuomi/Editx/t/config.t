#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 2;
use Test::MockObject;
use Test::MockModule;
use FindBin qw($Bin);
use Koha::Plugins;

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

subtest 'getSettings - DB and file precedence' => sub {
    plan tests => 2;
    my $mock_config = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
    $mock_config->mock( 'loadConfigXml', sub {
        return {
            settings => {
                authoriser => 'file_authoriser',
                import_tmp_path => '/tmp/file_import',
            },
            notifications => {},
        };
    } );
    $mock_config->mock( 'loadPluginData', sub {
        return {
            procurement_authoriser => 'db_authoriser',
        };
    } );

    my $config   = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new();
    my $settings = $config->getSettings();

    is($settings->{'settings'}->{'authoriser'}, 'db_authoriser', 'Uses DB value when DB has value');
    is($settings->{'settings'}->{'import_tmp_path'}, '/tmp/file_import', 'Uses file value when DB key is missing');
};

subtest 'loadPluginData - XML fallback and DB write-back on empty value' => sub {
    plan tests => 4;
    my @do_calls;
    my $mock_dbh = Test::MockObject->new();
    $mock_dbh->mock( 'selectall_arrayref', sub {
        return [
            { plugin_key => 'procurement_authoriser', plugin_value => '' },
        ];
    } );
    $mock_dbh->mock( 'do', sub {
        my ( undef, @args ) = @_;
        push @do_calls, \@args;
        return 1;
    } );

    my $mock_context = Test::MockModule->new('C4::Context');
    $mock_context->mock( 'dbh', sub { return $mock_dbh; } );

    my $mock_config = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
    $mock_config->mock( 'loadConfigXml', sub {
        return {
            settings => {
                authoriser => 'file_authoriser',
            },
            notifications => {},
        };
    } );

    my $config      = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new();
    my $plugin_data = $config->loadPluginData();

    is(
        $plugin_data->{procurement_authoriser},
        'file_authoriser',
        'Falls back to XML when DB value is empty'
    );
    is( scalar @do_calls, 1, 'Writes fallback value back to DB once' );
    is( $do_calls[0]->[3], 'procurement_authoriser', 'Writes the expected plugin key' );
    is( $do_calls[0]->[4], 'file_authoriser', 'Writes XML fallback value to DB' );
};

done_testing();