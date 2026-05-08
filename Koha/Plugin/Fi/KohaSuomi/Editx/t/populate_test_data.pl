#!/usr/bin/perl

use Modern::Perl;
use C4::Context;
use DateTime;
use Getopt::Long;
use XML::LibXML;

=head1 NAME

populate_test_data.pl - Populate EDItX plugin database with test data

=head1 SYNOPSIS

    perl populate_test_data.pl [--clear] [--borrowernumber=NUMBER]

=head1 DESCRIPTION

This script populates the EDItX plugin database table with various test scenarios:
- Vendors (aqbooksellers)
- Budget periods and funds (aqbudgetperiods, aqbudgets)
- Pending shipment notices waiting to be processed
- Processing notices currently being handled
- Completed notices that have been successfully imported
- Failed notices with various error conditions

=head1 OPTIONS

    --clear              Clear existing test data before populating
    --borrowernumber=N   Borrowernumber to use as budget owner (default: 51)
    --help               Show this help message

=cut

# Determine table name (plugin uses qualified table name)
my $table_name = 'koha_plugin_fi_kohasuomi_editx_contents';

# Store created IDs for reference
my %created_ids = (
    vendors => {},
    budget_periods => {},
    budgets => {},
);

# Parse command-line options
my $clear = 0;
my $borrowernumber = 51;  # Default value
my $help = 0;

GetOptions(
    'clear'            => \$clear,
    'borrowernumber=i' => \$borrowernumber,
    'help'             => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print <<'HELP';
Usage: populate_test_data.pl [OPTIONS]

Populate EDItX plugin database with comprehensive test data including
vendors, budget periods, funds, and EDItX shipment notices.

Options:
    --clear              Clear existing test data before populating
    --borrowernumber=N   Borrowernumber to use as budget owner (default: 51)
                         Find valid borrowernumber:
                         koha-mysql <instance> -e "SELECT borrowernumber, surname FROM borrowers LIMIT 5;"
    --help               Show this help message

Examples:
    perl populate_test_data.pl --borrowernumber=42
    perl populate_test_data.pl --clear --borrowernumber=99
    perl populate_test_data.pl --help

HELP
    exit 0;
}

# Get database handle (after parsing options, so --help works without DB connection)
my $dbh = C4::Context->dbh;

sub clear_test_data {
    say "Clearing existing test data...";
    
    # Clear EDItX contents (by ShipNoticeNumber)
    $dbh->do("DELETE FROM $table_name WHERE name LIKE 'SN%'");
    
    # Delete in order of foreign key dependencies:
    
    # 1. Delete order-item relationships for orders in test baskets
    $dbh->do("DELETE FROM aqorders_items WHERE ordernumber IN (SELECT ordernumber FROM aqorders WHERE basketno IN (SELECT basketno FROM aqbasket WHERE basketname LIKE 'SN%'))");
    
    # 2. Delete orders in test baskets
    $dbh->do("DELETE FROM aqorders WHERE basketno IN (SELECT basketno FROM aqbasket WHERE basketname LIKE 'SN%')");
    
    # 3. Clear test budgets/funds (must be before budget periods)
    $dbh->do("DELETE FROM aqbudgets WHERE budget_code LIKE 'TEST%'");
    
    # 4. Clear test budget periods
    $dbh->do("DELETE FROM aqbudgetperiods WHERE budget_period_description LIKE 'TEST%'");
    
    # 5. Clear test baskets (must be before vendors)
    $dbh->do("DELETE FROM aqbasket WHERE basketname LIKE 'SN%'");
    
    # 6. Clear vendor EDI accounts (must be before vendors)
    $dbh->do("DELETE FROM vendor_edi_accounts WHERE vendor_id IN (SELECT id FROM aqbooksellers WHERE name LIKE 'TEST%')");
    
    # 7. Clear test vendors (last, as other tables reference it)
    $dbh->do("DELETE FROM aqbooksellers WHERE name LIKE 'TEST%'");
    
    say "Test data cleared.";
}

