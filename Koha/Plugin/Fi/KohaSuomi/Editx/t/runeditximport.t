#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);

use Koha::Plugins;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

my $tmp_dir     = tempdir(CLEANUP => 1);
my $archive_dir = tempdir(CLEANUP => 1);
my $failed_dir  = tempdir(CLEANUP => 1);

my $test_xml = '<?xml version="1.0"?>
<LibraryShipNotice>
  <Header>
    <ShipNoticeNumber>SN-12345</ShipNoticeNumber>
    <IssueDateTime>2024-01-15T10:00:00</IssueDateTime>
    <BuyerParty>
      <PartyID>
        <PartyIDType>VendorAssignedID</PartyIDType>
        <Identifier>TESTVENDOR</Identifier>
      </PartyID>
    </BuyerParty>
  </Header>
</LibraryShipNotice>';

my @create_calls;
my @error_log_calls;
my @log_calls;
my $mock_find_vendor = 'TEST_VENDOR_ID';
my $mock_dup_exists  = 0;

my $mock_config = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
$mock_config->redefine('new', sub { bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config' });
$mock_config->redefine('getSettings', sub {
    return {
        settings => {
            log_directory        => '/tmp',
            import_tmp_path      => $tmp_dir,
            import_archive_path  => $archive_dir,
            import_failed_path   => $failed_dir,
        }
    };
});

my $mock_logger = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger');
$mock_logger->redefine('new',   sub { bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger' });
$mock_logger->redefine('log',       sub { my ($self, $msg) = @_; push @log_calls, $msg; return 1; });
$mock_logger->redefine('logError',  sub { my ($self, $msg) = @_; push @log_calls, $msg; return 1; });

my $mock_edi = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage');
$mock_edi->redefine('new',              sub { bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage' });
$mock_edi->redefine('constructFilename', sub { return 'SN-12345_2024-01-15T10:00:00' });
$mock_edi->redefine('findVendorId',      sub { return $mock_find_vendor });
$mock_edi->redefine('duplicateExists',   sub { return $mock_dup_exists });
$mock_edi->redefine('create', sub {
    my ($self, $raw, $filename, $vendor_id) = @_;
    push @create_calls, { raw => $raw, filename => $filename, vendor_id => $vendor_id };
});
$mock_edi->redefine('addToErrorLog', sub {
    my ($self, $identifier, $error) = @_;
    push @error_log_calls, { identifier => $identifier, error => $error };
});

sub run_cron {
    my (%params) = @_;

    @create_calls     = ();
    @error_log_calls  = ();
    @log_calls        = ();

    $mock_find_vendor = exists $params{vendor_id} ? $params{vendor_id} : 'TEST_VENDOR_ID';
    $mock_dup_exists  = exists $params{duplicate_exists} ? $params{duplicate_exists} : 0;

    my $script = File::Spec->catfile($Bin, '..', 'cronjobs', 'runEditXImport.pl');

    my $ok = eval {
        do $script;
        1;
    };

    return ($ok, $@);
}

sub clean_dirs {
    unlink glob "$tmp_dir/*.xml";
    unlink glob "$archive_dir/*.xml";
    unlink glob "$failed_dir/*.xml";
}

subtest 'saves file and archives it' => sub {
    clean_dirs();
    write_file("$tmp_dir/test1.xml", $test_xml);

    my ($ok, $error) = run_cron();

    ok($ok, 'script executed without dying');
    is($error, '', 'no eval error from script');
    is(scalar @create_calls, 1, 'create was called once');
    is($create_calls[0]->{filename}, 'SN-12345_2024-01-15T10:00:00', 'filename matches constructed value');
    is($create_calls[0]->{vendor_id}, 'TEST_VENDOR_ID', 'vendor_id passed to create');
    ok(!-f "$tmp_dir/test1.xml", 'file was moved out of tmp');
    ok(-f "$archive_dir/test1.xml", 'file was moved to archive');
    is(scalar @error_log_calls, 0, 'no error log entries');
};

subtest 'skips duplicate file' => sub {
    clean_dirs();
    write_file("$tmp_dir/test2.xml", $test_xml);

    my ($ok, $error) = run_cron(duplicate_exists => 1);

    ok($ok, 'script executed without dying');
    is(scalar @create_calls, 0, 'create was not called for duplicate');
    ok(!-f "$tmp_dir/test2.xml", 'file was moved out of tmp');
    ok(-f "$failed_dir/test2.xml", 'file was moved to failed');
    is(scalar @error_log_calls, 0, 'no errors logged for duplicate');
};

subtest 'skips empty file' => sub {
    clean_dirs();
    write_file("$tmp_dir/empty.xml", '');

    my ($ok, $error) = run_cron();

    ok($ok, 'script executed without dying');
    is(scalar @create_calls, 0, 'create was not called for empty file');
    ok(!-f "$tmp_dir/empty.xml", 'empty file was moved out of tmp');
    ok(-f "$failed_dir/empty.xml", 'empty file was moved to failed');
    is(scalar @error_log_calls, 0, 'no errors logged for empty file');
};

subtest 'logs error when vendor not found' => sub {
    clean_dirs();
    write_file("$tmp_dir/test3.xml", $test_xml);

    my ($ok, $error) = run_cron(vendor_id => undef);

    ok($ok, 'script handled missing vendor without dying');
    is(scalar @create_calls, 0, 'create was not called');
    is(scalar @error_log_calls, 1, 'error was logged');
    like($error_log_calls[0]->{error}, qr/Could not find matching vendor/, 'error mentions missing vendor');
    ok(-f "$failed_dir/test3.xml", 'file was moved to failed');
};

subtest 'handles empty tmp directory' => sub {
    clean_dirs();
    my ($ok, $error) = run_cron();

    ok($ok, 'script executed without dying on empty dir');
    is($error, '', 'no eval error from script');
    is(scalar @create_calls, 0, 'create was not called');
};

done_testing();
