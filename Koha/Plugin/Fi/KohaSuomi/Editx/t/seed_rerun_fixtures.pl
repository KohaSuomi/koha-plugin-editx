#!/usr/bin/perl

BEGIN {
    # find Koha's Perl modules
    # test carefully before changing this
    use FindBin;
    eval { require "$FindBin::Bin/../kohalib.pl" };
}
use Modern::Perl;
use utf8;
use DateTime;
use Getopt::Long;
use Koha::Plugins;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
use Business::ISBN;
use MARC::Field;
use MARC::Record;

=head1 NAME

seed_rerun_fixtures.pl - Seed fixtures for re-running a failed EDItX message

=head1 SYNOPSIS

    perl seed_rerun_fixtures.pl [OPTIONS]

    # 1. create the partial states
    perl seed_rerun_fixtures.pl --seed --borrowernumber=42

    # 2. look at what a re-run would do
    perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/Editx/cronjobs/check_editx_rerun_duplicates.pl --filename RR01

    # 3. hand the messages back to the processor
    perl seed_rerun_fixtures.pl --requeue

    # 4. run the processor and check the outcome
    perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/Editx/cronjobs/process_edi_messages.pl
    perl seed_rerun_fixtures.pl --verify

    # 5. receive the shipment, like the acquisitions UI would
    perl seed_rerun_fixtures.pl --receive

    # remove everything this script created
    perl seed_rerun_fixtures.pl --clear

=head1 DESCRIPTION

Creates the state that issue #23 describes: messages that failed part-way
through and left orders, items and budget spend behind, so the same message is
processed again.

The already-written part is not faked. C<--seed> runs the real
C<OrderProcessor::process> on the lines that would have been written before the
failure, so the biblios, basket, orders, items and C<aqbudgets_spend_log> rows
are exactly what the plugin writes in production. The full message is then
stored as FAILED, as a real failure would have left it.

=head2 Scenarios

    RR01  two lines, only the first one written
          re-run: line 1 is skipped, line 2 is written -> 2 orders, 2 items
    RR02  one line, fully written
          re-run: the line is skipped -> still 1 order, 1 item
    RR03  one line without CopyDetail/SubLineNumber
          rejected by Validator::validateEditxContent before process() runs,
          so nothing is written at all. The processor itself never reads
          SubLineNumber, so without the validation gate this message would
          have been imported.

Without the skip in C<OrderProcessor::process>, RR01 would end up with 3
orders and 3 items and RR02 with 2 orders and 2 items.

=head1 OPTIONS

    --seed              Create/refresh the fixtures (default)
    --verify            Report the outcome after running process_edi_messages.pl
    --requeue           Set the fixture messages back to NEW for processing
    --receive           Receive the shipment: stock invoice and received orders
    --clear             Remove the fixtures created by this script
    --borrowernumber=N  Borrower owning the test fund (default: 51)
    --help              Show this help

=head1 NOTES

C<--receive> does what "Receive shipment from vendor" does in the acquisitions
user interface: it creates a stock invoice with C<AddInvoice> and then sets
C<quantityreceived>, C<datereceived>, C<invoiceid> and C<orderstatus> the same
way C<C4::Acquisition::ModReceiveOrder> does, so the fixture ends up in the
state a real received delivery leaves behind. It only touches orders that
belong to the fixture messages, and does nothing when they are all received
already. C<--clear> removes those invoices again.

The infrastructure (currency, branch, location, vendor, budget period, fund) is
created if missing and is never removed by C<--clear>, so it can be shared with
other test data. C<--clear> only removes the RR* fixtures.

The seller name has to be exactly 'BTJ Finland Oy': the object factory picks
the vendor specific ItemDetail class from it, and C<ItemDetail::getNotes>
returns an empty string for the generic class, which makes C<createBiblio>
fail validation.

Every fixture line gets its own C<ReferenceNumber>, because that value is what
C<createOrder> stores as C<order_internalnote> and what the skip matches on.

=cut

my $FIXTURE_PREFIX = 'RR';

my $VENDOR_NAME    = 'TEST Vendor EDItX Rerun';
my $VENDOR_SAN     = '99011';
my $VENDOR_ACCOUNT = 'FI-EDITX-RERUN';
my $SELLER_NAME    = 'BTJ Finland Oy';

my $BRANCH   = 'CPL';
my $LOCATION = 'AIK';
my $FUND     = 'RRERUN';

my $MODE_SEED    = 0;
my $MODE_VERIFY  = 0;
my $MODE_REQUEUE = 0;
my $MODE_RECEIVE = 0;
my $MODE_CLEAR   = 0;
my $borrowernumber = 51;
my $help        = 0;

