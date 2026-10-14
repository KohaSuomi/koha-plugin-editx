#!/usr/bin/perl

use Modern::Perl;
use utf8;
use DateTime;
use Getopt::Long;
use Business::ISBN;

=head1 NAME

seed_automatch_fixtures.pl - Seed fixtures for the EDItX ISBN automatch scenarios

=head1 SYNOPSIS

    perl seed_automatch_fixtures.pl [OPTIONS]

    # 1. create the acquisition infrastructure and the fixtures
    perl seed_automatch_fixtures.pl --seed --borrowernumber=42

    # 2. process them (separate command)
    perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/Editx/cronjobs/process_edi_messages.pl

    # 3. check the outcome
    perl seed_automatch_fixtures.pl --verify

    # remove everything this script created
    perl seed_automatch_fixtures.pl --clear

=head1 DESCRIPTION

Creates NEW rows in Koha core's C<edifact_messages> table so that they are picked
up by C<process_edi_messages.pl>, together with the pre-existing bibliographic
records the automatch is supposed to find.

The point is the ISBN automatch in
C<OrderProcessor::getBiblioItemData>, which looks up C<biblioitems.isbn> using
every identifier in the order plus the equivalent ISBN forms:

    #17  search all identifiers, not only the first, and both hyphen forms
    #18  match across 10-digit and 13-digit ISBNs (check digit recomputed)

Every fixture uses a distinct ISBN pair so that exactly one stored record can
match a given message. That matters because C<getItemsByIsbns> returns all rows
and C<getBiblioItemData> takes an arbitrary one of them.

=head2 Scenarios

    AM01  stored 0306406152 (10-digit), order carries the 13-digit form
    AM02  first ProductID does not match, second one does
    AM03  control: nothing stored, a new biblio must be created
    AM04  wrong check digit must not be converted into a match

Stored bibioitems.isbn values are always unhyphenated, so the hyphen handling is
only exercised from the order side, where BTJ sends 020$a such as
978-0-306-40615-7. AM01 covers that.

=head1 OPTIONS

    --seed              Create/refresh the fixtures (default)
    --verify            Report the outcome of the processed fixtures
    --clear             Remove the fixtures created by this script
    --borrowernumber=N  Borrower owning the test fund (default: 51)
    --help              Show this help

=head1 NOTES

The infrastructure (currency, branch, location, vendor, budget period, fund) is
created if missing and is never removed by C<--clear>, so it can be shared with
other test data. C<--clear> only removes the AM* fixtures.

The seller name has to be exactly 'BTJ Finland Oy': the object factory picks the
vendor specific ItemDetail class from it, and C<ItemDetail::getNotes> returns an
empty string for the generic class, which makes C<createBiblio> fail validation.

=cut

my $FIXTURE_PREFIX = 'AM';

my $VENDOR_NAME    = 'TEST Vendor EDItX Automatch';
my $VENDOR_SAN     = '99001';
my $VENDOR_ACCOUNT = 'FI-EDITX-AUTOMATCH';
my $SELLER_NAME    = 'BTJ Finland Oy';

my $BRANCH   = 'CPL';
my $LOCATION = 'AIK';

my $MODE_SEED   = 0;
my $MODE_VERIFY = 0;
my $MODE_CLEAR  = 0;
my $borrowernumber = 51;
my $help        = 0;

GetOptions(
    'seed'              => \$MODE_SEED,
    'verify'            => \$MODE_VERIFY,
    'clear'             => \$MODE_CLEAR,
    'borrowernumber=i'  => \$borrowernumber,
    'help'              => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print <<'HELP';
Usage: seed_automatch_fixtures.pl [OPTIONS]

  --seed              Create/refresh the ISBN automatch fixtures (default)
  --verify            Report the outcome after running process_edi_messages.pl
  --clear             Remove the fixtures created by this script
  --borrowernumber=N  Borrower owning the test fund (default: 51)
  --help              Show this help

HELP
    exit 0;
}

$MODE_SEED = 1 unless $MODE_VERIFY || $MODE_CLEAR || $MODE_SEED;

