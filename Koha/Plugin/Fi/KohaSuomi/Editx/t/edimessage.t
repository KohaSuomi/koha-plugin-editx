#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use XML::LibXML;
use DateTime;

use Koha::Database;
use Koha::Plugins;
use t::lib::TestBuilder;

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $edi_message = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage->new;

# Unique per run: the SAN must not collide with EDI accounts that are really
# in the database, findVendorId does not order its result.
my $test_vendor_san   = 'EDXTEST' . $$;
my $unknown_vendor_san = 'EDXUNKNOWN' . $$;

eval { $schema->resultset('EdifactMessage')->first };
if ($@) {
    plan skip_all => 'No edifact_messages table available: ' . $@;
}

sub setup_vendor_fixture {
    my $vendor = $schema->resultset('Aqbookseller')->create({
        name           => 'TEST Vendor EDItX',
        address1       => 'Test Street 1',
        phone          => '+358 9 1234567',
        accountnumber  => 'FI-EDX-TEST',
        notes          => 'Test vendor for EDItX testing',
        active         => 1,
    });

    $schema->resultset('VendorEdiAccount')->create({
        description       => 'TEST EDI Account',
        vendor_id         => $vendor->id,
        san               => $test_vendor_san,
        id_code_qualifier => '91',
        transport         => 'FILE',
        orders_enabled    => 1,
    });

    return $vendor;
}

# Parameterized ship notice, the same shape editxcontroller.t posts through the REST API.
sub generate_shipnotice_xml {
    my %args = @_;

    my $ship_notice_number = exists $args{ship_notice_number} ? $args{ship_notice_number} : '661424';
    my $issue_datetime     = exists $args{issue_datetime}     ? $args{issue_datetime}     : '20261014T1711';
    my $vendor_san         = exists $args{vendor_san}         ? $args{vendor_san}         : $test_vendor_san;
    my $fund_number        = exists $args{fund_number}        ? $args{fund_number}        : 'OUPKAIK2026';

    return '<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>' . $ship_notice_number . '</ShipNoticeNumber>
        <IssueDateTime>' . $issue_datetime . '</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>20261014</Date>
            <DateQualifierCode>Shipped</DateQualifierCode>
        </DateCoded>
        <BuyerParty>
            <PartyID>
                <PartyIDType>VendorAssignedID</PartyIDType>
                <Identifier>' . $vendor_san . '</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>Kohala;FI-KOHA;016</NameLine>
            </PartyName>
        </BuyerParty>
        <SellerParty>
            <PartyID>
                <PartyIDType>BuyerAssignedID</PartyIDType>
                <Identifier>FI-TEST</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>BTJ Finland Oy</NameLine>
            </PartyName>
        </SellerParty>
    </Header>
    <ItemDetail>
        <LineNumber>1</LineNumber>
        <ProductID>
            <ProductIDType>ISBN</ProductIDType>
            <Identifier>978-951-0-50610-3</Identifier>
        </ProductID>
        <ItemDescription>
            <ProductForm>BK</ProductForm>
            <Title>Test Book</Title>
            <Author>Test Author</Author>
            <PublisherName>Test Publisher</PublisherName>
            <YearOfPublication>2026</YearOfPublication>
        </ItemDescription>
        <QuantityShipping>1</QuantityShipping>
        <PricingDetail>
            <Price>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <PriceQualifierCode>FixedRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <CopyDetail>
            <SubLineNumber>1</SubLineNumber>
            <CopyQuantity>1</CopyQuantity>
            <DeliverToLocation>AIK</DeliverToLocation>
            <DestinationLocation>AIK</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <FundDetail>
                <FundNumber>' . $fund_number . '</FundNumber>
                <MonetaryAmount>12.00</MonetaryAmount>
            </FundDetail>
        </CopyDetail>
    </ItemDetail>
    <Summary>
        <NumberOfLines>1</NumberOfLines>
        <UnitsShipped>1</UnitsShipped>
    </Summary>
</LibraryShipNotice>
    ';
}

sub parse_shipnotice {
    return XML::LibXML->new->parse_string(generate_shipnotice_xml(@_));
}

sub create_message {
    my ($filename, $status, $vendor_id) = @_;

    return $schema->resultset('EdifactMessage')->create({
        message_type  => 'EDItX',
        transfer_date => DateTime->now,
        raw_msg       => generate_shipnotice_xml(),
        filename      => $filename,
        status        => $status,
        vendor_id     => $vendor_id,
    });
}

subtest 'constructFilename builds the message identifier' => sub {
    plan tests => 3;

    my $xml = parse_shipnotice(
        ship_notice_number => '661424',
        issue_datetime     => '20261014T1711',
    );

    is(
        $edi_message->constructFilename($xml, undef),
        '661424_20261014T1711',
        'identifier is built from ShipNoticeNumber and IssueDateTime'
    );
    is(
        $edi_message->constructFilename($xml, 'kohauser'),
        'kohauser_661424_20261014T1711',
        'the REST API prefixes the identifier with the user'
    );
    is(
        $edi_message->constructFilename(parse_shipnotice(), undef),
        '661424_20261014T1711',
        'the same values produce the same identifier for a re-sent order'
    );
};