GetOptions(
    'seed'              => \$MODE_SEED,
    'verify'            => \$MODE_VERIFY,
    'requeue'           => \$MODE_REQUEUE,
    'receive'           => \$MODE_RECEIVE,
    'clear'             => \$MODE_CLEAR,
    'borrowernumber=i'  => \$borrowernumber,
    'help'              => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print <<'HELP';
Usage: seed_rerun_fixtures.pl [OPTIONS]

  --seed              Create/refresh the re-run fixtures (default)
  --verify            Report the outcome after running process_edi_messages.pl
  --requeue           Set the fixture messages back to NEW so the cron picks them up
  --receive           Receive the shipment: stock invoice + received orders
  --clear             Remove the fixtures created by this script
  --borrowernumber=N  Borrower owning the test fund (default: 51)
  --help              Show this help

HELP
    exit 0;
}

$MODE_SEED = 1 unless $MODE_VERIFY || $MODE_CLEAR || $MODE_REQUEUE || $MODE_RECEIVE || $MODE_SEED;

# expect_orders / expect_items are counted over every basket and order that
# belongs to the fixture, so a second basket created by the re-run counts too.
my @SCENARIOS = (
    {
        key           => 'RR01',
        title         => 'two lines, only the first one was written before the failure',
        lines         => 2,
        seeded_lines  => 1,    # what --seed actually processes
        isbns         => [ '9789519900018', '9789519900025' ],
        expect_status => 'OK', # the re-run completes the message
        expect_orders => 2,
        expect_items  => 2,
    },
    {
        key           => 'RR02',
        title         => 'one line, fully written before the failure',
        lines         => 1,
        seeded_lines  => 1,
        isbns         => ['9789519900032'],
        expect_status => 'OK',
        expect_orders => 1,
        expect_items  => 1,
    },
    {
        key           => 'RR03',
        title         => 'missing CopyDetail/SubLineNumber: rejected before processing',
        lines         => 1,
        seeded_lines  => 0,
        isbns         => ['9789519900049'],
        omit          => 'SubLineNumber',
        expect_status => 'FAILED',
        expect_orders => 0,
        expect_items  => 0,
    },
);

my @ISBNS = map { @{ $_->{isbns} } } @SCENARIOS;

my $dbh;
my $budget_period_id;
my $vendor_id;
my $parser;
my $year;

# ------------------------------------------------------------------- helpers

sub say_ok   { print "  ok   $_[0]\n" }
sub say_skip { print "  --   $_[0]\n" }
sub say_new  { print "  new  $_[0]\n" }
sub say_bad  { print "  BAD  $_[0]\n" }

sub scalar_value {
    my ($sql, @bind) = @_;
    return $dbh->selectrow_array($sql, undef, @bind);
}

sub sql_literal {
    my ($value) = @_;
    return 'NULL' unless defined $value;
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    return "'$value'";
}

sub fixture_filename {
    my ($scenario) = @_;
    return $scenario->{key} . '_' . $scenario->{issue_date_time};
}

# -------------------------------------------------------------- infrastructure

sub check_borrower {
    my $exists = scalar_value( 'SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ?', $borrowernumber );
    die "borrowernumber $borrowernumber does not exist, pass a valid one with --borrowernumber\n" if !$exists;
    say_ok("borrowernumber $borrowernumber");
}

sub ensure_currency {
    # Koha 25.05 names the columns currency and symbol, not currency_code.
    my $exists = scalar_value("SELECT COUNT(*) FROM currency WHERE currency = 'EUR'");
    return say_ok('currency EUR') if $exists;

    $dbh->do(
        "INSERT INTO currency (currency, symbol, isocode, timestamp, rate, active)
         VALUES ('EUR', ?, 'EUR', NOW(), 1.0, 1)",
        undef, "\x{20ac}"
    );
    say_new('currency EUR');
}

sub ensure_branch {
    my $exists = scalar_value( 'SELECT COUNT(*) FROM branches WHERE branchcode = ?', $BRANCH );
    return say_ok("branch $BRANCH") if $exists;

    $dbh->do( 'INSERT INTO branches (branchcode, branchname) VALUES (?, ?)',
        undef, $BRANCH, "EDItX rerun $BRANCH" );
    say_new("branch $BRANCH");
}

sub ensure_location {
    # Locations are authorised values of category LOC; there is no locations table.
    my $exists = scalar_value(
        "SELECT COUNT(*) FROM authorised_values WHERE category = 'LOC' AND authorised_value = ?",
        $LOCATION
    );
    return say_ok("location $LOCATION") if $exists;

    $dbh->do(
        "INSERT INTO authorised_values (category, authorised_value, lib) VALUES ('LOC', ?, ?)",
        undef, $LOCATION, "EDItX rerun $LOCATION"
    );
    say_new("location $LOCATION");
}