# Pre-existing records the automatch is expected to find. Each one is matched by
# exactly one scenario.
my @STORED_RECORDS = (
    {
        key      => 'AM01',
        isbn     => '0306406152',
        title    => 'AM01 stored record, 10-digit isbn',
        author   => 'Stored, Ten',
        note     => 'order carries 9780306406157',
    },
    {
        key      => 'AM02',
        isbn     => '9789519900018',
        title    => 'AM02 stored record, 13-digit isbn',
        author   => 'Stored, Thirteen',
        note     => 'order carries it as the second ProductID',
    },
);

my @SCENARIOS = (
    {
        key          => 'AM01',
        title        => '#18 stored 10-digit isbn, order carries the 13-digit form',
        expect       => 'reuse',
        expect_key   => 'AM01',
        product_ids  => [ { type => 'EAN13', id => '9780306406157' } ],
        marc001      => '9780306406157',
        marc020      => '978-0-306-40615-7',
        biblio_title => 'AM01 order title',
    },
    {
        key          => 'AM02',
        title        => '#17 first ProductID does not match, the second one does',
        expect       => 'reuse',
        expect_key   => 'AM02',
        product_ids  => [
            { type => 'Seller', id => 'AM-NO-MATCH-0001' },
            { type => 'EAN13',  id => '9789519900018' },
        ],
        marc001      => '9789519900018',
        marc020      => '9519900012',
        biblio_title => 'AM02 order title',
    },
    {
        key          => 'AM03',
        title        => 'control: nothing stored, a new biblio is created',
        expect       => 'new',
        expect_key   => undef,
        product_ids  => [ { type => 'EAN13', id => '9789520003333' } ],
        marc001      => '9789520003333',
        marc020      => '978-952-00-0333-3',
        biblio_title => 'AM03 order title',
    },
    {
        key          => 'AM04',
        title        => 'wrong check digit must not match the stored 10-digit record',
        expect       => 'new',
        expect_key   => undef,
        product_ids  => [ { type => 'ISBN', id => '0306406153' } ],
        marc001      => '0306406153',
        marc020      => '0306406153',
        biblio_title => 'AM04 order title',
    },
);

my %STORED_BY_KEY = map { $_->{key} => $_ } @STORED_RECORDS;

my $dbh;
my $schema;
my $fund_code;
my $vendor_id;
my $budget_period_id;

# ---------------------------------------------------------------- utilities

sub say_ok   { print "  ok   $_[0]\n" }
sub say_skip { print "  --   $_[0]\n" }
sub say_new  { print "  new  $_[0]\n" }
sub say_bad  { print "  BAD  $_[0]\n" }

sub scalar_value {
    my ($sql, @bind) = @_;
    my $value = $dbh->selectrow_array($sql, undef, @bind);
    return $value;
}

sub sql_literal {
    my ($value) = @_;
    return 'NULL' unless defined $value;
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    return "'$value'";
}

# ------------------------------------------------------------------- fixtures

