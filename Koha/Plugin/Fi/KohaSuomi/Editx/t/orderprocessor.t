#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 8;
use Test::MockObject;
use Test::MockModule;
use FindBin qw($Bin);
use LWP::UserAgent;
use HTTP::Request;
use Koha::Database;
use Koha::Plugins;
use Koha::Libraries;
use Koha::AuthorisedValues;
use Koha::Acquisition::Budget;
use Koha::Acquisition::Budgets;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice;

my @log_messages;
my @error_messages;

my $mock_logger = Test::MockObject->new();
$mock_logger->set_isa('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger');
$mock_logger->mock('log', sub {
    my ($self, $message) = @_;
    push @log_messages, $message;
});
$mock_logger->mock('logError', sub {
    my ($self, $message) = @_;
    push @error_messages, $message;
});

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

#Find or create test library branch
my $branch = Koha::Libraries->find('OUPK') || $builder->build_object({
    class => 'Koha::Libraries',
    value => { branchname => 'Test Branch', branchcode => 'OUPK' }
});

is($branch->branchcode, 'OUPK', 'Branch code is correct');

#Find or create test location
my $loc = Koha::AuthorisedValues->find({ category => 'LOC', authorised_value => 'AIK' }) || $builder->build_object({
    class => 'Koha::AuthorisedValues',
    value => { category => 'LOC',  authorised_value => 'AIK' }
});

is($loc->authorised_value, 'AIK', 'Authorised value LOC is correct');

# Create test budget
my $budget = Koha::Acquisition::Budgets->find({ budget_period_description => 'OUPKAIK2026' }) || Koha::Acquisition::Budget->new(
    {
        budget_period_startdate   => '2026-01-01',
        budget_period_enddate     => '2026-12-31',
        budget_period_active      => 1,
        budget_period_description => 'OUPKAIK2026',
        budget_period_total       => 10000,
    }
)->store;

is($budget->budget_period_description, 'OUPKAIK2026', 'Budget description is correct');

# create a matching fund so getBudgetId(FundNumber) returns a valid budget_id
my $fund = $schema->resultset('Aqbudget')->find_or_create(
    {
        budget_code      => 'OUPKAIK2026',
        budget_name      => 'Test Fund OUPKAIK2026',
        budget_amount    => 10000,
        budget_period_id => $budget->budget_period_id,
        budget_branchcode => 'OUPK',
    }
);

is($fund->budget_code, 'OUPKAIK2026', 'Fund code is correct');

my $order_processor = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor->new;
# Replace default logger with a test mock to avoid file IO and capture messages.
$order_processor->setLogger($mock_logger);
my $parser = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser->new(
    objectFactory => Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice->new(
        schemaPath => '/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/'
    )
);