sub ensure_vendor {
    # The bookseller table is aqbooksellers, keyed by id.
    $vendor_id = scalar_value( 'SELECT id FROM aqbooksellers WHERE name = ?', $VENDOR_NAME );

    if ( !$vendor_id ) {
        $dbh->do(
            'INSERT INTO aqbooksellers (name, address1, accountnumber, notes, postal, active) VALUES (?, ?, ?, ?, ?, ?)',
            undef, $VENDOR_NAME, 'Rerun Street 1', $VENDOR_ACCOUNT, 'EDItX rerun test vendor', '00100', 1
        );
        $vendor_id = $dbh->last_insert_id( undef, undef, 'aqbooksellers', undef );
        say_new("vendor $VENDOR_NAME (id $vendor_id)");
    }
    else {
        say_ok("vendor $VENDOR_NAME (id $vendor_id)");
    }

    my $account_id = scalar_value(
        "SELECT id FROM vendor_edi_accounts
         WHERE vendor_id = ? AND san = ? AND id_code_qualifier = '91'
           AND transport = 'FILE' AND orders_enabled = 1",
        $vendor_id, $VENDOR_SAN
    );

    if ( !$account_id ) {
        $dbh->do(
            "INSERT INTO vendor_edi_accounts (description, vendor_id, san, id_code_qualifier, transport, orders_enabled)
             VALUES (?, ?, ?, 91, 'FILE', 1)",
            undef, "EDItX rerun EDI account $VENDOR_SAN", $vendor_id, $VENDOR_SAN
        );
        $account_id = $dbh->last_insert_id( undef, undef, 'vendor_edi_accounts', undef );
        say_new("vendor_edi_accounts SAN $VENDOR_SAN (id $account_id)");
    }
    else {
        say_ok("vendor_edi_accounts SAN $VENDOR_SAN (id $account_id)");
    }
}

sub ensure_budget {
    print "\nInfrastructure:\n";

    check_borrower();
    ensure_currency();
    ensure_branch();
    ensure_location();
    ensure_vendor();

    # budget_period_startdate / budget_period_enddate, not _start / _end.
    my $description = "TEST EDItX rerun budget period $year";

    $budget_period_id = scalar_value(
        'SELECT budget_period_id FROM aqbudgetperiods WHERE budget_period_description = ?',
        $description
    );
    if ($budget_period_id) {
        say_ok("$description (id $budget_period_id)");
    }
    else {
        $dbh->do(
            'INSERT INTO aqbudgetperiods (budget_period_startdate, budget_period_enddate, budget_period_description, budget_period_total, budget_period_active)
             VALUES (?, ?, ?, ?, 1)',
            undef, "$year-01-01", "$year-12-31", $description, 50000
        );
        $budget_period_id = $dbh->last_insert_id( undef, undef, 'aqbudgetperiods', undef );
        say_new("$description (id $budget_period_id)");
    }

    my $fund_id = scalar_value( 'SELECT budget_id FROM aqbudgets WHERE budget_code = ?', $FUND );
    if ($fund_id) {
        say_ok("fund $FUND");
    }
    else {
        $dbh->do(
            'INSERT INTO aqbudgets (budget_code, budget_name, budget_amount, budget_period_id, budget_owner_id, budget_notes)
             VALUES (?, ?, 50000, ?, ?, ?)',
            undef, $FUND, 'TEST EDItX rerun fund', $budget_period_id, $borrowernumber, 'EDItX rerun'
        );
        say_new("fund $FUND");
    }
}