sub generate_xml {
    my ($params) = @_;

    my $ship_notice_num = $params->{ship_notice_num};
    my $title           = $params->{title};
    my $author          = $params->{author};
    my $marc001         = $params->{marc001};
    my $marc020         = $params->{marc020};
    my $publisher       = $params->{publisher} // 'EDItX Automatch Press';
    my $year            = $params->{year} // DateTime->now->year;
    my $price           = $params->{price} // '12.00';
    my $location        = $BRANCH . $LOCATION . $year;

    my $product_ids = '';
    for my $product_id (@{ $params->{product_ids} }) {
        $product_ids .= <<"XML";
        <ProductID>
            <ProductIDType>$product_id->{type}</ProductIDType>
            <Identifier>$product_id->{id}</Identifier>
        </ProductID>
XML
    }

    return qq{<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>$ship_notice_num</ShipNoticeNumber>
        <IssueDateTime>@{[ DateTime->now->strftime('%Y%m%dT%H%M') ]}</IssueDateTime>
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
    <ItemDetail>
        <LineNumber>1</LineNumber>
$product_ids        <ItemDescription>
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
        <QuantityShipping>1</QuantityShipping>
        <ReferenceCoded>
            <ReferenceTypeCode>VendorsOrderReference</ReferenceTypeCode>
            <ReferenceNumber>$ship_notice_num</ReferenceNumber>
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
            <SubLineNumber>1</SubLineNumber>
            <CopyQuantity>1</CopyQuantity>
            <DeliverToLocation>$location</DeliverToLocation>
            <DestinationLocation>$location</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>$price</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <LocationCode>$BRANCH;$LOCATION;1</LocationCode>
            <ReaderInterestCode/>
            <FundDetail>
                <FundNumber>$fund_code</FundNumber>
                <MonetaryAmount>$price</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
&lt;collection xmlns=&quot;http://www.loc.gov/MARC21/slim&quot;&gt;
 &lt;record&gt;
  &lt;leader&gt;00000nam a22000008a 4500&lt;/leader&gt;
  &lt;controlfield tag=&quot;001&quot;&gt;$marc001&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;003&quot;&gt;FI-Test&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;005&quot;&gt;20240326101401.0&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;008&quot;&gt;240315s$year    fi                  fin&lt;/controlfield&gt;
  &lt;datafield tag=&quot;020&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;$marc020&lt;/subfield&gt;
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
</LibraryShipNotice>};
}

# ------------------------------------------------------------- infrastructure

sub ensure_currency {
    my $exists = scalar_value("SELECT COUNT(*) FROM currency WHERE currency = 'EUR'");
    return say_ok('currency EUR') if $exists;

    $dbh->do(
        "INSERT INTO currency (currency, symbol, isocode, timestamp, rate, active) VALUES ('EUR', ?, 'EUR', NOW(), 1.0, 1)",
        undef, "\x{20ac}"
    );
    say_new('currency EUR');
}

sub ensure_branch {
    my $exists = scalar_value('SELECT COUNT(*) FROM branches WHERE branchcode = ?', $BRANCH);
    return say_ok("branch $BRANCH") if $exists;

    $dbh->do('INSERT INTO branches (branchcode, branchname) VALUES (?, ?)', undef, $BRANCH, "EDItX automatch $BRANCH");
    say_new("branch $BRANCH");
}

sub ensure_location {
    my $exists = scalar_value(
        "SELECT COUNT(*) FROM authorised_values WHERE category = 'LOC' AND authorised_value = ?",
        $LOCATION
    );
    return say_ok("location $LOCATION") if $exists;

    $dbh->do(
        "INSERT INTO authorised_values (category, authorised_value, lib) VALUES ('LOC', ?, ?)",
        undef, $LOCATION, "EDItX automatch $LOCATION"
    );
    say_new("location $LOCATION");
}