sub create_test_currency {
    say "\nEnsuring EUR currency exists...";
    
    # Check if EUR currency already exists
    my $existing = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM currency WHERE currency = 'EUR'"
    );
    
    if ($existing) {
        say "  EUR currency already exists";
        return;
    }
    
    # Create EUR currency
    my $sql = qq{
        INSERT INTO currency (currency, symbol, isocode, timestamp, rate, active)
        VALUES ('EUR', '€', 'EUR', NOW(), 1.0, 1)
    };
    
    eval {
        $dbh->do($sql);
        say "  Created EUR currency";
    };
    if ($@) {
        say "  EUR currency creation failed (may already exist): $@";
    }
}

sub create_test_vendors {
    say "\nCreating test vendors...";
    
    my @vendors = (
        {
            name => 'TEST Vendor BTJ Finland',
            address1 => 'Test Street 1',
            address2 => '',
            address3 => '',
            address4 => '',
            phone => '+358 9 1234567',
            accountnumber => 'FI-BTJ-TEST',
            notes => 'Test vendor for EDItX testing - BTJ',
            postal => '00100',
            url => 'https://www.btj.fi',
            active => 1,
            san => '12345',
            id_code_qualifier => 91,
        },
        {
            name => 'TEST Vendor Booky',
            address1 => 'Booky Street 10',
            address2 => '',
            address3 => '',
            address4 => '',
            phone => '+358 9 7654321',
            accountnumber => 'FI-BOOKY-TEST',
            notes => 'Test vendor for EDItX testing - Booky',
            postal => '00200',
            url => 'https://www.booky.fi',
            active => 1,
            san => '23456',
            id_code_qualifier => 91,
        },
        {
            name => 'TEST Vendor Academic Press',
            address1 => 'Academic Avenue 5',
            address2 => '',
            address3 => '',
            address4 => '',
            phone => '+358 40 1112222',
            accountnumber => 'FI-ACADEMIC-TEST',
            notes => 'Test vendor for academic books - EDItX testing',
            postal => '00300',
            url => 'https://www.academicpress.fi',
            active => 1,
            san => '34567',
            id_code_qualifier => 91,
        },
    );
    
    foreach my $vendor (@vendors) {
        my $sql = qq{
            INSERT INTO aqbooksellers (
                name, address1, address2, address3, address4, phone,
                accountnumber, notes, postal, url, active
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        };
        
        $dbh->do($sql, undef,
            $vendor->{name},
            $vendor->{address1},
            $vendor->{address2},
            $vendor->{address3},
            $vendor->{address4},
            $vendor->{phone},
            $vendor->{accountnumber},
            $vendor->{notes},
            $vendor->{postal},
            $vendor->{url},
            $vendor->{active}
        );
        
        my $vendor_id = $dbh->last_insert_id(undef, undef, 'aqbooksellers', undef);
        $created_ids{vendors}{$vendor->{name}} = $vendor_id;
        say "  Created vendor: $vendor->{name} (ID: $vendor_id)";
        
        # Create corresponding EDI account for this vendor
        my $edi_sql = qq{
            INSERT INTO vendor_edi_accounts (
                vendor_id, san, id_code_qualifier, transport, orders_enabled
            ) VALUES (?, ?, ?, 'FILE', 1)
        };
        
        $dbh->do($edi_sql, undef,
            $vendor_id,
            $vendor->{san},
            $vendor->{id_code_qualifier}
        );
        
        say "    Created EDI account: SAN=$vendor->{san}, qualifier=$vendor->{id_code_qualifier}";
    }
}

sub create_test_budget_periods {
    say "\nCreating test budget periods...";
    
    my $current_year = DateTime->now->year;
    my $next_year = $current_year + 1;
    
    my @periods = (
        {
            budget_period_startdate => "$current_year-01-01",
            budget_period_enddate => "$current_year-12-31",
            budget_period_description => "TEST Budget Period $current_year",
            budget_period_total => 100000.00,
            budget_period_active => 1,
        },
        {
            budget_period_startdate => "$next_year-01-01",
            budget_period_enddate => "$next_year-12-31",
            budget_period_description => "TEST Budget Period $next_year",
            budget_period_total => 120000.00,
            budget_period_active => 1,
        },
    );
    
    foreach my $period (@periods) {
        my $sql = qq{
            INSERT INTO aqbudgetperiods (
                budget_period_startdate,
                budget_period_enddate,
                budget_period_description,
                budget_period_total,
                budget_period_active
            ) VALUES (?, ?, ?, ?, ?)
        };
        
        $dbh->do($sql, undef,
            $period->{budget_period_startdate},
            $period->{budget_period_enddate},
            $period->{budget_period_description},
            $period->{budget_period_total},
            $period->{budget_period_active}
        );
        
        my $period_id = $dbh->last_insert_id(undef, undef, 'aqbudgetperiods', undef);
        $created_ids{budget_periods}{$period->{budget_period_description}} = $period_id;
        say "  Created budget period: $period->{budget_period_description} (ID: $period_id)";
    }
}

sub create_test_budgets {
    my ($owner_id) = @_;
    
    say "\nCreating test budgets/funds...";
    say "  Using borrowernumber $owner_id as budget owner";
    
    # Validate borrowernumber exists
    my $borrower_exists = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ?",
        undef, $owner_id
    );
    
    unless ($borrower_exists) {
        warn "\nWARNING: Borrowernumber $owner_id does not exist!\n";
        warn "Find valid borrowernumber with:\n";
        warn "  koha-mysql <instance> -e \"SELECT borrowernumber, surname FROM borrowers LIMIT 5;\"\n";
        warn "\nSkipping budget creation.\n\n";
        return;
    }
    
    # Get the current year budget period ID
    my $current_year = DateTime->now->year;
    my $period_name = "TEST Budget Period $current_year";
    my $budget_period_id = $created_ids{budget_periods}{$period_name};
    
    unless ($budget_period_id) {
        warn "WARNING: Budget period not found, budgets may not work correctly\n";
        return;
    }
    
    my @budgets = (
        {
            budget_code => 'TESTFUND2025',
            budget_name => 'TEST General Acquisitions Fund',
            budget_amount => 50000.00,
            budget_period_id => $budget_period_id,
            budget_owner_id => $owner_id,
            budget_notes => 'Test fund for general book acquisitions',
        },
        {
            budget_code => 'TESTLOC2025',
            budget_name => 'TEST Location-specific Fund',
            budget_amount => 20000.00,
            budget_period_id => $budget_period_id,
            budget_owner_id => $owner_id,
            budget_notes => 'Test fund for location-specific acquisitions',
        },
        {
            budget_code => 'OUPKAIK2025',
            budget_name => 'TEST OUP KAIK Fund',
            budget_amount => 15000.00,
            budget_period_id => $budget_period_id,
            budget_owner_id => $owner_id,
            budget_notes => 'Test fund matching real fund pattern',
        },
        {
            budget_code => 'TEST_CHILDREN',
            budget_name => 'TEST Children\'s Books Fund',
            budget_amount => 10000.00,
            budget_period_id => $budget_period_id,
            budget_owner_id => $owner_id,
            budget_notes => 'Test fund for children\'s materials',
        },
        {
            budget_code => 'TEST_ACADEMIC',
            budget_name => 'TEST Academic Books Fund',
            budget_amount => 30000.00,
            budget_period_id => $budget_period_id,
            budget_owner_id => $owner_id,
            budget_notes => 'Test fund for academic and research materials',
        },
    );
    
    foreach my $budget (@budgets) {
        my $sql = qq{
            INSERT INTO aqbudgets (
                budget_code,
                budget_name,
                budget_amount,
                budget_period_id,
                budget_owner_id,
                budget_notes
            ) VALUES (?, ?, ?, ?, ?, ?)
        };
        
        eval {
            $dbh->do($sql, undef,
                $budget->{budget_code},
                $budget->{budget_name},
                $budget->{budget_amount},
                $budget->{budget_period_id},
                $budget->{budget_owner_id},
                $budget->{budget_notes}
            );
            
            my $budget_id = $dbh->last_insert_id(undef, undef, 'aqbudgets', undef);
            $created_ids{budgets}{$budget->{budget_code}} = $budget_id;
            say "  Created fund: $budget->{budget_code} - $budget->{budget_name} (ID: $budget_id)";
        };
        if ($@) {
            warn "  WARNING: Could not create fund $budget->{budget_code}: $@\n";
        }
    }
}

