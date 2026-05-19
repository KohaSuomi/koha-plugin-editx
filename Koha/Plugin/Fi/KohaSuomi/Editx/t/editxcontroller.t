#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 10;
use LWP::UserAgent;
use HTTP::Request;
use Koha::Database;
use Koha::Libraries;
use Koha::AuthorisedValues;
use Koha::Acquisition::Budget;
use Koha::Acquisition::Budgets;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $test_branchcode = 'OUPK';
my $test_location   = 'AIK';
my $test_fund_code  = 'OUPKAIK2026';
my $test_vendor_san = '12345';

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

sub setup_editx_fixture_data {
    my $branch = Koha::Libraries->find($test_branchcode) || $builder->build_object({
        class => 'Koha::Libraries',
        value => { branchname => 'Test Branch', branchcode => $test_branchcode }
    });

    my $loc = Koha::AuthorisedValues->find({ category => 'LOC', authorised_value => $test_location }) || $builder->build_object({
        class => 'Koha::AuthorisedValues',
        value => { category => 'LOC', authorised_value => $test_location }
    });

    my $vendor = $schema->resultset('Aqbookseller')->find({ name => 'TEST Vendor BTJ' }) || $schema->resultset('Aqbookseller')->create({
        name => 'TEST Vendor BTJ',
        address1 => 'Test Street 1',
        phone => '+358 9 1234567',
        accountnumber => 'FI-BTJ-TEST',
        notes => 'Test vendor for EDItX testing',
        active => 1,
    });

    $schema->resultset('VendorEdiAccount')->find({ vendor_id => $vendor->id }) || $schema->resultset('VendorEdiAccount')->create({
        description => 'TEST EDI Account',
        vendor_id => $vendor->id,
        san => $test_vendor_san,
        id_code_qualifier => '91',
        transport => 'FILE',
        orders_enabled => 1,
    });

    my $budget = Koha::Acquisition::Budgets->find({ budget_period_description => $test_fund_code }) || Koha::Acquisition::Budget->new(
        {
            budget_period_startdate   => '2026-01-01',
            budget_period_enddate     => '2026-12-31',
            budget_period_active      => 1,
            budget_period_description => $test_fund_code,
            budget_period_total       => 10000,
        }
    )->store;

    $schema->resultset('Aqbudget')->find_or_create(
        {
            budget_code       => $test_fund_code,
            budget_name       => 'Test Fund OUPKAIK2026',
            budget_amount     => 10000,
            budget_period_id  => $budget->budget_period_id,
            budget_branchcode => $branch->branchcode,
        }
    );
}

subtest 'POST valid XML file' => sub {
    plan tests => 3;
    # Begin transaction
    $schema->storage->txn_begin;
    setup_editx_fixture_data();

    # Create a test patron with a password and permissions
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });

    # Get the patron's userid
    my $userid    = $patron->userid;

    # Get XML body
    my $xml_body = generate_shipnotice_xml();

    # Call the API endpoint with users credentials and XML body
    my $editx_content = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(201)
        ->json_is({
            message => 'Data saved successfully',
        });
    $editx_content = $editx_content->tx->res->json;

    # Rollback the transaction, so we don't leave test data in the database
    $schema->storage->txn_rollback;
};


subtest 'Invalid user credentials' => sub {
    plan tests => 2;
    # Attempt to access the API with no permissions
    $schema->storage->txn_begin;
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 0 }    #no permissions
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => '<xml></xml>')
        ->status_is(403);
    
    $schema->storage->txn_rollback;
};