sub ensure_vendor {
    $vendor_id = scalar_value('SELECT id FROM aqbooksellers WHERE name = ?', $VENDOR_NAME);

    if ( !$vendor_id ) {
        $dbh->do(
            'INSERT INTO aqbooksellers (name, address1, accountnumber, notes, postal, active) VALUES (?, ?, ?, ?, ?, ?)',
            undef, $VENDOR_NAME, 'Automatch Street 1', $VENDOR_ACCOUNT, 'EDItX automatch test vendor', '00100', 1
        );
        $vendor_id = $dbh->last_insert_id(undef, undef, 'aqbooksellers', undef);
        say_new("vendor $VENDOR_NAME (id $vendor_id)");
    }
    else {
        say_ok("vendor $VENDOR_NAME (id $vendor_id)");
    }

    my $account_id = scalar_value(
        "SELECT id FROM vendor_edi_accounts WHERE vendor_id = ? AND san = ? AND transport = 'FILE' AND orders_enabled = 1",
        $vendor_id, $VENDOR_SAN
    );

    if ( !$account_id ) {
        $dbh->do(
            'INSERT INTO vendor_edi_accounts (description, vendor_id, san, id_code_qualifier, transport, orders_enabled)
             VALUES (?, ?, ?, 91, \'FILE\', 1)',
            undef, 'EDItX automatch EDI account', $vendor_id, $VENDOR_SAN
        );
        $account_id = $dbh->last_insert_id(undef, undef, 'vendor_edi_accounts', undef);
        say_new("vendor_edi_accounts SAN $VENDOR_SAN (id $account_id)");
    }
    else {
        say_ok("vendor_edi_accounts SAN $VENDOR_SAN (id $account_id)");
    }
}

sub ensure_budget {
    my $year = DateTime->now->year;
    my $description = "TEST Automatch Budget Period $year";

    $budget_period_id = scalar_value(
        'SELECT budget_period_id FROM aqbudgetperiods WHERE budget_period_description = ?',
        $description
    );

    if ( !$budget_period_id ) {
        $dbh->do(
            'INSERT INTO aqbudgetperiods (budget_period_startdate, budget_period_enddate, budget_period_description, budget_period_total, budget_period_active)
             VALUES (?, ?, ?, ?, 1)',
            undef, "$year-01-01", "$year-12-31", $description, 100000
        );
        $budget_period_id = $dbh->last_insert_id(undef, undef, 'aqbudgetperiods', undef);
        say_new("$description (id $budget_period_id)");
    }
    else {
        say_ok("$description (id $budget_period_id)");
    }

    $fund_code = 'AMAUTOMATCH';

    my $fund_id = scalar_value('SELECT budget_id FROM aqbudgets WHERE budget_code = ?', $fund_code);
    if ( !$fund_id ) {
        $dbh->do(
            'INSERT INTO aqbudgets (budget_code, budget_name, budget_amount, budget_period_id, budget_owner_id, budget_notes)
             VALUES (?, ?, ?, ?, ?, ?)',
            undef, $fund_code, 'TEST EDItX automatch fund', 50000, $budget_period_id, $borrowernumber, 'EDItX automatch'
        );
        say_new("fund $fund_code");
    }
    else {
        say_ok("fund $fund_code");
    }
}

sub check_borrower {
    my $exists = scalar_value('SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ?', $borrowernumber);
    die "borrowernumber $borrowernumber does not exist, pass a valid one with --borrowernumber\n" if !$exists;
    say_ok("borrowernumber $borrowernumber");
}

sub check_config {
    # Loaded here rather than at compile time so --help and --clear work even
    # when the plugin directory is not in @INC.
    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;

    my $config   = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new;
    my $settings = $config->getSettings();
    my $authoriser = $settings->{settings}->{authoriser};
    my $allowed    = $settings->{settings}->{allowed_locations};
    my $automatch  = $settings->{settings}->{automatch_biblios};

    die "authoriser is not configured; OrderProcessor::process dies without it\n" if !$authoriser;
    say_ok("authoriser $authoriser");

    my $authoriser_exists = scalar_value('SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ?', $authoriser);
    die "authoriser $authoriser is not a valid borrowernumber\n" if !$authoriser_exists;
    say_ok("authoriser $authoriser exists");

    my %allowed = map { $_ => 1 } grep { $_ } split /,/, ($allowed // '');
    die "allowed_locations must contain $LOCATION for the fixtures to resolve\n" if !$allowed{$LOCATION};
    say_ok("allowed_locations contains $LOCATION");

    if ( defined $automatch && $automatch eq 'no' ) {
        die "automatch_biblios is 'no', the scenarios cannot pass\n";
    }
    say_ok('automatch_biblios enabled');

    my $has_map = scalar_value(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'map_productform'"
    );
    if ($has_map) {
        my $mapped = scalar_value("SELECT COUNT(*) FROM map_productform WHERE onix_code = 'BK'");
        say_skip('map_productform has no BK row, productform falls back to the literal "BK"') if !$mapped;
    }
    else {
        say_skip('map_productform table missing, productform falls back to the literal "BK"');
    }
}

sub ensure_infrastructure {
    print "\nInfrastructure:\n";
    check_borrower();
    ensure_currency();
    ensure_branch();
    ensure_location();
    ensure_vendor();
    ensure_budget();
}

# ------------------------------------------------------------------- fixtures

sub seed_stored_records {
    print "\nPre-existing records the automatch must find:\n";

    for my $record (@STORED_RECORDS) {
        my $biblionumber = scalar_value('SELECT biblionumber FROM biblio WHERE title = ?', $record->{title});

        if ($biblionumber) {
            say_ok("$record->{key}: $record->{isbn} already on biblionumber $biblionumber");
        }
        else {
            # datecreated is NOT NULL without a default in the biblio table.
            $biblionumber = $schema->resultset('Biblio')->create(
                {
                    title       => $record->{title},
                    author      => $record->{author},
                    notes       => $record->{note},
                    datecreated => DateTime->now->strftime('%Y-%m-%d'),
                }
            )->biblionumber;

            $schema->resultset('Biblioitem')->create(
                {
                    biblionumber => $biblionumber,
                    isbn         => $record->{isbn},
                }
            );

            say_new("$record->{key}: biblionumber $biblionumber, isbn $record->{isbn}");
        }

        $record->{biblionumber} = $biblionumber;
    }
}

sub check_isbn_pairs {
    print "\nISBN pairs:\n";

    for my $scenario (@SCENARIOS) {
        for my $product_id ( @{ $scenario->{product_ids} }, { type => 'marc020', id => $scenario->{marc020} } ) {
            my $plain = $product_id->{id};
            $plain =~ s/-//g;
            next if $plain !~ /^\d{9}[\dX]$|^\d{13}$/;

            my $isbn = Business::ISBN->new($plain);
            my $valid = $isbn && eval { $isbn->is_valid } ? 'valid' : 'invalid';

            # AM04 deliberately carries a wrong check digit.
            if ( $scenario->{key} eq 'AM04' ) {
                say_skip("$scenario->{key}: $plain is $valid (intentional)");
            }
            else {
                die "$scenario->{key}: isbn $plain is not valid, the fixture would not test anything\n" if $valid eq 'invalid';
                say_ok("$scenario->{key}: $plain is $valid");
            }
        }
    }
}

sub check_isbn_collisions {
    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;

    print "\nStored ISBN collisions:\n";

    my @problems;

    for my $record (@STORED_RECORDS) {
        # Ignore the row we created ourselves on a previous run.
        my $mine = scalar_value( 'SELECT biblionumber FROM biblio WHERE title = ?', $record->{title} );

        my $sql = 'SELECT biblionumber FROM biblioitems WHERE isbn = ?';
        my @bind = ( $record->{isbn} );
        if ($mine) {
            $sql .= ' AND biblionumber <> ?';
            push @bind, $mine;
        }

        my @found = @{ $dbh->selectcol_arrayref( $sql, undef, @bind ) };
        if (@found) {
            say_bad("$record->{key}: $record->{isbn} is already on biblionumber " . join( ', ', @found ) );
            push @problems, $record->{key};
        }
        else {
            say_ok("$record->{key}: $record->{isbn} is not used by any other record");
        }
    }

    # A scenario that expects a new biblio must not be able to match anything,
    # including records that were already in the database.
    for my $scenario (@SCENARIOS) {
        next if $scenario->{expect} eq 'reuse';

        my @forms;
        for my $identifier ( map { $_->{id} } @{ $scenario->{product_ids} } ) {
            push @forms,
                Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor->getIsbnLookupForms($identifier);
        }
        push @forms,
            Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor->getIsbnLookupForms( $scenario->{marc020} );

        my %seen;
        my @hits;
        for my $form ( grep { defined && length && !$seen{$_}++ } @forms ) {
            my $rows = $dbh->selectcol_arrayref( 'SELECT biblionumber FROM biblioitems WHERE isbn = ?', undef, $form );
            push @hits, "$form => @{$rows}" if @{$rows};
        }

        if (@hits) {
            say_bad("$scenario->{key}: expects a new biblio but these forms already exist: " . join( '; ', @hits ) );
            push @problems, $scenario->{key};
        }
        else {
            say_ok("$scenario->{key}: no stored record matches any of its lookup forms");
        }
    }

    die
        "\nFix the fixture ISBNs before seeding: @problems\n"
        . "getItemsByIsbns returns every match and getBiblioItemData takes an arbitrary\n"
        . "one, so an ISBN that already exists makes the outcome depend on row order.\n"
        if @problems;
}

sub seed_messages {
    print "\nEDItX messages (status NEW):\n";

    for my $scenario (@SCENARIOS) {
        my $filename = $scenario->{key} . '_' . DateTime->now->strftime('%Y%m%dT%H%M');

        my $existing = scalar_value(
            "SELECT COUNT(*) FROM edifact_messages WHERE message_type = 'EDItX' AND filename LIKE ?",
            $scenario->{key} . '\\_%'
        );

        if ($existing) {
            say_skip("$scenario->{key}: a message already exists, delete it first or use --clear");
            next;
        }

        my $xml = generate_xml(
            {
                ship_notice_num => $scenario->{key},
                title           => $scenario->{biblio_title},
                author          => 'Order, Author',
                product_ids     => $scenario->{product_ids},
                marc001         => $scenario->{marc001},
                marc020         => $scenario->{marc020},
            }
        );

        $dbh->do(
            "INSERT INTO edifact_messages (message_type, transfer_date, vendor_id, status, raw_msg, filename)
             VALUES ('EDItX', ?, ?, 'NEW', ?, ?)",
            undef, DateTime->now->strftime('%Y-%m-%d'), $vendor_id, $xml, $filename
        );

        my $id = $dbh->last_insert_id(undef, undef, 'edifact_messages', undef);
        say_new("$scenario->{key}: edifact_messages id $id, expect '$scenario->{expect}'");
    }
}

# -------------------------------------------------------------------- clearing

sub clear_fixtures {
    print "Clearing $FIXTURE_PREFIX fixtures...\n";

    my @keys = map { $_->{key} } @SCENARIOS;

    # These two maps have to be separate: folding the second one into the first
    # one's LIST would apply the first block to the strings it returns.
    my @stored_titles   = map { $_->{title} } @STORED_RECORDS;
    my @scenario_titles = map { $_->{biblio_title} } @SCENARIOS;
    my @titles = ( @stored_titles, @scenario_titles );

    my $basket_names = join ', ', map { sql_literal($_) } @keys;
    my $biblio_titles = join ', ', map { sql_literal($_) } @titles;

    my $order_clause = "(SELECT ordernumber FROM aqorders
                          WHERE basketno IN (SELECT basketno FROM aqbasket WHERE basketname IN ($basket_names)))";

    # Collect the items before the orders go away. Picking them by biblio is not
    # enough: a scenario that matched somebody else's record puts its item there.
    my $itemnumbers = $dbh->selectcol_arrayref("SELECT itemnumber FROM aqorders_items WHERE ordernumber IN $order_clause");
    my $item_clause = @{$itemnumbers} ? 'itemnumber IN (' . join( ', ', @{$itemnumbers} ) . ')' : '1 = 0';

    # Every subquery below targets a different table, otherwise MySQL refuses
    # the statement with "You can't specify target table for update in FROM".
    my @statements = (
        [   "DELETE FROM aqorders_items WHERE ordernumber IN $order_clause" => 'aqorders_items'
        ],
        [   "DELETE FROM items WHERE $item_clause" => 'items'
        ],
        [   "DELETE FROM aqorders
             WHERE basketno IN (SELECT basketno FROM aqbasket WHERE basketname IN ($basket_names))" => 'aqorders'
        ],
        [   "DELETE FROM aqbasket WHERE basketname IN ($basket_names)" => 'aqbasket'
        ],
        [   "DELETE FROM biblioitems
             WHERE biblionumber IN (SELECT biblionumber FROM biblio WHERE title IN ($biblio_titles))" => 'biblioitems'
        ],
        [   "DELETE FROM biblio WHERE title IN ($biblio_titles)" => 'biblio'
        ],
    );

    for my $statement (@statements) {
        my ($sql, $table) = @$statement;
        my $rows = $dbh->do($sql);
        $rows = defined $rows ? $rows + 0 : 0;    # "0E0" is truthy as a string
        say_ok("$table: removed $rows row(s)") if $rows;
    }

    # Done per key with a bound pattern: 'AM\_%' would mean the literal "AM_",
    # and the filenames are AM01_<timestamp>.
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

sub verify {
    print "\nVerification\n";
    print "=" x 72 . "\n";

    my @failures;
    my @stored_biblos = map { scalar_value('SELECT biblionumber FROM biblio WHERE title = ?', $_->{title}) } @STORED_RECORDS;
    my %is_stored = map { $_ => 1 } grep { $_ } @stored_biblos;

    for my $scenario (@SCENARIOS) {
        my $key = $scenario->{key};

        my $message = $dbh->selectrow_hashref(
            "SELECT id, status FROM edifact_messages WHERE message_type = 'EDItX' AND filename LIKE ? ORDER BY id DESC",
            { Slice => {} }, "$key\\_%"
        );

        if ( !$message ) {
            say_bad("$key: no message found, the fixtures were not seeded");
            push @failures, $key;
            next;
        }

        my $basketno = scalar_value('SELECT basketno FROM aqbasket WHERE basketname = ?', $key);
        if ( !$basketno ) {
            say_bad("$key: message status $message->{status}, but no basket '$key' was created");
            push @failures, $key;
            next;
        }

        my $orders = $dbh->selectall_arrayref(
            "SELECT ordernumber, biblionumber FROM aqorders WHERE basketno = ? ORDER BY ordernumber",
            { Slice => {} }, $basketno
        );

        if ( !@$orders ) {
            say_bad("$key: message status $message->{status}, basket $basketno has no orders");
            push @failures, $key;
            next;
        }

        my $order      = $orders->[0];
        my $biblionumber = $order->{biblionumber};

        if ( $scenario->{expect} eq 'reuse' ) {
            my $stored_record = $STORED_BY_KEY{ $scenario->{expect_key} };
            my $stored_number = scalar_value( 'SELECT biblionumber FROM biblio WHERE title = ?', $stored_record->{title} );

            if ( defined $biblionumber && defined $stored_number && $biblionumber == $stored_number ) {
                say_ok("$key: reused biblionumber $biblionumber as expected ($scenario->{title})");
            }
            else {
                say_bad("$key: order points at biblionumber " . ( defined $biblionumber ? $biblionumber : 'undef' )
                        . ", expected $stored_number");
                push @failures, $key;
            }
        }
        else {
            if ( defined $biblionumber && !$is_stored{$biblionumber} ) {
                say_ok("$key: created a new biblionumber $biblionumber as expected ($scenario->{title})");
            }
            else {
                say_bad("$key: expected a new biblio, but the order points at $biblionumber");
                push @failures, $key;
            }
        }

        say_skip("$key: message status $message->{status}") if $message->{status} ne 'OK';
    }

    print "=" x 72 . "\n";
    if (@failures) {
        print "FAILED: @failures\n";
        return 1;
    }

    print "All scenarios behaved as expected.\n";
    return 0;
}

# ------------------------------------------------------------------------ main

if ( !$ENV{'KOHA_CONF'} ) {
    die "KOHA_CONF is not set, run this through koha-shell <instance>\n";
}

# Loaded after the guard so a missing KOHA_CONF produces one clear message.
require C4::Context;
require Koha::Database;

$dbh    = C4::Context->dbh;
$schema = Koha::Database->new->schema;

if ($MODE_CLEAR) {
    clear_fixtures();
    exit 0;
}

if ($MODE_VERIFY) {
    exit verify();
}

say "EDItX ISBN automatch fixtures ($FIXTURE_PREFIX)";
say '====================================================';

ensure_infrastructure();
check_config();
check_isbn_pairs();
check_isbn_collisions();
seed_stored_records();
seed_messages();

print "\n" . '=' x 60 . "\n";
print "Fixtures ready.\n\n";
print "Next steps:\n";
print "  1. process them:\n";
print "       perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/Editx/cronjobs/process_edi_messages.pl\n";
print "  2. check the outcome:\n";
print "       perl seed_automatch_fixtures.pl --verify\n";
print "  3. clean up:\n";
print "       perl seed_automatch_fixtures.pl --clear\n";
print '=' x 60 . "\n";