sub generate_editx_xml {
    my ($params) = @_;
    
    my $ship_notice_num = $params->{ship_notice_num} // '12345';
    my $date = $params->{date} // DateTime->now->strftime('%Y%m%d');
    my $datetime = $params->{datetime} // DateTime->now->strftime('%Y%m%dT%H%M');
    my $isbn = $params->{isbn} // '9789510506103';
    my $title = $params->{title} // 'Test Book';
    my $author = $params->{author} // 'Test Author';
    my $publisher = $params->{publisher} // 'Test Publisher';
    my $year = $params->{year} // '2024';
    my $price = $params->{price} // '12.00';
    my $quantity = $params->{quantity} // '1';
    my $location = $params->{location} // 'TESTLOC2025';
    my $fund = $params->{fund} // 'TESTLOC2025';
    my $line_number = $params->{line_number} // '1';
    my $notes = $params->{notes} // 'EDItX test order';
    
    return qq{<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>$ship_notice_num</ShipNoticeNumber>
        <IssueDateTime>$datetime</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>$date</Date>
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
        <LineNumber>$line_number</LineNumber>
        <ProductID>
            <ProductIDType>EAN13</ProductIDType>
            <Identifier>$isbn</Identifier>
        </ProductID>
        <ProductID>
            <ProductIDType>ISBN</ProductIDType>
            <Identifier>$isbn</Identifier>
        </ProductID>
        <ItemDescription>
            <ProductForm>BK</ProductForm>
            <Title>$title</Title>
            <Author>$author</Author>
            <SeriesTitle></SeriesTitle>
            <VolumeOrPart/>
            <EditionStatement/>
            <CityOfPublication></CityOfPublication>
            <PublisherName>$publisher</PublisherName>
            <YearOfPublication>$year</YearOfPublication>
        </ItemDescription>
        <QuantityShipping>$quantity</QuantityShipping>
        <ReferenceCoded>
            <ReferenceTypeCode>VendorsOrderReference</ReferenceTypeCode>
            <ReferenceNumber>$ship_notice_num</ReferenceNumber>
            <ReferenceDate>$date</ReferenceDate>
        </ReferenceCoded>
        <PricingDetail>
            <Price>
                <MonetaryAmount>$price</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>FixedRPIncludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>10</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <PricingDetail>
            <Price>
                <MonetaryAmount>$price</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>FixedRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>10</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <PricingDetail>
            <Price>
                <MonetaryAmount>$price</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <PriceQualifierCode>SRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>10</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <CopyDetail>
            <SubLineNumber>1</SubLineNumber>
            <CopyQuantity>$quantity</CopyQuantity>
            <DeliverToLocation>$location</DeliverToLocation>
            <DestinationLocation>$location</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>$price</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <LocationCode>FI-KOHA;210;1</LocationCode>
            <ReaderInterestCode/>
            <FundDetail>
                <FundNumber>$fund</FundNumber>
                <MonetaryAmount>$price</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
&lt;collection xmlns=&quot;http://www.loc.gov/MARC21/slim&quot;&gt;
 &lt;record&gt;
  &lt;leader&gt;00000nam a22000008a 4500&lt;/leader&gt;
  &lt;controlfield tag=&quot;001&quot;&gt;$isbn&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;003&quot;&gt;FI-Test&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;005&quot;&gt;20240326101401.0&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;008&quot;&gt;240315s$year    fi                  fin&lt;/controlfield&gt;
  &lt;datafield tag=&quot;020&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;$isbn&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;100&quot; ind1=&quot;1&quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;$author&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;245&quot; ind1=&quot;1&quot; ind2=&quot;0&quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;$title&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;260&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;b&quot;&gt;$publisher&lt;/subfield&gt;
   &lt;subfield code=&quot;c&quot;&gt;$year&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;500&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;$notes&lt;/subfield&gt;
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
        <UnitsShipped>$quantity</UnitsShipped>
    </Summary>
</LibraryShipNotice>};
}