subtest 'POST invalid XML file' => sub {
    plan tests => 3;
    # Attempt to post an invalid XML file
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # Get invalid XML body
    my $xml_body = generate_shipnotice_xml(well_formed => 0);
    
    # Should return 500 for invalid XML
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(500)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

subtest 'PUT update Editx content' => sub {
    plan tests => 12;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # Create a test Editx content first
    my $xml_body = generate_shipnotice_xml();
    
    # Create content
    my $response = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(201);
    
    # Get the created content ID by listing all contents
    my $list_response = $t->get_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx")
        ->status_is(200);
    my $contents = $list_response->tx->res->json;
    my $content_id = $contents->[0]->{id};
    
    # Test update with valid status
    $t->put_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx/$content_id" => json => { status => 'completed' })
        ->status_is(200)
        ->json_is({ message => 'Status updated successfully' });
    
    # Test update with invalid status
    $t->put_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx/$content_id" => json => { status => 'invalid_status' })
        ->status_is(400)
        ->json_has('/errors');
    
    # Test update with non-existing ID
    $t->put_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx/99999" => json => { status => 'pending' })
        ->status_is(404);
    
    $schema->storage->txn_rollback;
};

subtest 'GET all Editx contents' => sub {
    plan tests => 5;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # Create a test Editx content
    my $xml_body = generate_shipnotice_xml();
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(201);
    
    # Retrieve all contents
    my $list_response = $t->get_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx")
        ->status_is(200);
    
    my $contents = $list_response->tx->res->json;
    ok(scalar(@$contents) > 0, 'At least one content was returned');
    
    $schema->storage->txn_rollback;
};

subtest 'POST XML with missing required fields' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # XML missing ProductForm
    my $xml_body = generate_shipnotice_xml(
        ship_notice_number => '12345',
        product_form => undef,
        message_type => '01'
    );
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(400)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

subtest 'POST XML with invalid vendor SAN' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # XML with invalid vendor SAN
    my $xml_body = generate_shipnotice_xml(
        ship_notice_number => '12345',
        vendor_san => '99999',
        message_type => '01'
    );
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(400)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

subtest 'POST XML with invalid fund code' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # XML with non-existent fund code
    my $xml_body = generate_shipnotice_xml(
        ship_notice_number => '12345',
        fund_number => 'NONEXISTENT_FUND',
        message_type => '01'
    );
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(400)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

subtest 'POST XML with unknown seller' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # XML with unknown seller name
    my $xml_body = generate_shipnotice_xml(
        ship_notice_number => '12345',
        seller_id => 'FI-UNKNOWN',
        seller_name => 'Unknown Vendor Inc',
        message_type => '01'
    );
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(400)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

subtest 'POST XML with invalid MessageType' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;
    setup_editx_fixture_data();
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # XML with invalid MessageType value
    my $xml_body = generate_shipnotice_xml(
        ship_notice_number => '12345',
        message_type => '99'
    );
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(400)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

# Parameterized XML generator for test scenarios
sub generate_shipnotice_xml {
    my %args = @_;
    
    my $ship_notice_number = exists $args{ship_notice_number} ? $args{ship_notice_number} : 'TEST001';
    my $vendor_san         = exists $args{vendor_san} ? $args{vendor_san} : '12345';
    my $seller_id          = exists $args{seller_id} ? $args{seller_id} : 'FI-BTJ';
    my $seller_name        = exists $args{seller_name} ? $args{seller_name} : 'BTJ Finland Oy';
    my $product_form       = exists $args{product_form} ? $args{product_form} : 'BK';
    my $fund_number        = exists $args{fund_number} ? $args{fund_number} : 'OUPKAIK2026';
    my $message_type       = exists $args{message_type} ? $args{message_type} : '04';
    my $include_marc       = exists $args{include_marc} ? $args{include_marc} : ($message_type eq '04' ? 1 : 0);
    my $well_formed        = exists $args{well_formed} ? $args{well_formed} : 1;
    
    # Return malformed XML if requested
    return '<ShipNotice>
    <Header>
        <DocumentNumber>12345</DocumentNumber>
    </Header>
    <Items>
        <Item>
            <ProductID>ABC123</ProductID>
            <Quantity>-10</Quantity>
        </Item>
    <!-- Missing closing tag for Items -->
</ShipNotice>
    ' unless $well_formed;
    
    # Build ProductForm element if specified
    my $product_form_element = defined $product_form ? "            <ProductForm>$product_form</ProductForm>" : '';
    
    # Build MessageLine content
    my $message_line = $include_marc ? '&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
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
                ' : 'Simple message';
    
    return '<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>' . $ship_notice_number . '</ShipNoticeNumber>
        <IssueDateTime>20260515T1200</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>20260515</Date>
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
                <Identifier>' . $seller_id . '</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>' . $seller_name . '</NameLine>
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
' . $product_form_element . '
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
            <DeliverToLocation>OUPKAIK2026</DeliverToLocation>
            <DestinationLocation>OUPKAIK2026</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <FundDetail>
                <FundNumber>' . $fund_number . '</FundNumber>
                <MonetaryAmount>12.00</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>' . $message_type . '</MessageType>
                <MessageLine>' . $message_line . '</MessageLine>
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