sub check_config {
    # Loaded here rather than at compile time so --help and --clear work even
    # when the plugin directory is not in @INC.
    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

    my $config   = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new;
    my $settings = $config->getSettings();
    my $authoriser = $settings->{settings}->{authoriser};
    my $allowed    = $settings->{settings}->{allowed_locations};

    die "authoriser is not configured; OrderProcessor::process dies without it\n" if !$authoriser;
    say_ok("authoriser $authoriser");

    my $authoriser_exists = scalar_value( 'SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ?', $authoriser );
    die "authoriser $authoriser is not a valid borrowernumber\n" if !$authoriser_exists;
    say_ok("authoriser $authoriser exists");

    my %allowed = map { $_ => 1 } grep { $_ } split /,/, ( $allowed // '' );
    die "allowed_locations must contain $LOCATION for the fixtures to resolve\n" if !$allowed{$LOCATION};
    say_ok("allowed_locations contains $LOCATION");
}

sub build_parser {
    # Both classes are named below without a compile-time use, so they have to
    # be loaded here before ->new is called on them.
    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice;
    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser;

    my $schema_path = $FindBin::Bin . '/../Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/';
    $schema_path = '/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/'
        if !-d $schema_path;

    $parser = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser->new(
        objectFactory =>
            Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice->new(
            schemaPath => $schema_path,
            )
    );
}

# ------------------------------------------------------------------- XML

sub build_marc {
    my ($params) = @_;

    my $field008 = sprintf( '%-40s', "240315s$year    fi                  fin" );

    my $record = MARC::Record->new();
    $record->append_fields(
        MARC::Field->new( '001', $params->{isbn} ),
        MARC::Field->new( '003', 'FI-Test' ),
        MARC::Field->new( '005', DateTime->now->strftime('%Y%m%d%H%M%S') . '.0' ),
        MARC::Field->new( '008', $field008 ),
    );

    $record->append_fields(
        MARC::Field->new( '020', '', '', a => $params->{isbn} ),
        MARC::Field->new( '100', '1', '', a => 'Rerun, Fixture' ),
        MARC::Field->new( '245', '1', '0', a => $params->{title} ),
        MARC::Field->new( '260', '', '', b => 'EDItX Rerun Press', c => $year ),
        MARC::Field->new( '942', '', '', c => 'BK' ),
    );

    return $record;
}

sub build_line {
    my ($params) = @_;

    my $title   = $params->{title};
    my $isbn    = $params->{isbn};
    my $price   = $params->{price} // '12.00';
    my $omit    = $params->{omit};

    # BranchLocationYear::Parser splits this into branch, location and year, so
    # it has to be BRANCH + LOCATION + YYYY or getBranchCode() stays empty and
    # createItem fails its destinationlocation validation.
    my $deliver_to = $BRANCH . $LOCATION . $year;

    my $marc = build_marc( { isbn => $isbn, title => $title } )->as_xml( 'UTF-8', 'MARC21' );

    # The MARC XML travels escaped inside MessageLine.
    my $marc_escaped = $marc;
    $marc_escaped =~ s/&/&amp;/g;
    $marc_escaped =~ s/</&lt;/g;
    $marc_escaped =~ s/>/&gt;/g;
    $marc_escaped =~ s/"/&quot;/g;

    # SubLineNumber is required by Validator::validateEditxContent and never
    # read by the processor, which makes it the honest "validation only" field.
    my $sub_line = ( $omit && $omit eq 'SubLineNumber' )
        ? ''
        : "            <SubLineNumber>1</SubLineNumber>\n";

    return <<"XML";
    <ItemDetail>
        <LineNumber>$params->{index}</LineNumber>
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
            <Author>Rerun, Fixture</Author>
            <SeriesTitle></SeriesTitle>
            <VolumeOrPart/>
            <EditionStatement/>
            <CityOfPublication></CityOfPublication>
            <PublisherName>EDItX Rerun Press</PublisherName>
            <YearOfPublication>$year</YearOfPublication>
        </ItemDescription>
        <QuantityShipping>1</QuantityShipping>
        <ReferenceCoded>
            <ReferenceTypeCode>VendorsOrderReference</ReferenceTypeCode>
            <ReferenceNumber>$params->{reference}</ReferenceNumber>
            <ReferenceDate>@{[ DateTime->now->strftime('%d.%m.%Y') ]}</ReferenceDate>
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
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>SRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>10</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <CopyDetail>
$sub_line            <CopyQuantity>1</CopyQuantity>
            <DeliverToLocation>$deliver_to</DeliverToLocation>
            <DestinationLocation>$deliver_to</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>$price</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <LocationCode>$BRANCH;$LOCATION;1</LocationCode>
            <ReaderInterestCode/>
            <FundDetail>
                <FundNumber>$FUND</FundNumber>
                <MonetaryAmount>$price</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>$marc_escaped</MessageLine>
            </Message>
            <RequestedBy/>
            <ApprovedBy/>
        </CopyDetail>
    </ItemDetail>
XML
}

sub build_message {
    my ($params) = @_;

    my $lines = '';
    for my $line ( @{ $params->{lines} } ) {
        $lines .= build_line($line);
    }

    return qq{<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>$params->{ship_notice_num}</ShipNoticeNumber>
        <IssueDateTime>$params->{issue_date_time}</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>@{[ DateTime->now->strftime('%Y%m%d') ]}</Date>
            <DateQualifierCode>Shipped</DateQualifierCode>
        </DateCoded>
        <BuyerParty>
            <PartyID>
                <PartyIDType>VendorAssignedID</PartyIDType>
                <Identifier>$VENDOR_SAN</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>Kohala;FI-KOHA;016</NameLine>
            </PartyName>
        </BuyerParty>
        <SellerParty>
            <PartyID>
                <PartyIDType>BuyerAssignedID</PartyIDType>
                <Identifier>$VENDOR_ACCOUNT</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>$SELLER_NAME</NameLine>
            </PartyName>
        </SellerParty>
    </Header>
$lines    <Summary>
        <NumberOfLines>$params->{summary_lines}</NumberOfLines>
        <UnitsShipped>$params->{summary_lines}</UnitsShipped>
    </Summary>
</LibraryShipNotice>};
}

# ------------------------------------------------------------------- seeding

sub scenario_lines_for {
    my ($scenario, $count) = @_;

    my @lines;
    my @isbns = @{ $scenario->{isbns} };
    for my $index ( 1 .. $count ) {
        push @lines,
            {
            index     => $index,
            isbn      => $isbns[ $index - 1 ],
            title     => "$scenario->{key} line $index",
            reference => "$scenario->{key}-L$index",
            omit      => $scenario->{omit},
            };
    }

    return @lines;
}

sub process_fixture_lines {
    my ($scenario, $xml, $filename) = @_;

    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;

    my $order_processor = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor->new;

    my $order = $parser->parseDb($xml);
    die "$scenario->{key}: the seeded XML could not be parsed\n" if !$order;

    # process() identifies a line by the message filename, exactly as
    # process_edi_messages.pl sets it before calling process().
    $order->setFileName($filename);

    $order_processor->process($order);
}

sub store_failed_message {
    my ($scenario, $xml, $filename, $error) = @_;

    $dbh->do(
        "INSERT INTO edifact_messages (message_type, transfer_date, vendor_id, status, raw_msg, filename)
         VALUES ('EDItX', NOW(), ?, 'FAILED', ?, ?)",
        undef, $vendor_id, $xml, $filename
    );

    my $id = $dbh->last_insert_id( undef, undef, 'edifact_messages', 'id' );

    $dbh->do(
        "INSERT INTO edifact_errors (message_id, date, details) VALUES (?, NOW(), ?)",
        undef, $id, $error
    );

    return $id;
}

sub seed_scenario {
    my ($scenario) = @_;

    $scenario->{issue_date_time} = DateTime->now->strftime('%Y%m%dT%H%M');
    my $filename = fixture_filename($scenario);

    my @all_lines = scenario_lines_for( $scenario, $scenario->{lines} );

    my $full_xml = build_message(
        {
        ship_notice_num => $scenario->{key},
        issue_date_time => $scenario->{issue_date_time},
        lines           => \@all_lines,
        summary_lines   => $scenario->{lines},
        }
    );

    # The part that was written before the failure is produced by the real
    # processor, so the stored rows are the ones production would have.
    if ( $scenario->{seeded_lines} ) {
        my @seeded = @all_lines[ 0 .. $scenario->{seeded_lines} - 1 ];

        my $seed_xml = build_message(
            {
            ship_notice_num => $scenario->{key},
            issue_date_time => $scenario->{issue_date_time},
            lines           => \@seeded,
            summary_lines   => scalar @seeded,
            }
        );

        process_fixture_lines( $scenario, $seed_xml, $filename );

        my $orders = scalar_value(
            'SELECT COUNT(*) FROM aqorders WHERE order_vendornote = ?', $filename
        );
        say_new("$scenario->{key}: wrote $orders order(s) for the first $scenario->{seeded_lines} line(s)");
    }
    else {
        say_new("$scenario->{key}: nothing written before the failure");
    }

    # The stored error is the one a real run would have logged, so the failure
    # looks like the ones the notification e-mail already reports.
    my $error
        = $scenario->{omit}
        ? "Editx content validation failed: $scenario->{omit} not present\n"
        : "Budget ID not found for fund number: MISSINGFUND\n";

    my $id = store_failed_message( $scenario, $full_xml, $filename, $error );
    say_new("$scenario->{key}: edifact_messages id $id, status FAILED, filename $filename");

    $scenario->{filename} = $filename;
}

sub seed {
    print "Seeding $FIXTURE_PREFIX re-run fixtures\n";
    print "=" x 72 . "\n";

    # Re-seeding on top of an existing set would leave the old baskets, orders
    # and items behind under a filename nobody will requeue again.
    for my $scenario (@SCENARIOS) {
        my $existing = scalar_value(
            "SELECT COUNT(*) FROM edifact_messages WHERE message_type = 'EDItX' AND filename LIKE ?",
            "$scenario->{key}\\_%"
        );
        next if !$existing;

        die "$scenario->{key}: $existing message(s) from an earlier seed are still there."
            . "\nRun --clear first, then --seed, so the counts below describe one run.\n";
    }

    ensure_budget();
    check_config();
    build_parser();

    check_isbns();

    print "\nFixtures:\n";
    seed_scenario($_) for @SCENARIOS;

    print "\nDone. Next:\n";
    print "  perl cronjobs/check_editx_rerun_duplicates.pl --filename RR01\n";
    print "  perl seed_rerun_fixtures.pl --requeue\n";
    print "  perl cronjobs/process_edi_messages.pl\n";
    print "  perl seed_rerun_fixtures.pl --verify\n";
    print "  perl seed_rerun_fixtures.pl --receive\n";
}

sub check_isbns {
    print "\nISBNs:\n";

    for my $isbn (@ISBNS) {
        my $book = Business::ISBN->new($isbn);
        my $valid = $book && eval { $book->is_valid } ? 1 : 0;
        say_ok("$isbn is valid") if $valid;
        say_skip("$isbn is not a valid ISBN") if !$valid;

        # An existing record on this ISBN would make the automatch find it, so
        # the fixture would not create a new biblio and the counts would differ.
        my $stored = $dbh->selectcol_arrayref( 'SELECT biblionumber FROM biblioitems WHERE isbn = ?', undef, $isbn );
        die "$isbn is already stored on biblionumber " . join( ', ', @$stored )
            . "\nRemove those records or change the fixture ISBNs, otherwise the"
            . " scenario does not test what it claims to test.\n"
            if @$stored;
    }
}

# ------------------------------------------------------------------ receiving

# "Receive shipment from vendor" is acqui/parcels.pl: it creates a stock
# invoice and then marks the orders received. This does the same, so the
# fixture ends up in the state a real received delivery leaves behind.
sub pending_fixture_orders {
    my $rows = $dbh->selectall_arrayref(
        "SELECT o.ordernumber, o.quantity, o.unitprice, o.currency
         FROM aqorders o
         WHERE o.order_vendornote IN (SELECT filename FROM edifact_messages
                                      WHERE message_type = 'EDItX' AND filename LIKE ?)
           AND (o.quantityreceived IS NULL OR o.quantityreceived < o.quantity)
         ORDER BY o.ordernumber",
        { Slice => {} }, "$FIXTURE_PREFIX\\_%"
    );

    return @{$rows};
}

sub receive_fixtures {
    require C4::Acquisition;

    print "Receiving $FIXTURE_PREFIX fixtures\n";
    print "=" x 72 . "\n";

    my @pending = pending_fixture_orders();
    if ( !@pending ) {
        say_ok('no unreceived fixture orders, nothing to receive');
        return;
    }

    # AddInvoice is the same call the acquisitions UI makes, so the invoice
    # looks exactly like a stock invoice a user would have created.
    my $invoice_number = "$FIXTURE_PREFIX-RERUN-" . DateTime->now->strftime('%Y%m%dT%H%M');

    my $invoiceid = C4::Acquisition::AddInvoice(
        invoicenumber => $invoice_number,
        booksellerid  => $vendor_id,
        shipmentdate  => DateTime->now->strftime('%Y-%m-%d'),
    );

    die "AddInvoice did not return an invoiceid\n" if !$invoiceid;

    my $order_count = scalar @pending;
    say_new("invoice $invoice_number (id $invoiceid) for $order_count order(s)");

    # The same fields C4::Acquisition::ModReceiveOrder sets when the whole
    # order is received: no split, budget_id stays as it is.
    for my $order (@pending) {
        $dbh->do(
            "UPDATE aqorders
             SET quantityreceived = quantity,
                 datereceived     = CURDATE(),
                 invoiceid        = ?,
                 orderstatus      = 'complete',
                 invoice_unitprice = unitprice,
                 invoice_currency  = COALESCE(currency, 'EUR')
             WHERE ordernumber = ?",
            undef, $invoiceid, $order->{ordernumber}
        );
        say_ok("order $order->{ordernumber} received");
    }
}

# ------------------------------------------------------------------- requeue

sub requeue {
    print "Requeuing $FIXTURE_PREFIX fixtures\n";
    print "=" x 72 . "\n";

    for my $scenario (@SCENARIOS) {
        my $key = $scenario->{key};
        my $rows = $dbh->do(
            "UPDATE edifact_messages
             SET status = 'NEW'
             WHERE message_type = 'EDItX' AND status <> 'NEW' AND filename LIKE ?",
            undef, "$key\\_%"
        );
        $rows = defined $rows ? $rows : 0;

        say_ok("$key: $rows message(s) set to NEW")
            if $rows;
        say_ok("$key: messages were already NEW")
            if !$rows;
    }

    print "\nRun process_edi_messages.pl now, then --verify.\n";
}

# ------------------------------------------------------------------- clearing

sub clear_fixtures {
    print "Clearing $FIXTURE_PREFIX fixtures...\n";

    my @keys = map { $_->{key} } @SCENARIOS;
    my $basket_names = join ', ', map { sql_literal($_) } @keys;

    # Every fixture line gets the title "<KEY> line <n>", for the biblios this
    # script created.
    my $titles = join ', ',
        map {
        my $key = $_->{key};
        map { sql_literal("$key line $_") } ( 1, 2 );
        } @SCENARIOS;

    my $order_clause = "(SELECT ordernumber FROM aqorders
                          WHERE basketno IN (SELECT basketno FROM aqbasket WHERE basketname IN ($basket_names)))";

    my $itemnumbers
        = $dbh->selectcol_arrayref("SELECT itemnumber FROM aqorders_items WHERE ordernumber IN $order_clause");
    my $item_clause = @{$itemnumbers} ? 'itemnumber IN (' . join( ', ', @{$itemnumbers} ) . ')' : '1 = 0';

    # Order matters: aqbudgets_spend_log and aqorders.invoiceid point at rows
    # that are deleted below, so they go first.

    # The spend log stores the filename in origin, and the lookup goes through
    # edifact_messages, which is removed last.
    for my $scenario (@SCENARIOS) {
        my $key = $scenario->{key};
        my $rows = $dbh->do(
            "DELETE FROM aqbudgets_spend_log
             WHERE origin IN (SELECT filename FROM edifact_messages
                              WHERE message_type = 'EDItX' AND filename LIKE ?)",
            undef, "$key\\_%"
        );
        $rows = defined $rows ? $rows + 0 : 0;
        say_ok("aqbudgets_spend_log: removed $rows row(s)") if $rows;
    }

    # aqorders.invoiceid points at the stock invoice --receive created, so the
    # orders lose the link before the invoice goes.
    my @invoices = @{ $dbh->selectcol_arrayref(
        "SELECT invoiceid FROM aqinvoices WHERE invoicenumber LIKE ?", undef, "$FIXTURE_PREFIX-RERUN-%" ) };

    for my $invoiceid (@invoices) {
        my $unlinked = $dbh->do( 'UPDATE aqorders SET invoiceid = NULL WHERE invoiceid = ?', undef, $invoiceid );
        $unlinked = defined $unlinked ? $unlinked + 0 : 0;
        say_ok("aqorders: unlinked $unlinked order(s) from invoice $invoiceid") if $unlinked;
    }

    my @statements = (
        [ "DELETE FROM aqorders_items WHERE ordernumber IN $order_clause" => 'aqorders_items' ],
        [ "DELETE FROM items WHERE $item_clause" => 'items' ],
        [   "DELETE FROM aqorders
                 WHERE basketno IN (SELECT basketno FROM aqbasket WHERE basketname IN ($basket_names))" => 'aqorders'
        ],
        [ "DELETE FROM aqbasket WHERE basketname IN ($basket_names)" => 'aqbasket' ],
        [   "DELETE FROM biblioitems
                 WHERE biblionumber IN (SELECT biblionumber FROM biblio WHERE title IN ($titles))" => 'biblioitems'
        ],
        [   "DELETE FROM biblio_metadata
                 WHERE biblionumber IN (SELECT biblionumber FROM biblio WHERE title IN ($titles))" => 'biblio_metadata'
        ],
        [ "DELETE FROM biblio WHERE title IN ($titles)" => 'biblio' ],
    );

    for my $statement (@statements) {
        my ( $sql, $table ) = @$statement;
        my $rows = $dbh->do($sql);
        $rows = defined $rows ? $rows + 0 : 0;    # "0E0" is truthy as a string
        say_ok("$table: removed $rows row(s)") if $rows;
    }

    if (@invoices) {
        my $removed_invoices = $dbh->do(
            "DELETE FROM aqinvoices WHERE invoicenumber LIKE ?", undef, "$FIXTURE_PREFIX-RERUN-%" );
        say_ok( 'aqinvoices: removed ' . ( $removed_invoices || 0 ) . ' row(s)' ) if $removed_invoices;
    }

    my $removed = 0;
    for my $key (@keys) {
        $removed += $dbh->do(
            "DELETE FROM edifact_messages WHERE message_type = 'EDItX' AND filename LIKE ?",
            undef, "$key\\_%"
        ) || 0;
    }
    say_ok("edifact_messages: removed $removed row(s)") if $removed;

    print "Done. The infrastructure (vendor, fund, branch, location) was kept.\n";
}