sub insert_test_record {
    my ($content, $status, $statusmessage, $transfer_time) = @_;
    
    # Extract ShipNoticeNumber from XML content
    my $ship_notice_number = 'UNKNOWN';
    eval {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($content);
        my ($node) = $doc->findnodes('//ShipNoticeNumber');
        $ship_notice_number = $node->textContent if $node;
    };
    if ($@) {
        warn "Warning: Could not parse XML to extract ShipNoticeNumber: $@\n";
    }
    
    my $sql = qq{
        INSERT INTO $table_name (name, content, status, statusmessage, transfer_time, timestamp)
        VALUES (?, ?, ?, ?, ?, NOW())
    };
    
    $dbh->do($sql, undef, $ship_notice_number, $content, $status, $statusmessage, $transfer_time);
    say "Inserted: $ship_notice_number (status: $status)";
}

sub populate_test_data {
    say "\nPopulating test data...\n";
    
    # 1. PENDING NOTICES - Waiting to be processed
    say "Creating PENDING test records...";
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN001',
            isbn => '9789511234567',
            title => 'Waiting Book',
            author => 'Pending, Author',
            publisher => 'Pending Press',
            price => '15.50'
        }),
        'pending',
        undef,
        undef
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN002',
            isbn => '9789511234568',
            title => 'Multi-Copy Book',
            author => 'Popular, Writer',
            quantity => '5',
            price => '22.00'
        }),
        'pending',
        undef,
        undef
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN003',
            isbn => '9789511234569',
            title => 'Expensive Academic Book',
            author => 'Scholar, Dr.',
            publisher => 'Academic Press',
            price => '95.00'
        }),
        'pending',
        undef,
        undef
    );
    
    # 2. PROCESSING NOTICES - Currently being handled
    say "\nCreating PROCESSING test records...";
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN004',
            isbn => '9789511234570',
            title => 'Book Being Processed',
            author => 'Active, Author',
            price => '18.90'
        }),
        'processing',
        'Currently importing to catalog',
        DateTime->now->subtract(minutes => 5)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN005',
            isbn => '9789511234571',
            title => 'Large Batch Item',
            author => 'Batch, Author',
            quantity => '10',
            price => '12.50'
        }),
        'processing',
        'Processing large order batch',
        DateTime->now->subtract(minutes => 15)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    # 3. COMPLETED NOTICES - Successfully processed
    say "\nCreating COMPLETED test records...";
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN006',
            isbn => '9789511234572',
            title => 'Successfully Imported Book',
            author => 'Success, Author',
            price => '14.00'
        }),
        'completed',
        'Successfully imported 1 item(s)',
        DateTime->now->subtract(hours => 2)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN007',
            isbn => '9789511234573',
            title => 'Another Completed Order',
            author => 'Done, Writer',
            price => '19.90'
        }),
        'completed',
        'Successfully imported 1 item(s)',
        DateTime->now->subtract(hours => 5)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN008',
            isbn => '9789511234574',
            title => 'Yesterdays Order',
            author => 'Past, Author',
            price => '21.00',
            date => DateTime->now->subtract(days => 1)->strftime('%Y%m%d')
        }),
        'completed',
        'Successfully imported 1 item(s)',
        DateTime->now->subtract(days => 1)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    # 4. FAILED NOTICES - Various failure scenarios
    say "\nCreating FAILED test records...";
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN009',
            isbn => 'INVALID-ISBN',
            title => 'Book with Invalid ISBN',
            author => 'Error, Author',
            price => '16.00'
        }),
        'failed',
        'Invalid ISBN format',
        DateTime->now->subtract(hours => 1)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN010',
            isbn => '9789511234575',
            title => 'Book with Missing Fund',
            author => 'Nofund, Author',
            fund => 'NONEXISTENT_FUND',
            price => '13.50'
        }),
        'failed',
        'Fund NONEXISTENT_FUND not found in system',
        DateTime->now->subtract(hours => 3)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        '<?xml version="1.0" encoding="UTF-8"?><LibraryShipNotice><Header><ShipNoticeNumber>SN011</ShipNoticeNumber>',
        'failed',
        'Malformed XML: premature end of document',
        DateTime->now->subtract(hours => 6)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN012',
            isbn => '9789511234576',
            title => 'Duplicate Order',
            author => 'Duplicate, Author',
            price => '17.00'
        }),
        'failed',
        'Duplicate shipment notice number: SN012 already processed',
        DateTime->now->subtract(days => 2)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN013',
            isbn => '9789511234577',
            title => 'Network Timeout Book',
            author => 'Timeout, Author',
            price => '20.00'
        }),
        'failed',
        'Network timeout while processing order',
        DateTime->now->subtract(hours => 12)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    # 5. Edge cases and special scenarios
    say "\nCreating EDGE CASE test records...";
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN014',
            isbn => '9789511234578',
            title => 'Käyttäjän käsikirja - Åäö test',
            author => 'Äänekoski, Öljy',
            publisher => 'Ääniteos Oy',
            price => '25.50'
        }),
        'pending',
        undef,
        undef
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN015',
            isbn => '9789511234579',
            title => 'Rare Collector Edition',
            author => 'Rare, Collector',
            price => '499.99'
        }),
        'completed',
        'Successfully imported 1 item(s) - high value item flagged',
        DateTime->now->subtract(hours => 24)->strftime('%Y-%m-%d %H:%M:%S')
    );
    
    insert_test_record(
        generate_editx_xml({
            ship_notice_num => 'SN016',
            isbn => '9789511234580',
            title => 'Old Pending Order',
            author => 'Ancient, Order',
            date => DateTime->now->subtract(months => 1)->strftime('%Y%m%d'),
            datetime => DateTime->now->subtract(months => 1)->strftime('%Y%m%dT%H%M'),
            price => '11.00'
        }),
        'pending',
        undef,
        undef
    );
    
    say "\n" . "=" x 60;
    say "Test data population completed!";
    say "=" x 60;
    
    # Display summary for EDItX messages
    my $summary = $dbh->selectall_arrayref(
        "SELECT status, COUNT(*) as count FROM $table_name WHERE name LIKE 'SN%' GROUP BY status",
        { Slice => {} }
    );
    
    say "\nSummary of EDItX test records:";
    say "-" x 30;
    foreach my $row (@$summary) {
        printf "%-15s: %d records\n", uc($row->{status}), $row->{count};
    }
    say "-" x 30;
    
    my $total = $dbh->selectrow_array("SELECT COUNT(*) FROM $table_name WHERE name LIKE 'SN%'");
    say "TOTAL          : $total records\n";
    
    # Display Koha acquisitions summary
    say "\nKoha Acquisitions Summary:";
    say "-" x 30;
    
    my $eur_exists = $dbh->selectrow_array("SELECT COUNT(*) FROM currency WHERE currency = 'EUR'");
    say "EUR Currency   : " . ($eur_exists ? "exists" : "missing");
    
    my $vendor_count = $dbh->selectrow_array("SELECT COUNT(*) FROM aqbooksellers WHERE name LIKE 'TEST%'");
    say "Vendors        : $vendor_count";
    
    my $edi_count = $dbh->selectrow_array("SELECT COUNT(*) FROM vendor_edi_accounts WHERE vendor_id IN (SELECT id FROM aqbooksellers WHERE name LIKE 'TEST%')");
    say "EDI Accounts   : $edi_count";
    
    my $period_count = $dbh->selectrow_array("SELECT COUNT(*) FROM aqbudgetperiods WHERE budget_period_description LIKE 'TEST%'");
    say "Budget Periods : $period_count";
    
    my $fund_count = $dbh->selectrow_array("SELECT COUNT(*) FROM aqbudgets WHERE budget_code LIKE 'TEST%' OR budget_code LIKE '%2025'");
    say "Funds/Budgets  : $fund_count";
    say "-" x 30 . "\n";
}

