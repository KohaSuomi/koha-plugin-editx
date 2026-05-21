#!/usr/bin/perl
package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage;

use C4::Context;
use Data::Dumper;
use File::Basename;
use XML::LibXML;

my $singleton;

sub new {
    my $class = shift;
    $singleton ||= bless {}, $class;
}

sub add {
    my $self = shift;
    my $messagefile = $_[0];
    my $raw_message = $_[1];
    my $status = $_[2] // 'NEW';
    my $dbh = C4::Context->dbh;
    $dbh->do("DELETE FROM edifact_messages WHERE filename='$messagefile'");
    my $sth = $dbh->prepare("INSERT INTO edifact_messages (message_type, transfer_date, raw_msg, filename, status) VALUES ('EDItX', NOW(), ?, ?, ?)");
    $sth->execute($raw_message, $messagefile, $status);
}

sub create {
    my $self = shift;
    my $raw_message = $_[0];
    my $filename = $_[1];
    my $vendor_id = $_[2];
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("INSERT INTO edifact_messages (message_type, transfer_date, raw_msg, filename, status, vendor_id) VALUES ('EDItX', NOW(), ?, ?, 'NEW', ?)");
    $sth->execute($raw_message, $filename, $vendor_id);
}

sub update {
    my $self = shift;
    my $identifier = $_[0];
    my $status = $_[1];
    my $dbh = C4::Context->dbh;

    # Prefer id-based updates used by the REST controller.
    my $sth = $dbh->prepare("UPDATE edifact_messages SET status=? WHERE id=?");
    $sth->execute($status, $identifier);
    my $rows = $sth->rows;

    # Backward compatibility: older callers may pass filename.
    if ($rows == 0) {
        my $fallback_sth = $dbh->prepare("UPDATE edifact_messages SET status=? WHERE filename=?");
        $fallback_sth->execute($status, $identifier);
        $rows = $fallback_sth->rows;
    }

    return $rows;
}

sub claimForProcessing {
    my $self = shift;
    my $id = $_[0];
    my $dbh = C4::Context->dbh;

    # Atomic claim: only one worker can flip NEW -> PROCESSING.
    my $sth = $dbh->prepare("UPDATE edifact_messages SET status='PROCESSING' WHERE id=? AND status='NEW'");
    $sth->execute($id);

    return $sth->rows;
}

sub delete {
    my $self = shift;
    my $identifier = $_[0];
    my $dbh = C4::Context->dbh;

    # Prefer id-based deletes.
    my $sth = $dbh->prepare("DELETE FROM edifact_messages WHERE id=?");
    $sth->execute($identifier);
    my $rows = $sth->rows;

    # Backward compatibility: older callers may pass filename.
    if ($rows == 0) {
        my $fallback_sth = $dbh->prepare("DELETE FROM edifact_messages WHERE filename=?");
        $fallback_sth->execute($identifier);
        $rows = $fallback_sth->rows;
    }

    return $rows;
}

sub list {
    my $self = shift;
    my $offset = $_[0];
    my $limit = $_[1];
    my $dbh = C4::Context->dbh;
    my $sth;

    if (defined $limit && $limit =~ /^\d+$/) {
        $offset = 0 unless defined $offset && $offset =~ /^\d+$/;
        $sth = $dbh->prepare("SELECT em.id as id, em.message_type, em.transfer_date, em.filename, em.status, ee.details FROM edifact_messages em LEFT JOIN edifact_errors ee ON ee.id = (SELECT ee2.id FROM edifact_errors ee2 WHERE ee2.message_id = em.id ORDER BY ee2.date DESC, ee2.id DESC LIMIT 1) WHERE em.message_type='EDItX' ORDER BY em.transfer_date DESC LIMIT ? OFFSET ?");
        $sth->execute($limit, $offset);
    } else {
        $sth = $dbh->prepare("SELECT em.id as id, em.message_type, em.transfer_date, em.filename, em.status, ee.details FROM edifact_messages em LEFT JOIN edifact_errors ee ON ee.id = (SELECT ee2.id FROM edifact_errors ee2 WHERE ee2.message_id = em.id ORDER BY ee2.date DESC, ee2.id DESC LIMIT 1) WHERE em.message_type='EDItX' ORDER BY em.transfer_date DESC");
        $sth->execute();
    }

    return $sth->fetchall_arrayref({});
}