# ---------------------------------------------------------------- verification

sub fixture_counts {
    my ($key) = @_;

    my $orders = scalar_value(
        "SELECT COUNT(*) FROM aqorders
         WHERE order_vendornote IN (SELECT filename FROM edifact_messages
                                    WHERE message_type = 'EDItX' AND filename LIKE ?)",
        "$key\\_%"
    );

    my $items = scalar_value(
        "SELECT COUNT(*) FROM aqorders_items
         WHERE ordernumber IN (SELECT ordernumber FROM aqorders
                               WHERE order_vendornote IN (SELECT filename FROM edifact_messages
                                                          WHERE message_type = 'EDItX' AND filename LIKE ?))",
        "$key\\_%"
    );

    my $spend = scalar_value(
        "SELECT COUNT(*) FROM aqbudgets_spend_log
         WHERE origin IN (SELECT filename FROM edifact_messages
                          WHERE message_type = 'EDItX' AND filename LIKE ?)",
        "$key\\_%"
    );

    my $baskets = scalar_value(
        "SELECT COUNT(DISTINCT basketno) FROM aqbasket WHERE basketname = ?", $key
    );

    return {
        orders  => $orders,
        items   => $items,
        spend   => $spend,
        baskets => $baskets,
    };
}

sub verify {
    print "\nVerification\n";
    print "=" x 72 . "\n";

    my @failures;

    for my $scenario (@SCENARIOS) {
        my $key = $scenario->{key};

        my $message = $dbh->selectrow_hashref(
            "SELECT id, status, filename FROM edifact_messages
             WHERE message_type = 'EDItX' AND filename LIKE ? ORDER BY id DESC",
            { Slice => {} }, "$key\\_%"
        );

        if ( !$message ) {
            say_bad("$key: no message found, the fixtures were not seeded");
            push @failures, $key;
            next;
        }

        if ( $message->{status} eq 'NEW' ) {
            say_bad("$key: message $message->{id} is still NEW, run --requeue and process_edi_messages.pl");
            push @failures, $key;
            next;
        }

        if ( $message->{status} eq $scenario->{expect_status} ) {
            say_ok("$key: message $message->{id} status $message->{status} as expected");
        }
        else {
            say_bad("$key: message $message->{id} status $message->{status}, expected $scenario->{expect_status}");
            push @failures, $key;
        }

        my $counts = fixture_counts($key);
        say_ok(
            "$key: $counts->{orders} order(s), $counts->{items} item(s), $counts->{baskets} basket(s), "
                . "$counts->{spend} spend-log row(s)"
        );

        if ( $counts->{orders} == $scenario->{expect_orders} ) {
            say_ok("$key: $counts->{orders} order(s) as expected");
        }
        else {
            say_bad("$key: $counts->{orders} order(s), expected $scenario->{expect_orders}");
            push @failures, $key;
        }

        if ( $counts->{items} == $scenario->{expect_items} ) {
            say_ok("$key: $counts->{items} item(s) as expected");
        }
        else {
            say_bad("$key: $counts->{items} item(s), expected $scenario->{expect_items}");
            push @failures, $key;
        }
    }

    print "\n" . ( '-' x 72 ) . "\n";
    if (@failures) {
        say_bad( 'FAILED: ' . join( ', ', @failures ) );
        print <<'HINT';

If the counts are higher than expected, OrderProcessor did not skip the lines
that were already written. Check that the deployed plugin contains the
lineAlreadyProcessed() change and that the messages carry the same filename as
the seeded orders (order_vendornote).
HINT
        return 1;
    }

    say_ok('All re-run fixtures behaved as expected.');
    return 0;
}

# ----------------------------------------------------------------------- main

# Koha::Plugins does not load Koha::Database, so require it before ->new.
require Koha::Database;

$dbh  = Koha::Database->new->dbh;
$year = DateTime->now->year;

exit 1 if $MODE_VERIFY && verify();
exit 0 if $MODE_VERIFY;

requeue()   if $MODE_REQUEUE;
clear_fixtures() if $MODE_CLEAR;
seed()      if $MODE_SEED;

if ( $MODE_RECEIVE ) {
    # AddInvoice needs the bookseller id; --receive can run on its own.
    ensure_vendor() unless $vendor_id;
    receive_fixtures();
}

exit 0;