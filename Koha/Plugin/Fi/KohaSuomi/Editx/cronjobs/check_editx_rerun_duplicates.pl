#!/usr/bin/perl

# check_editx_rerun_duplicates.pl
#
# Read-only diagnostic: reports whether re-running an EDItX message would
# create duplicate acquisition records. This script never writes: it only runs
# the same SELECT lookups OrderProcessor::process performs and reports what
# already exists in the database.
#
# Usage:
#   perl cronjobs/check_editx_rerun_duplicates.pl            # list FAILED messages + summary
#   perl cronjobs/check_editx_rerun_duplicates.pl --id 42
#   perl cronjobs/check_editx_rerun_duplicates.pl --filename 661424_20261014T1900
#   perl cronjobs/check_editx_rerun_duplicates.pl --id 42 --json
#
# Requires the Koha environment (KOHA_CONF, perl module path) as the other
# cronjobs do.

use strict;
use warnings;
use Modern::Perl;
use Getopt::Long;
use JSON::MaybeXS;
use XML::LibXML::XPathContext;
use FindBin qw($Bin);
use File::Spec;

use Koha::Database;
use Koha::Plugins;
use C4::Context;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor::Order;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice;

binmode STDOUT, ':encoding(UTF-8)';

my $JSON = JSON::MaybeXS->new(utf8 => 1, pretty => 1);

my $edi_message = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage->new();
my $dbh = C4::Context->dbh;

my $opt_id;
my $opt_filename;
my $opt_funds = 0;
my $opt_json = 0;
my $opt_help = 0;
GetOptions(
    'id=i'      => \$opt_id,
    'filename=s' => \$opt_filename,
    'funds|f'   => \$opt_funds,
    'json'      => \$opt_json,
    'help|h'    => \$opt_help,
) or die "Bad options\n";

if ( $opt_help ) {
    print_usage();
    exit 0;
}

my $validator = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator->new();
my $orderProcessor = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor->new();
my $orderCreator = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor::Order->new();

my $parser = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::Parser->new(
    objectFactory =>
        Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::Xml::ObjectFactory::LibraryShipNotice->new(
        schemaPath => schema_path(),
        )
);

sub schema_path {
    my $candidate = File::Spec->catdir( $Bin, '..', 'Procurement', 'EditX', 'XmlSchema' ) . '/';
    return $candidate;
}

sub print_usage {
    print <<'USAGE';
Usage: check_editx_rerun_duplicates.pl [--id N | --filename NAME] [--funds] [--json]

Reports whether re-running an EDItX message would create duplicate
acquisition records (orders, baskets, spend-log rows, possibly a biblio).
Read-only: performs no database writes.

  (no options)          list FAILED messages with a duplicate-risk summary
  --id N                analyse the message with edifact_messages.id = N
  --filename NAME       analyse the message(s) with the given filename
  --funds               list the FundNumbers of every line per message and
                        mark the ones that are missing from aqbudgets
  --json                machine-readable output

In --funds mode, "written" is the number of lines processed before the first
line that would have died: those lines are the ones already stored from the
original run, and therefore the ones a re-run would duplicate.
USAGE
}

# ---------------------------------------------------------------- message load