# Main execution
if ($clear) {
    clear_test_data();
    say "";
}

# Create Koha acquisitions infrastructure
create_test_currency();
create_test_vendors();
create_test_budget_periods();
create_test_budgets($borrowernumber);

# Create EDItX test messages
populate_test_data();

say "\nYou can now test the EDItX plugin with this data.";
say "To clear test data later, run: perl populate_test_data.pl --clear\n";

__END__

=head1 TESTING SCENARIOS

This script creates the following test data:

=head2 CURRENCY (EUR)

Ensures EUR currency exists in the currency table for order processing.
If EUR already exists, it will not be modified.

=head2 VENDORS (3 records in aqbooksellers + EDI accounts in vendor_edi_accounts)

- TEST Vendor BTJ Finland (SAN: 12345)
- TEST Vendor Booky (SAN: 23456)
- TEST Vendor Academic Press (SAN: 34567)

Each vendor has a corresponding EDI account configured for FILE transport with orders enabled.

NOTE: Baskets are created automatically by the EDItX processor when orders are processed.
The basket name will match the ShipNoticeNumber from the EDItX message.

=head2 BUDGET PERIODS (2 records in aqbudgetperiods)
- Current year budget period
- Next year budget period

=head2 BUDGETS/FUNDS (5 records in aqbudgets)
- TESTFUND2025 - General Acquisitions Fund (€50,000)
- TESTLOC2025 - Location-specific Fund (€20,000)
- OUPKAIK2025 - OUP KAIK Fund (€15,000)
- TEST_CHILDREN - Children's Books Fund (€10,000)
- TEST_ACADEMIC - Academic Books Fund (€30,000)

