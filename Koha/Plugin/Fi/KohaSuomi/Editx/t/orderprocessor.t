#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More tests => 14;
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

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
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

my $authoriser = Koha::Patrons->search({}, { order_by => { -asc => 'borrowernumber' }, rows => 1 })->single || $builder->build_object({
    class => 'Koha::Patrons',
    value => { surname => 'Test', firstname => 'Authoriser' }
});

my $mock_authoriser = $authoriser->borrowernumber;
my $mock_location = 'AIK';

my $mock_config = Test::MockObject->new();
$mock_config->set_isa('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config');
$mock_config->mock('getLogDir', sub {
    return '/tmp'; # Return a temp directory for logs to avoid file IO during tests
});
$mock_config->mock('getSettings', sub {
    return {
        'settings' => {
            'import_tmp_path' => '/tmp/editx/tmp',
            'import_load_path' => '/tmp/editx/load',
            'import_archive_path' => '/tmp/editx/archive',
            'import_failed_path' => '/tmp/editx/failed',
            'import_failed_archived_path' => '/tmp/editx/failed_archive',
            'authoriser' => $mock_authoriser,
            'allowed_locations' => $mock_location,
            'productform_alternative_triggers' => '',
            'automatch_biblios' => 'yes',
            'use_finna_materialtype' => 'no',
            'log_directory' => '/tmp',
        },
        'notifications' => {
            'mailto' => 'test@example.com',
            'mailfrom' => 'noreply@example.com',
        }
    };
});
$mock_config->mock('getUseAutomatchBiblios', sub {
    return 'yes';
});
$mock_config->mock('getUseFinnaMaterials', sub {
    return 'no';
});

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

# Find or create test vendor
my $vendor = $schema->resultset('Aqbookseller')->find({ name => 'TEST Vendor BTJ' }) || $schema->resultset('Aqbookseller')->create({
    name => 'TEST Vendor BTJ',
    address1 => 'Test Street 1',
    phone => '+358 9 1234567',
    accountnumber => 'FI-BTJ-TEST',
    notes => 'Test vendor for EDItX testing',
    active => 1,
});

is($vendor->name, 'TEST Vendor BTJ', 'Vendor name is correct');

# Create vendor EDI account with SAN 12345 and qualifier 91
my $vendor_edi = $schema->resultset('VendorEdiAccount')->find({ vendor_id => $vendor->id }) || $schema->resultset('VendorEdiAccount')->create({
    description => 'TEST EDI Account',
    vendor_id => $vendor->id,
    san => '12345',
    id_code_qualifier => '91',
    transport => 'FILE',
    orders_enabled => 1,
});

is($vendor_edi->san, '12345', 'Vendor EDI SAN is correct');

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
$order_processor->setConfig($mock_config);
my $parser = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser->new(
    objectFactory => Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice->new(
        schemaPath => '/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/'
    )
);

subtest 'Missing configurations' => sub {
    plan tests => 4;

    $mock_authoriser = '';
    
    $order_processor->setConfig($mock_config);
    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));

    my $error = order_processor_helper($order_object);
    is($error, "Authoriser is not configured in plugin settings.", 'dies with missing authoriser');

    $mock_authoriser = $authoriser->borrowernumber;
    $order_processor->setConfig($mock_config);

    $error = order_processor_helper($order_object);
    is($error, 1, 'no error after setting authoriser');

    $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));

    $error = order_processor_helper($order_object);
    is($error, "Basket name could not be determined from shipment notice.", 'dies with missing basket name');

    $mock_location = '';
    $order_processor->setConfig($mock_config);
    $error = order_processor_helper($order_object);
    is($error, "Allowed locations are not configured in plugin settings.", 'dies with missing allowed locations');

    $mock_location = 'AIK';
    $order_processor->setConfig($mock_config);

};

subtest 'Successful order processing' => sub {
    plan tests => 2;

    @error_messages = ();

    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));

    order_processor_helper($order_object);

    is(scalar(@log_messages) > 0, 1, 'Log messages were captured');
    is (scalar(@error_messages), 0, 'No error messages were captured');

};

subtest 'Invalid product form' => sub {
    plan tests => 1;

    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',    
            ProductForm => '99', # Invalid product form to trigger error
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));
    
    order_processor_helper($order_object);
    
    like(
        $error_messages[0],
        qr/Required parameter: '\$productform' was not set or it was empty\./,
        'logs missing productform error'
    );

};