sub fetch_message {
    my ($id) = @_;
    my $sth = $dbh->prepare(
        "SELECT id, filename, status, transfer_date, raw_msg
         FROM edifact_messages
         WHERE message_type = 'EDItX' AND id = ?
         LIMIT 1" );
    $sth->execute($id);
    return $sth->fetchrow_hashref;
}

sub fetch_messages_by_filename {
    my ($filename) = @_;
    my $sth = $dbh->prepare(
        "SELECT id, filename, status, transfer_date, raw_msg
         FROM edifact_messages
         WHERE message_type = 'EDItX' AND filename = ?
         ORDER BY id DESC" );
    $sth->execute($filename);
    my @rows;
    while ( my $row = $sth->fetchrow_hashref ) { push @rows, $row; }
    return @rows;
}

sub fetch_failed_messages {
    my $sth = $dbh->prepare(
        "SELECT m.id, m.filename, m.status, m.transfer_date, m.raw_msg,
                (SELECT e.details FROM edifact_errors e
                  WHERE e.message_id = m.id ORDER BY e.date DESC, e.id DESC LIMIT 1) AS last_error
         FROM edifact_messages m
         WHERE m.message_type = 'EDItX' AND m.status = 'FAILED'
         ORDER BY m.id DESC" );
    $sth->execute();
    my @rows;
    while ( my $row = $sth->fetchrow_hashref ) { push @rows, $row; }
    return @rows;
}

# ---------------------------------------------------------------- existence checks

sub existing_orders {
    my ($filename, $reference_numbers) = @_;
    my $sth = $dbh->prepare(
        "SELECT ordernumber, biblionumber, orderdate, order_vendornote, order_internalnote
         FROM aqorders
         WHERE order_vendornote = ?
         ORDER BY ordernumber" );
    $sth->execute($filename);
    my @rows;
    while ( my $row = $sth->fetchrow_hashref ) { push @rows, $row; }

    # A corrected re-send may carry a new IssueDateTime and therefore a new
    # filename, so the same lines can also be found by their reference number
    # (order_internalnote) from the original run.
    for my $reference (@{$reference_numbers}) {
        my $ref_sth = $dbh->prepare(
            "SELECT ordernumber, biblionumber, orderdate, order_vendornote, order_internalnote
             FROM aqorders
             WHERE order_internalnote = ?
             ORDER BY ordernumber" );
        $ref_sth->execute($reference);
        while ( my $row = $ref_sth->fetchrow_hashref ) {
            next if grep { $_->{ordernumber} eq $row->{ordernumber} } @rows;
            push @rows, $row;
        }
    }

    return @rows;
}

sub existing_baskets {
    my ($basketname) = @_;
    my $sth = $dbh->prepare(
        "SELECT basketno, basketname, booksellerid, authorisedby, closedate
         FROM aqbaskets
         WHERE basketname = ?
         ORDER BY basketno" );
    $sth->execute($basketname);
    my @rows;
    while ( my $row = $sth->fetchrow_hashref ) { push @rows, $row; }
    return @rows;
}

sub existing_spend_log {
    my ($filename) = @_;
    my $sth = $dbh->prepare(
        "SELECT COUNT(*) FROM aqbudgets_spend_log WHERE origin = ?" );
    $sth->execute($filename);
    my ($count) = $sth->fetchrow_array();
    return $count || 0;
}

# ---------------------------------------------------------------- analysis

sub analyse_message {
    my ($message) = @_;
    my $filename = $message->{filename};

    my $result = {
        id          => $message->{id},
        filename    => $filename,
        status      => $message->{status},
        transfer_date => $message->{transfer_date},
        last_error  => $message->{last_error},
        checks      => [],
        verdict     => 'UNKNOWN',
    };

    # The EDItX object is parsed from the stored raw message, exactly as
    # process_edi_messages.pl does.
    my $raw_msg = $message->{raw_msg};
    if ( !defined $raw_msg || $raw_msg eq '' ) {
        push @{ $result->{checks} },
            {
            check  => 'raw_msg',
            status => 'FAIL',
            detail => 'edifact_messages.raw_msg is empty, the message cannot be analysed',
            };
        $result->{verdict} = 'UNKNOWN';
        return $result;
    }

    my $order = $parser->parseDb($raw_msg);
    if ( !$order ) {
        push @{ $result->{checks} },
            {
            check  => 'parse',
            status => 'FAIL',
            detail => 'XML could not be parsed into an EDItX object, so processing would stop before any write',
            };
        $result->{verdict} = 'SAFE_TO_RERUN';
        return $result;
    }
    $order->setFileName($filename);

    my $basketname = eval { $order->getBasketName };

    # Validation (the same check the REST POST path runs, and which
    # process_edi_messages.pl runs before process()). If this fails, process()
    # is never reached and nothing is written.
    my $xml = eval { $edi_message->parse_xml($raw_msg) };
    if ($xml) {
        my @errors = $validator->validateEditxContent( $xml, $filename . ': ' );
        if (@errors) {
            push @{ $result->{checks} },
                {
                check  => 'validation',
                status => 'FAIL',
                detail => join( '; ', @errors ),
                };
            $result->{verdict} = 'SAFE_TO_RERUN';
            return $result;
        }
        push @{ $result->{checks} },
            { check => 'validation', status => 'OK', detail => 'no validation errors' };
    }

    # A failure in these checks would have occurred part-way through the
    # original run, leaving whatever the earlier lines wrote already in the
    # database. Any non-zero count below is what a re-run would duplicate.
    my @lines = line_outcomes( $order, $filename );
    my @reference_numbers = grep { defined } map { $_->{reference_number} } @lines;

    my @orders = existing_orders( $filename, \@reference_numbers );
    push @{ $result->{checks} },
        {
        check  => 'orders',
        status => ( @orders ? 'DUPLICATE' : 'OK' ),
        count  => scalar(@orders),
        detail => ( @orders
            ? 'a re-run would create ' . scalar(@orders) . ' more order(s); matched on order_vendornote (filename) and order_internalnote (reference number)'
            : 'no existing orders for this filename or its line reference numbers' ),
        rows   => [ map { { ordernumber => $_->{ordernumber}, biblionumber => $_->{biblionumber}, orderdate => $_->{orderdate}, internalnote => $_->{order_internalnote} } } @orders ],
        };

    if ( defined $basketname ) {
        my @baskets = existing_baskets($basketname);
        push @{ $result->{checks} },
            {
            check  => 'baskets',
            status => ( @baskets ? 'DUPLICATE' : 'OK' ),
            count  => scalar(@baskets),
            detail => ( @baskets
                ? 're-run would create a new basket with the same name (basketname = ShipNoticeNumber)'
                : 'no existing basket with this name' ),
            };
    }

    my $spend = existing_spend_log($filename);
    push @{ $result->{checks} },
        {
        check  => 'spend_log',
        status => ( $spend ? 'DUPLICATE' : 'OK' ),
        count  => $spend,
        detail => ( $spend
            ? "re-run would add $spend more aqbudgets_spend_log row(s) (origin = filename), double-counting spend"
            : 'no existing spend-log rows for this filename' ),
        };

    # Per-line outcome: biblio automatch (does a re-run reuse the biblio or
    # create a new one) and the budget lookup that kills processing mid-message.
    if (@lines) {
        my $has_new_biblio = grep { $_->{biblio_status} eq 'NEW_BIBLIO' } @lines;
        my $has_missing_budget = grep { $_->{budget_status} eq 'MISSING' } @lines;
        push @{ $result->{checks} },
            {
            check  => 'lines',
            status => ( ( $has_new_biblio || $has_missing_budget ) ? 'DUPLICATE' : 'OK' ),
            detail => 'per-line biblio automatch and budget lookup',
            lines  => \@lines,
            };
    }

    my $has_duplicate = grep { $_->{status} eq 'DUPLICATE' } @{ $result->{checks} };
    $result->{verdict} = $has_duplicate ? 'WOULD_DUPLICATE' : 'NO_DUPLICATES_FOUND';

    return $result;
}

# Replays, read-only, the lookups process() performs per line: the biblio
# automatch (OrderProcessor::getBiblioItemData) and the budget lookup that
# Order::createOrder does before it can create an order.
sub line_outcomes {
    my ($order, $filename) = @_;

    my @outcomes;
    my $itemDetails = eval { $order->getItems };
    return @outcomes unless $itemDetails && ref($itemDetails) eq 'ARRAY';

    foreach my $itemDetail (@$itemDetails) {
        my $copyDetails = eval { $itemDetail->getCopyDetail };
        next unless $copyDetails && ref($copyDetails) eq 'ARRAY';

        # How many copies the whole line asks for, summed over its copy details.
        my $line_expected = 0;
        for my $copyDetail (@$copyDetails) {
            my $qty = eval { $copyDetail->getCopyQuantity };
            $line_expected += $qty if defined $qty && $qty > 0;
        }

        foreach my $copyDetail (@$copyDetails) {
            my $copyQty = eval { $copyDetail->getCopyQuantity };
            next unless defined $copyQty && $copyQty > 0;

            my $title       = eval { $itemDetail->getTitle };
            my $reference   = eval { $itemDetail->getReferenceNumber };
            my $fundNumber  = eval { $copyDetail->getFundNumber };

            my ($biblio, $biblioitem, $biblio_error);
            {
                local $@;
                my @found = eval { $orderProcessor->getBiblioItemData( $copyDetail, $itemDetail, $order ) };
                $biblio_error = $@;
                ( $biblio, $biblioitem ) = @found;
            }

            my ( $budget_id, $budget_error );
            {
                local $@;
                $budget_id  = eval { $orderCreator->getBudgetId($fundNumber) };
                $budget_error = $@;
            }

            my %line = (
                title            => $title,
                reference_number => $reference,
                copy_quantity    => $copyQty,
                fund             => $fundNumber,
                budget_status    => ( $budget_id ? 'OK' : 'MISSING' ),
                budget_id        => $budget_id,
                items_to_create  => $copyQty,
            );

            # Whether the re-run would skip this line (orders and items already
            # stored) or write it again. A line whose order exists but is short
            # of items is neither: it needs the partial order cleaned up first.
            my $progress = eval { $orderCreator->getOrderProgress( $reference, $filename ) } || {};
            my $expected  = $line_expected || $copyQty;
            my $stored    = $progress->{items} // 0;
            my $found     = $progress->{orders} // 0;

            $line{stored_orders} = $found;
            $line{stored_items}  = $stored;
            $line{expected_items} = $expected;

            if ( !$found ) {
                $line{write_status} = 'WOULD_WRITE';
            }
            elsif ( $stored >= $expected ) {
                $line{write_status} = 'WOULD_SKIP';
            }
            else {
                $line{write_status} = 'PARTIAL';
                $line{partial_detail} =
                    "order(s) exist but only $stored of $expected item(s) are stored; "
                    . 'the re-run would write this line again and duplicate the order';
            }

            if ( $biblio_error && !defined $biblio ) {
                $line{biblio_status} = 'LOOKUP_ERROR';
                $line{error}         = $biblio_error;
            }
            elsif ( $biblio && $biblioitem ) {
                $line{biblio_status} = 'REUSES_BIBLIO';
                $line{biblionumber}  = $biblio;
                $line{biblio_detail} = "automatch finds biblio $biblio, so the biblio is reused";
            }
            else {
                $line{biblio_status} = 'NEW_BIBLIO';
                $line{biblio_detail} =
                    'automatch miss: the re-run would create a new biblio (automatch_biblios='
                    . ( eval { $orderProcessor->getConfig()->getUseAutomatchBiblios() } // 'no' ) . ')';
            }

            if ( $line{budget_status} eq 'MISSING' ) {
                $line{budget_detail} = "fund '$fundNumber' is not in aqbudgets"
                    . ( $budget_error ? " ($budget_error)" : '' )
                    . ': createOrder dies here, so the re-run stops at this line';
            }

            push @outcomes, \%line;
        }
    }

    return @outcomes;
}

# ---------------------------------------------------------------- output

sub print_analysis {
    my ($r) = @_;

    print "Message #$r->{id}  $r->{filename}  (status $r->{status}, received $r->{transfer_date})\n";
    print "  Last error: $r->{last_error}\n" if defined $r->{last_error};

    for my $c ( @{ $r->{checks} } ) {
        printf "  [%-10s] %-12s %s\n", $c->{status}, $c->{check}, $c->{detail} // '';
        if ( $c->{check} eq 'orders' && $c->{rows} && @{ $c->{rows} } ) {
            for my $row ( @{ $c->{rows} } ) {
                printf "               existing order #%s (biblio %s, %s)\n",
                    $row->{ordernumber}, $row->{biblionumber}, $row->{orderdate};
            }
        }
        if ( $c->{check} eq 'lines' && $c->{lines} ) {
            for my $line ( @{ $c->{lines} } ) {
                printf "               %-11s biblio=%-13s budget=%-8s items=%-3s %s\n",
                    ( $line->{write_status} // '?' ), $line->{biblio_status}, $line->{budget_status},
                    $line->{items_to_create},
                    ( defined $line->{title} ? $line->{title} : '' );
                print "                 $line->{biblio_detail}\n"   if $line->{biblio_detail};
                print "                 $line->{budget_detail}\n"   if $line->{budget_detail};
                print "                 $line->{partial_detail}\n" if $line->{partial_detail};
                print "                 error: $line->{error}\n"     if $line->{error};
            }
        }
    }

    print "  => VERDICT: $r->{verdict}\n\n";
}

# ---------------------------------------------------------------- fund scan

# Reads the FundNumbers straight from the stored XML with XPath, so it also
# works for messages that fail validation before the line walk ever runs.
sub scan_funds {
    my ($raw_msg) = @_;

    my $doc = eval { $edi_message->parse_xml($raw_msg) };
    return { error => 'raw_msg could not be parsed as XML' } if !$doc;

    my $xc = XML::LibXML::XPathContext->new($doc);
    my @funds = map { $_->textContent } $xc->findnodes('//CopyDetail/FundDetail/FundNumber');

    # One row per copy detail line, so the line order matches processing order.
    my @lines;
    my $index = 0;
    for my $fund (@funds) {
        $index++;
        push @lines,
            {
            line        => $index,
            fund        => $fund,
            budget_id   => undef,
            budget_ok   => 0,
            };
    }

    my %checked;
    for my $line (@lines) {
        my $fund = $line->{fund};
        next if exists $checked{$fund};
        $checked{$fund} = eval { $orderCreator->getBudgetId($fund) } || 0;
    }
    for my $line (@lines) {
        $line->{budget_id} = $checked{ $line->{fund} };
        $line->{budget_ok} = $line->{budget_id} ? 1 : 0;
    }

    my @distinct = do {
        my %seen;
        grep { !$seen{$_}++ } map { $_->{fund} } @lines;
    };

    # The first line whose fund is unknown is where process() dies; everything
    # before it has already been written. If no fund is missing, the message
    # failed somewhere else and the number cannot be derived from funds.
    my @missing_indexes = grep { !$lines[$_]{budget_ok} } 0 .. $#lines;
    my $written_before = @missing_indexes ? $missing_indexes[0] : undef;

    return {
        lines              => \@lines,
        line_count         => scalar @lines,
        distinct_funds     => \@distinct,
        missing_funds      => [ grep { !$checked{$_} } @distinct ],
        first_missing_line => ( defined $written_before ? $written_before + 1 : undef ),
        written_before     => $written_before,
        };
}

sub print_funds {
    my ($rows) = @_;

    if ( !@$rows ) {
        print "No FAILED EDItX messages found.\n";
        return;
    }

    printf "%-8s %-34s %5s %5s  %s\n", 'ID', 'FILENAME', 'LINES', 'WRIT', 'FUNDS (missing marked !)';
    for my $r (@$rows) {
        my $funds;
        if ( $r->{scan}{error} ) {
            $funds = $r->{scan}{error};
        }
        else {
            $funds = join( ', ',
                map { ( length $_->{fund} ? $_->{fund} : '(empty)' ) . ( $_->{budget_ok} ? '' : ' !' ) }
                    @{ $r->{scan}{lines} } );
        }
        printf "%-8s %-34s %5s %5s  %s\n", '#' . $r->{id}, ( $r->{filename} // '' ),
            ( defined $r->{scan}{line_count} ? $r->{scan}{line_count} : '-' ),
            ( defined $r->{scan}{written_before} ? $r->{scan}{written_before} : '-' ),
            $funds;
    }
}

# ---------------------------------------------------------------- main

my @messages;
if ( defined $opt_id ) {
    my $msg = fetch_message($opt_id);
    die "No EDItX message with id $opt_id\n" if !$msg;
    @messages = ($msg);
}
elsif ( defined $opt_filename ) {
    @messages = fetch_messages_by_filename($opt_filename);
    die "No EDItX message with filename '$opt_filename'\n" if !@messages;
}
else {
    @messages = fetch_failed_messages();
}

if ($opt_funds) {
    my @rows = map { { id => $_->{id}, filename => $_->{filename}, scan => scan_funds( $_->{raw_msg} ) } } @messages;

    if ($opt_json) {
        print $JSON->encode( \@rows );
    }
    else {
        print_funds( \@rows );
    }
    exit 0;
}

my @results = map { analyse_message($_) } @messages;

if ($opt_json) {
    print $JSON->encode( \@results );
}
elsif ( @results > 1 || ( !defined $opt_id && !defined $opt_filename ) ) {
    # List mode: one verdict line per message.
    if ( !@results ) {
        print "No FAILED EDItX messages found.\n";
    }
    for my $r (@results) {
        printf "Message #%-5s %-40s %s\n", $r->{id}, ( $r->{filename} // '' ), $r->{verdict};
    }
}
else {
    print_analysis($_) for @results;
}

exit 0;