subtest 'Successful order processing' => sub {
    plan tests => 2;


    my $order_object = $parser->parseDb(order_mock(
        {
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));

    $order_processor->process($order_object);

    #Log messages should indicate successful processing
    is(scalar(@log_messages) > 0, 1, 'Log messages were captured');
    is (scalar(@error_messages), 0, 'No error messages were captured');

};

subtest 'Invalid product form' => sub {
    plan tests => 1;

    my $order_object = $parser->parseDb(order_mock(
        {
            ProductForm => '99', # Invalid product form to trigger error
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));
    @error_messages = ();
    my $die_message = '';
    eval {
        $order_processor->process($order_object);
        1;
    } or do {
        $die_message = $@;
    };
    
    like(
        $error_messages[0],
        qr/Required parameter: '\$productform' was not set or it was empty\./,
        'logs missing productform error'
    );

};

subtest "Invalid fund number" => sub {
    plan tests => 1;

    my $order_object = $parser->parseDb(order_mock(
        {
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'INVALID_FUND' # Invalid fund number to trigger error
        }
    ));
    @error_messages = ();
    my $die_message = '';
    eval {
        $order_processor->process($order_object);
        1;
    } or do {
        $die_message = $@;
    };

    like($die_message, qr/Cannot insert order: Mandatory parameter budget_id is missing/, 'Die message indicates invalid fund number');

};

subtest "Invalid location" => sub {
    plan tests => 2;

    my $order_object = $parser->parseDb(order_mock(
        {
            ProductForm => 'BK',
            DeliverToLocation => 'HELAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026' # Invalid fund number to trigger error
        }
    ));
    @error_messages = ();
    my $die_message = '';
    eval {
        $order_processor->process($order_object);
        1;
    } or do {
        $die_message = $@;
    };
    like($error_messages[0], qr/Required parameter: '\$destinationlocation' was not set or it was empty\./, 'logs missing destination location error');
    like($error_messages[1], qr/Required parameter: '\$collectioncode' was not set or it was empty\./, 'logs missing collection code error');

};

$schema->storage->txn_rollback;


sub order_mock {
    my ($params) = @_;
    return '<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>12345</ShipNoticeNumber>
        <IssueDateTime>20250205T1730</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>20250205</Date>
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
            <ProductIDType>EAN13</ProductIDType>
            <Identifier>9789510506103</Identifier>
        </ProductID>
        <ProductID>
            <ProductIDType>ISBN</ProductIDType>
            <Identifier>978-951-0-50610-3</Identifier>
        </ProductID>
        <ItemDescription>
            <ProductForm>'.$params->{ProductForm}.'</ProductForm>
            <Title>Izak.</Title>
            <Author>Elstelä, Joel</Author>
            <SeriesTitle></SeriesTitle>
            <VolumeOrPart/>
            <EditionStatement/>
            <CityOfPublication></CityOfPublication>
            <PublisherName>WSOY</PublisherName>
            <YearOfPublication>2026</YearOfPublication>
        </ItemDescription>
        <QuantityShipping>1</QuantityShipping>
        <ReferenceCoded>
            <ReferenceTypeCode>VendorsOrderReference</ReferenceTypeCode>
            <ReferenceNumber>12345</ReferenceNumber>
            <ReferenceDate>05.02.2025</ReferenceDate>
        </ReferenceCoded>
        <PricingDetail>
            <Price>
                <MonetaryAmount>13.68</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>FixedRPIncludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <PricingDetail>
            <Price>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>FixedRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <PricingDetail>
            <Price>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <PriceQualifierCode>SRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <CopyDetail>
            <SubLineNumber>1</SubLineNumber>
            <CopyQuantity>1</CopyQuantity>
            <DeliverToLocation>'.$params->{DeliverToLocation}.'</DeliverToLocation>
            <DestinationLocation>'.$params->{DestinationLocation}.'</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <LocationCode>FI-KOHA;210;1</LocationCode>
            <ReaderInterestCode/>
            <FundDetail>
                <FundNumber>'.$params->{FundNumber}.'</FundNumber>
                <MonetaryAmount>12.00</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
&lt;collection xmlns=&quot;http://www.loc.gov/MARC21/slim&quot;&gt;
 &lt;record&gt;
  &lt;leader&gt;00962nam a22002898a 4500&lt;/leader&gt;
  &lt;controlfield tag=&quot;001&quot;&gt;978-951-0-50610-3&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;003&quot;&gt;FI-Woima&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;005&quot;&gt;20240326101401.0&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;008&quot;&gt;240315s2024    fi                  fin&lt;/controlfield&gt;
  &lt;datafield tag=&quot;020&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;978-951-0-50610-3&lt;/subfield&gt;
   &lt;subfield code=&quot;q&quot;&gt;kovakantinen&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;035&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;(FI-BTJ)7459348&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;040&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;FI-Woima&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;fin&lt;/subfield&gt;
   &lt;subfield code=&quot;e&quot;&gt;rda&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;041&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;fin&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;084&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;ykl&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;84.2&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;100&quot; ind1=&quot;1&quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Elstelä, Joel&lt;/subfield&gt;
   &lt;subfield code=&quot;e&quot;&gt;kirjoittaja&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;245&quot; ind1=&quot;1&quot; ind2=&quot;0&quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Izak.&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;250&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;1. p.&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;260&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;b&quot;&gt;WSOY&lt;/subfield&gt;
   &lt;subfield code=&quot;c&quot;&gt;2024&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;263&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;20240904&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;264&quot; ind1=&quot;3&quot; ind2=&quot;1&quot;&gt;
   &lt;subfield code=&quot;b&quot;&gt;WSOY&lt;/subfield&gt;
   &lt;subfield code=&quot;c&quot;&gt;2024&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;300&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;c&quot;&gt;korkeus 221 mm, leveys 144 mm, paksuus 46 mm&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;336&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;rdacontent&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;teksti&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;txt&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;337&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;rdamedia&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;käytettävissä ilman laitetta&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;n&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;338&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;rdacarrier&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;nide&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;nc&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;500&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;EI VIELÄ ILMESTYNYT, arvioitu ilmestymisaika 04.09.2024&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;856&quot; ind1=&quot;4&quot; ind2=&quot;2&quot;&gt;
   &lt;subfield code=&quot;q&quot;&gt;image&lt;/subfield&gt;
   &lt;subfield code=&quot;u&quot;&gt;https://sopimusasiakkaat.booky.fi/image.php?size=medium&amp;amp;id=9789510506103&lt;/subfield&gt;
   &lt;subfield code=&quot;z&quot;&gt;Kansikuva&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;856&quot; ind1=&quot;4&quot; ind2=&quot;2&quot;&gt;
   &lt;subfield code=&quot;q&quot;&gt;text&lt;/subfield&gt;
   &lt;subfield code=&quot;u&quot;&gt;https://sopimusasiakkaat.booky.fi/description.php?ean=9789510506103&lt;/subfield&gt;
   &lt;subfield code=&quot;z&quot;&gt;Kuvaus&lt;/subfield&gt;
  &lt;/datafield&gt;
 &lt;/record&gt;
&lt;/collection&gt;
                </MessageLine>
            </Message>
            <RequestedBy/>
            <ApprovedBy/>
        </CopyDetail>
    </ItemDetail>
    <Summary>
        <NumberOfLines>1</NumberOfLines>
        <UnitsShipped>1</UnitsShipped>
    </Summary>
</LibraryShipNotice>
    ';
}