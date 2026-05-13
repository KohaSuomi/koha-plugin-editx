#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 5;
use LWP::UserAgent;
use HTTP::Request;
use Koha::Database;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'POST valid XML file' => sub {
    plan tests => 3;
    # Begin transaction
    $schema->storage->txn_begin;
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
    my $xml_body = valid_shipnotice_xml();

    # Call the API endpoint with users credentials and XML body
    my $editx_content = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(201)
        ->json_is({
            message => 'Data saved successfully',
        });

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
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # Get invalid XML body
    my $xml_body = invalid_shipnotice_xml();
    
    # Should return 400 for invalid XML
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(400)
        ->json_has('/error');
    
    $schema->storage->txn_rollback;
};

subtest 'PUT update Editx content' => sub {
    plan tests => 12;
    $schema->storage->txn_begin;
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # Create a test Editx content first
    my $xml_body = valid_shipnotice_xml();
    
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
    
    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 2**11 }    #acquisition
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;
    
    # Create a test Editx content
    my $xml_body = valid_shipnotice_xml();
    
    $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx" => { "Content-Type" => "application/xml" } => $xml_body)
        ->status_is(201);
    
    # Retrieve all contents
    my $list_response = $t->get_ok("//$userid:$password@/api/v1/contrib/kohasuomi/editx")
        ->status_is(200);
    
    my $contents = $list_response->tx->res->json;
    ok(scalar(@$contents) > 0, 'At least one content was returned');
    
    $schema->storage->txn_rollback;
};

sub valid_shipnotice_xml {
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
            <ProductForm>BK</ProductForm>
            <Title>Izak.</Title>
            <Author>Elstela, Joel</Author>
            <SeriesTitle></SeriesTitle>
            <VolumeOrPart/>
            <EditionStatement/>
            <CityOfPublication></CityOfPublication>
            <PublisherName>WSOY</PublisherName>
            <YearOfPublication>2024</YearOfPublication>
        </ItemDescription>
        <QuantityShipping>1</QuantityShipping>
        <CopyDetail>
            <SubLineNumber>1</SubLineNumber>
            <CopyQuantity>1</CopyQuantity>
            <DeliverToLocation>OUPKAIK2025</DeliverToLocation>
            <DestinationLocation>OUPKAIK2025</DestinationLocation>
            <FundDetail>
                <FundNumber>OUPKAIK2025</FundNumber>
                <MonetaryAmount>12.00</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
&lt;collection xmlns=&quot;http://www.loc.gov/MARC21/slim&quot;&gt;
 &lt;record&gt;
  &lt;leader&gt;00962nam a22002898a 4500&lt;/leader&gt;
  &lt;datafield tag=&quot;245&quot; ind1=&quot;1&quot; ind2=&quot;0&quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Izak.&lt;/subfield&gt;
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

sub invalid_shipnotice_xml {
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
    ';
}