subtest 'findVendorId resolves the SAN to a vendor' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;

    my $vendor = setup_vendor_fixture();

    is(
        $edi_message->findVendorId(parse_shipnotice()),
        $vendor->id,
        'vendor is found by the SAN of the buyer party'
    );
    is(
        $edi_message->findVendorId(parse_shipnotice(vendor_san => '99999')),
        undef,
        'unknown SAN does not resolve to a vendor'
    );
    is(
        $edi_message->findVendorId(parse_shipnotice(vendor_san => $test_vendor_san, ship_notice_number => '669999')),
        $vendor->id,
        'the vendor is found independently of the ship notice number'
    );

    $schema->storage->txn_rollback;
};

subtest 'duplicate lookup is driven by the message status' => sub {
    plan tests => 5;
    $schema->storage->txn_begin;

    my $vendor = setup_vendor_fixture();

    ok(
        !$edi_message->duplicateExists('661424_20261014T1711'),
        'an unknown filename is not a duplicate'
    );

    my $pending = create_message('661424_20261014T1711', 'NEW', $vendor->id);
    ok(
        $edi_message->duplicateExists($pending->filename),
        'a message waiting for processing counts as a duplicate'
    );

    my $processed = create_message('661424_20261014T1800', 'OK', $vendor->id);
    ok(
        $edi_message->duplicateExists($processed->filename),
        'a message that was processed successfully counts as a duplicate'
    );

    my $failed = create_message('661424_20261014T1900', 'FAILED', $vendor->id);
    ok(
        !$edi_message->duplicateExists($failed->filename),
        'a message whose processing failed does not block a corrected re-send'
    );

    my $without_status = create_message('661424_20261014T2000', undef, $vendor->id);
    ok(
        $edi_message->duplicateExists($without_status->filename),
        'a message without a status counts as a duplicate'
    );

    $schema->storage->txn_rollback;
};

subtest 'update changes the status of a message' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my $vendor  = setup_vendor_fixture();
    my $message = create_message('661424_20261014T1711', 'NEW', $vendor->id);

    is($edi_message->update($message->id, 'FAILED'), 1, 'the status is updated by id');
    is($message->get_from_storage->status, 'FAILED', 'the message is now failed');

    is($edi_message->update($message->filename, 'OK'), 1, 'the status is updated by filename for older callers');
    is($message->get_from_storage->status, 'OK', 'the message is now processed');

    $schema->storage->txn_rollback;
};

subtest 'addToErrorLog attaches the error to the message' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my $vendor  = setup_vendor_fixture();
    my $message = create_message('661424_20261014T1711', 'FAILED', $vendor->id);

    $edi_message->addToErrorLog($message->id, 'Order could not be created');
    my @errors = $schema->resultset('EdifactError')->search({ message_id => $message->id })->all;
    is(scalar @errors, 1, 'an error row is written for the message id');
    is($errors[0]->details, 'Order could not be created', 'the error text is stored');

    $edi_message->addToErrorLog($message->filename, 'File already imported');
    @errors = $schema->resultset('EdifactError')->search({ message_id => $message->id })->all;
    is(scalar @errors, 2, 'the error is also attached when only the filename is known');

    $edi_message->addToErrorLog('missing_file.xml', 'Nothing to attach this to');
    is(
        $schema->resultset('EdifactError')->search({ details => 'Nothing to attach this to' })->count,
        0,
        'an unknown identifier is silently ignored'
    );

    $schema->storage->txn_rollback;
};

subtest 'newEdiMessage stores a ship notice' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my $vendor = setup_vendor_fixture();

    $edi_message->newEdiMessage(parse_shipnotice(), 'kohauser');

    my $message = $schema->resultset('EdifactMessage')->find(
        { filename => 'kohauser_661424_20261014T1711' }
    );
    ok($message, 'the message was stored with the identifier from the ship notice');
    is($message->status, 'NEW', 'the message waits for processing');
    is($message->vendor_id, $vendor->id, 'the message is linked to the vendor of the SAN');
    like($message->raw_msg, qr/<ShipNoticeNumber>661424<\/ShipNoticeNumber>/, 'the raw ship notice is stored');

    $schema->storage->txn_rollback;
};

subtest 'newEdiMessage rejects a re-sent message' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    setup_vendor_fixture();

    $edi_message->newEdiMessage(parse_shipnotice(), 'kohauser');

    my $error;
    eval { $edi_message->newEdiMessage(parse_shipnotice(), 'kohauser') };
    $error = $@;
    like(
        $error,
        qr/A message with the same filename already exists/,
        'a message with the same ShipNoticeNumber and IssueDateTime is rejected'
    );
    is(
        $schema->resultset('EdifactMessage')->search(
            { filename => 'kohauser_661424_20261014T1711' }
        )->count,
        1,
        'the rejected message was not stored'
    );

    $schema->storage->txn_rollback;
};

subtest 'newEdiMessage requires a known vendor' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    setup_vendor_fixture();

    my $error;
    eval {
        $edi_message->newEdiMessage(
            parse_shipnotice(vendor_san => '99999'),
            'kohauser'
        );
    };
    $error = $@;
    like($error, qr/Could not find matching vendor/, 'an unknown SAN is rejected');
    is(
        $schema->resultset('EdifactMessage')->search(
            { filename => 'kohauser_661424_20261014T1711' }
        )->count,
        0,
        'nothing was stored for an unknown vendor'
    );

    $schema->storage->txn_rollback;
};

done_testing();