=head2 EDITX MESSAGES - PENDING (3 records)
- Single book order
- Multiple copies of same book
- Expensive academic book

=head2 EDITX MESSAGES - PROCESSING (2 records)
- Normal book being processed
- Large batch order in progress

=head2 EDITX MESSAGES - COMPLETED (3 records)
- Recent successful import
- Older successful import
- Yesterday's completed order

=head2 EDITX MESSAGES - FAILED (5 records)
- Invalid ISBN format
- Missing fund in system
- Malformed XML
- Duplicate shipment notice
- Network timeout error

=head2 EDITX MESSAGES - EDGE CASES (3 records)
- Unicode/special characters in Finnish
- High-price collector item
- Old pending order from a month ago

=head1 NOTES

=head2 Budget Owner ID

The script uses borrowernumber 51 as the default budget owner. You can specify
a different borrowernumber using the --borrowernumber flag:

    perl populate_test_data.pl --borrowernumber=99

Find valid borrowernumbers with:

    SELECT borrowernumber, surname, firstname FROM borrowers LIMIT 10;

Or via koha-mysql:

    koha-mysql <instance> -e "SELECT borrowernumber, surname FROM borrowers LIMIT 5;"

The script will validate that the borrowernumber exists before creating budgets.

=head2 Dependencies

Test funds reference the current year's budget period. Ensure budget periods
are created before funds.

=head1 EXAMPLES

Create test data with default borrowernumber (51):

    perl populate_test_data.pl

Create test data with specific borrowernumber:

    perl populate_test_data.pl --borrowernumber=42

Clear existing test data and repopulate with new borrowernumber:

    perl populate_test_data.pl --clear --borrowernumber=99

Show help:

    perl populate_test_data.pl --help

=head1 AUTHOR

Generated for Koha EDItX Plugin Testing

=cut
