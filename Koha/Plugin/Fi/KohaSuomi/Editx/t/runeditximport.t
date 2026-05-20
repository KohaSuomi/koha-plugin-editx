#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use FindBin qw($Bin);
use File::Spec;
use Koha::Plugins;

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

my @archived_files;
my @failed_files;
my @processed_orders;
my @error_log_calls;
my @validated_files;
my @logger_errors;

my %mock_orders;
my %should_process_fail;

my $mock_config = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
$mock_config->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config';
});
$mock_config->redefine('getSettings', sub {
    return {
        settings => {
            log_directory     => '/tmp',
            import_load_path  => '/tmp/editx/load',
            import_tmp_path   => '/tmp/editx/tmp',
            import_archive_path => '/tmp/editx/archive',
            import_failed_path  => '/tmp/editx/failed',
        }
    };
});

my $mock_file = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::File');
$mock_file->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::File';
});
$mock_file->redefine('fillLoadFolder', sub { return 1; });
$mock_file->redefine('archiveFile', sub {
    my ($self, $filename) = @_;
    push @archived_files, $filename;
    return 1;
});
$mock_file->redefine('moveToFailFolder', sub {
    my ($self, $filename) = @_;
    push @failed_files, $filename;
    return 1;
});

my $mock_logger = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger');
$mock_logger->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger';
});
$mock_logger->redefine('log', sub { return 1; });
$mock_logger->redefine('logError', sub {
    my ($self, $message) = @_;
    push @logger_errors, $message;
    return 1;
});

my $mock_factory = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice');
$mock_factory->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice';
});

my $mock_parser = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser');
$mock_parser->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser';
});
$mock_parser->redefine('parseFiles', sub {
    return %mock_orders;
});

my $mock_validator = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator');
$mock_validator->redefine('validateEditx', sub {
    my ($filename) = @_;
    push @validated_files, $filename;
    return 1;
});

my $mock_orderprocessor = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor');
$mock_orderprocessor->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor';
});
$mock_orderprocessor->redefine('process', sub {
    my ($self, $order) = @_;
    my $order_id = ref($order) eq 'HASH' ? $order->{id} : $order;
    push @processed_orders, $order_id;
    die "Simulated process failure for $order_id" if $should_process_fail{$order_id};
    return 1;
});

my $mock_edimessage = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage');
$mock_edimessage->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage';
});
$mock_edimessage->redefine('addToErrorLog', sub {
    my ($self, $filename, $error) = @_;
    push @error_log_calls, { filename => $filename, error => $error };
    return 1;
});

sub run_cron {
    my (%params) = @_;

    @archived_files = ();
    @failed_files = ();
    @processed_orders = ();
    @error_log_calls = ();
    @validated_files = ();
    @logger_errors = ();

    %mock_orders = %{ $params{orders} || {} };
    %should_process_fail = %{ $params{process_fail_for} || {} };

    my $script = File::Spec->catfile($Bin, '..', 'cronjobs', 'runEditXImport.pl');

    my $ok = eval {
        do $script;
        1;
    };

    return ($ok, $@);
}

subtest 'archives successfully processed file' => sub {
    my ($ok, $error) = run_cron(
        orders => {
            'ok1.xml' => { id => 'ok1' },
        },
        process_fail_for => {},
    );

    ok($ok, 'cron script executed without dying');
    is($error, '', 'no eval error from script');
    is_deeply(\@validated_files, ['ok1.xml'], 'file was validated');
    is_deeply(\@processed_orders, ['ok1'], 'order was processed');
    is_deeply(\@archived_files, ['ok1.xml'], 'file was archived');
    is(scalar @failed_files, 0, 'no files moved to fail folder');
    is(scalar @error_log_calls, 0, 'no error log entries created');
};

subtest 'moves file to fail and logs error on processing failure' => sub {
    my ($ok, $error) = run_cron(
        orders => {
            'bad1.xml' => { id => 'bad1' },
        },
        process_fail_for => {
            bad1 => 1,
        },
    );

    ok($ok, 'cron script handled failure without dying');
    is($error, '', 'no eval error from script');
    is_deeply(\@validated_files, ['bad1.xml'], 'file was validated before processing');
    is_deeply(\@processed_orders, ['bad1'], 'order processing was attempted');
    is_deeply(\@failed_files, ['bad1.xml'], 'file moved to fail folder');
    is(scalar @archived_files, 0, 'file was not archived');
    is(scalar @error_log_calls, 1, 'error was logged to edifact_errors');
    is($error_log_calls[0]->{filename}, 'bad1.xml', 'error log call uses filename');
    like($error_log_calls[0]->{error}, qr/Simulated process failure/, 'error log contains processing failure reason');
};

done_testing();