sub total_count {
    my $self = shift;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT COUNT(*) FROM edifact_messages where message_type='EDItX'");
    $sth->execute();
    my ($total) = $sth->fetchrow_array();
    return $total;
}

sub findBookseller {
    my $self = shift;
    my $messagefile = $_[0];

    my $qualifier=91;
    my $san = XML::LibXML->new()->parse_file($messagefile)->findnodes('/LibraryShipNotice/Header/BuyerParty/PartyID[PartyIDType/text() = "VendorAssignedID"]/Identifier')->string_value();
    if (!$san) {
       $qualifier=92;
       $san = XML::LibXML->new()->parse_file($messagefile)->findnodes('/LibraryShipNotice/Header/SellerParty/PartyID[PartyIDType/text() = "BuyerAssignedID"]/Identifier')->string_value();
    }

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT vendor_id FROM vendor_edi_accounts WHERE san = ? AND id_code_qualifier=? AND transport='FILE' AND orders_enabled='1'");
    $sth->execute($san, $qualifier);
    my $vendor_id = $sth->fetchrow_array();
    my $basename = basename($messagefile);
    $dbh->do("UPDATE edifact_messages SET vendor_id='$vendor_id' WHERE filename='$basename'") if $vendor_id;
}


sub newEdiMessage {
    my $self = shift;
    my $xml = $_[0];
    my $editx_user = $_[1];

    my $filename = $self->constructFilename($xml, $editx_user);
    my $vendor_id = $self->findVendorId($xml);
    if (!$vendor_id) {
        die "Could not find matching vendor for the message";
    }
    if ($self->duplicateExists($filename)) {
        die "A message with the same filename already exists";
    }
    $self->create($xml, $filename, $vendor_id);
}

sub addToErrorLog {
    my $self = shift;
    my $identifier = $_[0];
    my $error_message = $_[1];
    my $dbh = C4::Context->dbh;

    # Prefer id-based lookup, but fall back to filename for older callers.
    my $message_id;
    if (defined $identifier && $identifier =~ /^\d+$/) {
        my $id_sth = $dbh->prepare("SELECT id FROM edifact_messages WHERE id=?");
        $id_sth->execute($identifier);
        $message_id = $id_sth->fetchrow_array();
    }

    if (!$message_id) {
        my $filename_sth = $dbh->prepare("SELECT id FROM edifact_messages WHERE filename=?");
        $filename_sth->execute($identifier);
        $message_id = $filename_sth->fetchrow_array();
    }

    return unless $message_id;

    my $insert_sth = $dbh->prepare("INSERT INTO edifact_errors (message_id, date, details) VALUES (?, NOW(), ?)");
    $insert_sth->execute($message_id, $error_message);
}

sub constructFilename {
    my $self = shift;
    my $xml = $_[0];
    my $editx_user = $_[1];
    my $ship_notice_number = $xml->findnodes('/LibraryShipNotice/Header/ShipNoticeNumber')->string_value();
    my $issue_date_time = $xml->findnodes('/LibraryShipNotice/Header/IssueDateTime')->string_value();
    my @parts = ($ship_notice_number, $issue_date_time);
    unshift @parts, $editx_user if defined $editx_user && $editx_user ne '';
    my $filename = join('_', @parts);
    return $filename;
}

sub findVendorId {
    my $self = shift;
    my $xml = $_[0];

    my $san = $xml->findnodes('/LibraryShipNotice/Header/BuyerParty/PartyID[PartyIDType/text() = "VendorAssignedID"]/Identifier')->string_value();
    if (!$san) {
       $san = $xml->findnodes('/LibraryShipNotice/Header/SellerParty/PartyID[PartyIDType/text() = "BuyerAssignedID"]/Identifier')->string_value();
    }

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT vendor_id FROM vendor_edi_accounts WHERE san = ? AND transport='FILE' AND orders_enabled='1'");
    $sth->execute($san);
    my $vendor_id = $sth->fetchrow_array();
    return $vendor_id;
}

sub duplicateExists {
    my $self = shift;
    my $filename = $_[0];
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT COUNT(*) FROM edifact_messages WHERE filename=?");
    $sth->execute($filename);
    my ($count) = $sth->fetchrow_array();
    return $count > 0;
}

sub parse_xml {
    my $self = shift;
    my $message = $_[0];
    my $xml;
    eval {
        $xml = XML::LibXML->new()->parse_string($message);
    };
    if ($@) {
        die "Invalid XML format: $@";
    }

    return $xml;
}

1;