subtest "Invalid fund number" => sub {
    plan tests => 2;

    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'INVALID_FUND' # Invalid fund number to trigger error
        }
    ));
    
    order_processor_helper($order_object);

    like($error_messages[0], qr/Budget ID not found for fund number: INVALID_FUND/, 'Error message indicates invalid fund number');

     $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026' # Valid fund number to ensure processing continues
        }

    ));

    order_processor_helper($order_object);

    is(scalar(@error_messages), 0, 'No error messages were captured with valid fund number');

};

subtest "Invalid location" => sub {
    plan tests => 2;

    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'HELAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026' # Invalid fund number to trigger error
        }
    ));
    @error_messages = ();
    eval {
        $order_processor->process($order_object);
        1;
    } or do {
    };
    ok(grep(/destinationlocation/, @error_messages), 'logs missing destination location error');
    ok(grep(/collectioncode/, @error_messages), 'logs missing collection code error');

};

subtest 'Error messages reference EDItX XML element paths' => sub {
    plan tests => 4;

    # Create orders with unique ISBNs so automatch does not find existing biblios
    @error_messages = ();
    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ISBN  => '978-951-0-99999-0',
            EAN   => '9789510999990',
            ProductForm => 'BK',
            Title => '',
            NameLine => 'BTJ Finland Oy',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));

    my $error = order_processor_helper($order_object);
    like($error, qr/Missing from EDItX message/, 'title: error references EDItX message');
    like($error, qr/ItemDescription\/Title/, 'title: error contains XML path for Title');

    # Unknown NameLine → no vendor class matches, base LibraryShipNotice used.
    # Base ItemDetail::getNotes() returns '' → triggers notes validation with
    # Header/SellerParty/PartyName/NameLine path.
    @error_messages = ();
    $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ISBN  => '978-951-0-99999-1',
            EAN   => '9789510999991',
            ProductForm => 'BK',
            Title => 'Test Title',
            NameLine => '',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026'
        }
    ));

    $error = order_processor_helper($order_object);
    like($error, qr/Missing from EDItX message/, 'nameline: error references EDItX message');
    like($error, qr/Header\/SellerParty\/PartyName\/NameLine/, 'nameline: error contains XML path for NameLine');
};

subtest 'UTF-8 MARC from parseDb is preserved' => sub {
    plan tests => 3;

    $mock_config->mock('getUseAutomatchBiblios', sub { return 'no'; });

    my ($before_biblio) = $schema->storage->dbh->selectrow_array(
        q{SELECT COALESCE(MAX(biblionumber),0) FROM biblio_metadata}
    );

    my $order_object = $parser->parseDb(order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026',
            Author => 'Münchner Symphoniker; Joseph Bastian',
            Title => 'Gaelic Symphony &amp; Vocal Works',
            MarcAuthor => 'Münchner Symphoniker; Joseph Bastian',
            MarcTitle => 'Gaelic Symphony &amp;amp; Vocal Works',
            MarcPhysical => '1 CD-äänilevy',
        }
    ));

    order_processor_helper($order_object);
    is(scalar(@error_messages), 0, 'No error messages while processing UTF-8 MARC');

    my ($metadata) = $schema->storage->dbh->selectrow_array(
        q{SELECT metadata FROM biblio_metadata WHERE biblionumber > ? ORDER BY biblionumber DESC LIMIT 1},
        undef,
        $before_biblio
    );

    ok(defined $metadata && $metadata ne '', 'Stored MARC metadata exists');
    like($metadata, qr/Münchner Symphoniker; Joseph Bastian.*1 CD-äänilevy/s, 'Stored MARC metadata keeps UTF-8 characters');

    $mock_config->mock('getUseAutomatchBiblios', sub { return 'yes'; });
};

