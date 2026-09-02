#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::MockObject;
use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir($Bin, qw(.. .. .. .. .. ..));

my @messages;
my %process_fail_for;
my %parse_fail_for;
my @updates;
my @error_logs;
my @processed_ids;
my @parsed_raw_inputs;
my %search_filters;
my @claims;

{
    package TestEdiMessageRow;

    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }

    sub id { return $_[0]->{id}; }
    sub raw_msg { return $_[0]->{raw_msg}; }
    sub filename { return $_[0]->{filename}; }
}

{
    package TestOrderObject;

    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }

    sub id { return $_[0]->{id}; }
    sub setFileName { $_[0]->{filename} = $_[1]; return 1; }
}

my $mock_database = Test::MockModule->new('Koha::Database');
$mock_database->redefine('new', sub {
    my $db = Test::MockObject->new();

    my $schema = Test::MockObject->new();
    my $rs = Test::MockObject->new();
    my $search = Test::MockObject->new();

    $search->mock('all', sub { return @messages; });
    $rs->mock('search', sub {
        my ($self, $filters) = @_;
        %search_filters = %{$filters || {}};
        return $search;
    });
    $schema->mock('resultset', sub {
        my ($self, $name) = @_;
        return $rs if $name eq 'EdifactMessage';
        die "Unexpected resultset name: $name";
    });

    $db->mock('schema', sub { return $schema; });
    return $db;
});

my $mock_factory = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice');
$mock_factory->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice';
});

my $mock_parser = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser');
$mock_parser->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser';
});
$mock_parser->redefine('parseDb', sub {
    my ($self, $raw_msg) = @_;
    push @parsed_raw_inputs, $raw_msg;

    return undef if $parse_fail_for{$raw_msg};

    my ($id) = $raw_msg =~ /^msg:(.+)$/;
    $id //= $raw_msg;
    return TestOrderObject->new(id => $id);
});

my $mock_orderprocessor = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor');
$mock_orderprocessor->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor';
});
$mock_orderprocessor->redefine('process', sub {
    my ($self, $order_object) = @_;
    my $id = $order_object->id;
    push @processed_ids, $id;

    die "Simulated process error for $id" if $process_fail_for{$id};
    return 1;
});

my $mock_edimessage = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage');
$mock_edimessage->redefine('new', sub {
    return bless {}, 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage';
});
$mock_edimessage->redefine('claimForProcessing', sub {
    my ($self, $id) = @_;
    push @claims, $id;
    return 1;
});
$mock_edimessage->redefine('update', sub {
    my ($self, $id, $status) = @_;
    push @updates, { id => $id, status => $status };
    return 1;
});
$mock_edimessage->redefine('addToErrorLog', sub {
    my ($self, $id, $error) = @_;
    push @error_logs, { id => $id, error => $error };
    return 1;
});

sub run_cron {
    my (%params) = @_;

    @messages = @{ $params{messages} || [] };
    %process_fail_for = %{ $params{process_fail_for} || {} };
    %parse_fail_for = %{ $params{parse_fail_for} || {} };

    @updates = ();
    @error_logs = ();
    @processed_ids = ();
    @parsed_raw_inputs = ();
    @claims = ();
    %search_filters = ();

    my $script = File::Spec->catfile($Bin, '..', 'cronjobs', 'process_edi_messages.pl');

    my $ok = eval {
        do $script;
        1;
    };

    return ($ok, $@);
}

subtest 'processes NEW messages to OK' => sub {
    my ($ok, $error) = run_cron(
        messages => [
            TestEdiMessageRow->new(id => 1, raw_msg => 'msg:1', filename => 'test_1.xml'),
            TestEdiMessageRow->new(id => 2, raw_msg => 'msg:2', filename => 'test_2.xml'),
        ],
    );

    ok($ok, 'cron script executed without dying');
    is($error, '', 'no eval error from script');
    is($search_filters{message_type}, 'EDItX', 'filters by EDItX message type');
    is($search_filters{status}, 'NEW', 'filters by NEW status');
    is_deeply(\@parsed_raw_inputs, ['msg:1', 'msg:2'], 'raw XML payloads were parsed');
    is_deeply(\@claims, [1, 2], 'messages were claimed for processing');
    is_deeply(\@processed_ids, [1, 2], 'orders were processed');
    is_deeply(
        \@updates,
        [
            { id => 1, status => 'OK' },
            { id => 2, status => 'OK' },
        ],
        'terminal status is set to OK for each message'
    );
    is(scalar @error_logs, 0, 'no error logs written');
};

subtest 'marks FAILED and logs error when processing fails' => sub {
    my ($ok, $error) = run_cron(
        messages => [
            TestEdiMessageRow->new(id => 10, raw_msg => 'msg:10', filename => 'test_10.xml'),
        ],
        process_fail_for => {
            10 => 1,
        },
    );

    ok($ok, 'cron script handles processing failure without dying');
    is($error, '', 'no eval error from script');
    is_deeply(\@claims, [10], 'message was claimed for processing');
    is_deeply(\@processed_ids, [10], 'processing was attempted once');
    is_deeply(
        \@updates,
        [
            { id => 10, status => 'FAILED' },
        ],
        'terminal status transitions to FAILED on processing error'
    );
    is(scalar @error_logs, 1, 'one error log entry written');
    is($error_logs[0]->{id}, 10, 'error log references message id');
    like($error_logs[0]->{error}, qr/Simulated process error/, 'error log contains failure reason');
};

subtest 'marks FAILED and logs error when parsing fails' => sub {
    my ($ok, $error) = run_cron(
        messages => [
            TestEdiMessageRow->new(id => 20, raw_msg => 'bad:xml', filename => 'test_20.xml'),
        ],
        parse_fail_for => {
            'bad:xml' => 1,
        },
    );

    ok($ok, 'cron script handles parse failure without dying');
    is($error, '', 'no eval error from script');
    is_deeply(\@claims, [20], 'message was claimed for processing');
    is(scalar @processed_ids, 0, 'processing not called when parsing fails');
    is_deeply(
        \@updates,
        [
            { id => 20, status => 'FAILED' },
        ],
        'terminal status transitions to FAILED on parse error'
    );
    is(scalar @error_logs, 1, 'one parse error log entry written');
    is($error_logs[0]->{id}, 20, 'parse error log references message id');
    like($error_logs[0]->{error}, qr/Failed to parse XML content/, 'error log contains parse failure reason');
};

done_testing();
