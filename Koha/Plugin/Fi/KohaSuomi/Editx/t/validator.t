#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 12;
use Test::MockObject;
use Test::MockModule;
use Test::Exception;
use FindBin qw($Bin);
use File::Temp qw(tempfile tempdir);
use XML::LibXML;

use Koha::Database;
use t::lib::TestBuilder;

use_ok('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator');

my $schema = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

# Create test vendor with EDI account
my $vendor = $schema->resultset('Aqbookseller')->create({
    name => 'TEST Vendor BTJ',
    address1 => 'Test Street 1',
    phone => '+358 9 1234567',
    accountnumber => 'FI-BTJ-TEST',
    notes => 'Test vendor for EDItX testing',
    active => 1,
});

my $vendor_edi = $schema->resultset('VendorEdiAccount')->create({
    description => 'TEST EDI Account',
    vendor_id => $vendor->id,
    san => '12345',
    id_code_qualifier => '91',
    transport => 'FILE',
    orders_enabled => 1,
});

# Create test budget period
my $budget_period = $schema->resultset('Aqbudgetperiod')->create({
    budget_period_startdate => '2026-01-01',
    budget_period_enddate => '2026-12-31',
    budget_period_active => 1,
    budget_period_description => 'TEST BUDGET 2026',
    budget_period_total => 10000,
});

# Create test fund
my $fund = $schema->resultset('Aqbudget')->create({
    budget_code => 'TESTFUND2026',
    budget_name => 'Test Fund 2026',
    budget_amount => 10000,
    budget_period_id => $budget_period->budget_period_id,
});

# Mock config and logger
my $mock_config = Test::MockObject->new();
$mock_config->set_isa('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
my $temp_dir = tempdir(CLEANUP => 1);
$mock_config->mock('getSettings', sub {
    return {
        'settings' => {
            'log_directory' => $temp_dir,
        }
    };
});

# Mock the Config module
my $config_module = Test::MockModule->new('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
$config_module->mock('new', sub { return $mock_config; });

subtest 'Valid EDItX XML validation succeeds' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    lives_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Valid EDItX XML passes validation';
};

subtest 'Invalid XML fails validation' => sub {
    plan tests => 1;
    
    my $xml = '<invalid>xml</invalid>';
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Invalid XML structure fails validation';
};

subtest 'Missing BuyerParty NameLine fails' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<NameLine>Kohala;FI-KOHA;016<\/NameLine>//;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Missing BuyerParty NameLine fails validation';
};

subtest 'Unknown seller fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/BTJ Finland Oy/Unknown Seller Inc/;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Unknown seller name fails validation';
};

subtest 'Invalid vendor SAN fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<Identifier>12345<\/Identifier>/<Identifier>99999<\/Identifier>/;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Invalid vendor SAN fails validation';
};

subtest 'Missing FundNumber fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<FundNumber>TESTFUND2026<\/FundNumber>//;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Missing FundNumber fails validation';
};

subtest 'Invalid fund code fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/TESTFUND2026/INVALIDFUND/g;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Invalid fund code fails validation';
};

subtest 'Missing ProductForm fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<ProductForm>BK<\/ProductForm>//;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Missing ProductForm fails validation';
};

subtest 'Missing MessageType fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<MessageType>04<\/MessageType>//;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Missing MessageType fails validation';
};

subtest 'Invalid MessageType value fails validation' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<MessageType>04<\/MessageType>/<MessageType>99<\/MessageType>/;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    dies_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'Invalid MessageType value fails validation';
};

subtest 'MessageType 01 passes without MARCXML' => sub {
    plan tests => 1;
    
    my $xml = valid_editx_xml();
    $xml =~ s/<MessageType>04<\/MessageType>/<MessageType>01<\/MessageType>/;
    $xml =~ s/<MessageLine>.*?<\/MessageLine>/<MessageLine>Simple message<\/MessageLine>/s;
    
    my ($fh, $filename) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $fh $xml;
    close $fh;
    
    lives_ok {
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator::validateEditx($filename);
    } 'MessageType 01 passes validation without MARCXML';
};

$schema->storage->txn_rollback;

sub valid_editx_xml {
    return '<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>TEST001</ShipNoticeNumber>
        <IssueDateTime>20260515T1200</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>20260515</Date>
            <DateQualifierCode>Shipped</DateQualifierCode>
        </DateCoded>
        <BuyerParty>
            <PartyID>
                <PartyIDType>VendorAssignedID</PartyIDType>
                <Identifier>12345</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>Kohala;FI-KOHA;016</NameLine>
            </PartyName>
        </BuyerParty>
        <SellerParty>
            <PartyID>
                <PartyIDType>BuyerAssignedID</PartyIDType>
                <Identifier>FI-BTJ</Identifier>
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
            <DeliverToLocation>TESTLIB2026</DeliverToLocation>
            <DestinationLocation>TESTLIB2026</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <FundDetail>
                <FundNumber>TESTFUND2026</FundNumber>
                <MonetaryAmount>12.00</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
&lt;collection xmlns=&quot;http://www.loc.gov/MARC21/slim&quot;&gt;
 &lt;record&gt;
  &lt;leader&gt;00962nam a22002898a 4500&lt;/leader&gt;
  &lt;controlfield tag=&quot;001&quot;&gt;978-951-0-50610-3&lt;/controlfield&gt;
  &lt;datafield tag=&quot;020&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;978-951-0-50610-3&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;100&quot; ind1=&quot;1&quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Test Author&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;245&quot; ind1=&quot;1&quot; ind2=&quot;0&quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Test Book&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;260&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;b&quot;&gt;Test Publisher&lt;/subfield&gt;
   &lt;subfield code=&quot;c&quot;&gt;2026&lt;/subfield&gt;
  &lt;/datafield&gt;
 &lt;/record&gt;
&lt;/collection&gt;
                </MessageLine>
            </Message>
        </CopyDetail>
    </ItemDetail>
    <Summary>
        <NumberOfLines>1</NumberOfLines>
        <UnitsShipped>1</UnitsShipped>
    </Summary>
</LibraryShipNotice>
    ';
}