subtest 'UTF-8 MARC from parseFile is preserved' => sub {
    plan tests => 4;

    @error_messages = ();
    $mock_config->mock('getUseAutomatchBiblios', sub { return 'no'; });

    my ($before_biblio) = $schema->storage->dbh->selectrow_array(
        q{SELECT COALESCE(MAX(biblionumber),0) FROM biblio_metadata}
    );

    # Create temporary file with UTF-8 content
    use File::Temp qw(tempfile);
    my ($fh, $tempfile) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    binmode($fh, ':encoding(UTF-8)');
    print $fh order_mock(
        {
            ShipNoticeNumber => '12345',
            ProductForm => 'BK',
            DeliverToLocation => 'OUPKAIK2026',
            DestinationLocation => 'OUPKAIK2026',
            FundNumber => 'OUPKAIK2026',
            Author => 'Tuomarila, Alexi',
            Title => 'Departing the wasteland',
            MarcAuthor => 'Tuomarila, Alexi',
            MarcTitle => 'Departing the wasteland',
            MarcPhysical => '1 CD-äänilevy',
        }
    );
    close $fh;

    my $order_object = $parser->parseFile($tempfile);
    ok($order_object, 'parseFile returned an object');

    order_processor_helper($order_object);
    if (@error_messages) {
        warn "ERRORS: " . join(", ", @error_messages) . "\n";
    }
    is(scalar(@error_messages), 0, 'No error messages while processing UTF-8 MARC from file');

    my ($metadata) = $schema->storage->dbh->selectrow_array(
        q{SELECT metadata FROM biblio_metadata WHERE biblionumber > ? ORDER BY biblionumber DESC LIMIT 1},
        undef,
        $before_biblio
    );

    ok(defined $metadata && $metadata ne '', 'Stored MARC metadata from file exists');
    like($metadata, qr/Tuomarila, Alexi.*1 CD-äänilevy/s, 'Stored MARC metadata from file keeps UTF-8 characters');

    $mock_config->mock('getUseAutomatchBiblios', sub { return 'yes'; });
};

$schema->storage->txn_rollback;


sub order_mock {
    my ($params) = @_;
    return '<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>'.$params->{ShipNoticeNumber}.'</ShipNoticeNumber>
        <IssueDateTime>20250205T1730</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>20250205</Date>
            <DateQualifierCode>Shipped</DateQualifierCode>
        </DateCoded>
        <BuyerParty>
            <PartyID>
                <PartyIDType>VendorAssignedID</PartyIDType>
                <Identifier>'.$params->{ShipNoticeNumber}.'</Identifier>
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
                <NameLine>'.($params->{NameLine} // 'BTJ Finland Oy').'</NameLine>
            </PartyName>
        </SellerParty>
    </Header>
    <ItemDetail>
        <LineNumber>1</LineNumber>
        <ProductID>
            <ProductIDType>EAN13</ProductIDType>
            <Identifier>'.($params->{EAN} // '9789510506103').'</Identifier>
        </ProductID>
        <ProductID>
            <ProductIDType>ISBN</ProductIDType>
            <Identifier>'.($params->{ISBN} // '978-951-0-50610-3').'</Identifier>
        </ProductID>
        <ItemDescription>
            <ProductForm>'.$params->{ProductForm}.'</ProductForm>
            <Title>'.($params->{Title} // 'Izak.').'</Title>
            <Author>'.($params->{Author} // 'Elstelä, Joel').'</Author>
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
   &lt;controlfield tag=&quot;001&quot;&gt;'.($params->{ISBN} // '978-951-0-50610-3').'&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;003&quot;&gt;FI-Woima&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;005&quot;&gt;20240326101401.0&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;008&quot;&gt;240315s2024    fi                  fin&lt;/controlfield&gt;
  &lt;datafield tag=&quot;020&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
    &lt;subfield code=&quot;a&quot;&gt;'.($params->{ISBN} // '978-951-0-50610-3').'&lt;/subfield&gt;
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
    &lt;subfield code=&quot;a&quot;&gt;'.($params->{MarcAuthor} // 'Elstelä, Joel').'&lt;/subfield&gt;
   &lt;subfield code=&quot;e&quot;&gt;kirjoittaja&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;245&quot; ind1=&quot;1&quot; ind2=&quot;0&quot;&gt;
    &lt;subfield code=&quot;a&quot;&gt;'.($params->{MarcTitle} // 'Izak.').'&lt;/subfield&gt;
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
    &lt;subfield code=&quot;c&quot;&gt;'.($params->{MarcPhysical} // 'korkeus 221 mm, leveys 144 mm, paksuus 46 mm').'&lt;/subfield&gt;
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

sub order_processor_helper {
    my $object = shift;
    @log_messages = ();
    @error_messages = ();
    eval {
        $order_processor->process($object);
        1;
    } or do {
        my $error = $@ || 'Unknown error';
        chomp $error;
        $error =~ s/ at .+? line \d+\.?$//;
        return $error;
    };
    return 1;
}