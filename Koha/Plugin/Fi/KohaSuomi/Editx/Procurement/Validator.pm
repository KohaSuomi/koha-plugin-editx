#!/usr/bin/perl

package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator;

use strict;
use Modern::Perl;
use XML::LibXML qw();
use XML::LibXML::XPathContext;
use MARC::Record;
use C4::Context;

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger;

use utf8;
use open ':std', ':encoding(UTF-8)';
use Try::Tiny;
use File::Basename;

# Required single-value fields in Header
my @REQUIRED_HEADER_FIELDS = (
    { xpath => 'LibraryShipNotice/Header/BuyerParty/PartyName/NameLine', 
      name => 'BuyerParty PartyName NameLine' },
    { xpath => 'LibraryShipNotice/Header/SellerParty/PartyName/NameLine', 
      name => 'SellerParty PartyName NameLine',
      validator => \&validate_seller },
    { xpath => 'LibraryShipNotice/Header/BuyerParty/PartyID/Identifier', 
      name => 'BuyerParty PartyID Identifier', 
      capture => 'vendor' },
    { xpath => 'LibraryShipNotice/Header/SellerParty/PartyID/Identifier', 
      name => 'SellerParty PartyID Identifier', 
      capture => 'buyer' },
    { xpath => 'LibraryShipNotice/Header/BuyerParty/PartyID/PartyIDType', 
      name => 'BuyerParty PartyID PartyIDType' },
);

# Required single-value fields in Summary
my @REQUIRED_SUMMARY_FIELDS = (
    { xpath => 'LibraryShipNotice/Summary/NumberOfLines', name => 'NumberOfLines' },
    { xpath => 'LibraryShipNotice/Summary/UnitsShipped', name => 'UnitsShipped' },
);

# Required multi-value fields in ItemDetail
my @REQUIRED_ITEM_FIELDS = (
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/FundDetail/FundNumber', 
      name => 'FundNumber', 
      validator => \&validate_fund },
    { xpath => 'LibraryShipNotice/ItemDetail/ItemDescription/ProductForm', 
      name => 'ProductForm' },
    { xpath => 'LibraryShipNotice/ItemDetail/ItemDescription/Title', 
      name => 'Title' },
    { xpath => 'LibraryShipNotice/ItemDetail/QuantityShipping', 
      name => 'QuantityShipping' },
    { xpath => 'LibraryShipNotice/ItemDetail/PricingDetail/Price/Tax/TaxTypeCode', 
      name => 'TaxTypeCode' },
    { xpath => 'LibraryShipNotice/ItemDetail/PricingDetail/Price/Tax/Percent', 
      name => 'Tax Percent' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/SubLineNumber', 
      name => 'SubLineNumber' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/CopyQuantity', 
      name => 'CopyQuantity' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/DeliverToLocation', 
      name => 'DeliverToLocation' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/DestinationLocation', 
      name => 'DestinationLocation' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/ProcessingInstructionCode', 
      name => 'ProcessingInstructionCode' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/FundDetail/MonetaryAmount', 
      name => 'FundDetail MonetaryAmount' },
    { xpath => 'LibraryShipNotice/ItemDetail/CopyDetail/Message/MessageType', 
      name => 'MessageType', 
      validator => \&validate_message_type },
);

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    return $self;
}

sub validateEditx {
  my $filename = shift;
  my $fileforlog = basename($filename) . ": ";
  
  my $config = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new;
  my $settings = $config->getSettings();
  my $logPath = $settings->{'settings'}->{'log_directory'} 
    or die('The log_directory not set in config.');

  my $logger = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger->new($logPath);
  $logger->log("\nValidating file: $filename");
  $logger->logError("\n-- Validating file $fileforlog");

  my ($xc, $captures) = parse_xml($filename, $fileforlog, $logger);
  return unless $xc;

  my $errors = 0;

  # Validate header fields
  $errors += validate_fields($xc, \@REQUIRED_HEADER_FIELDS, $fileforlog, $logger, $captures);
  
  # Validate vendor EDI account
  $errors += validate_vendor($captures, $fileforlog, $logger);
  
  # Validate summary fields
  $errors += validate_fields($xc, \@REQUIRED_SUMMARY_FIELDS, $fileforlog, $logger, $captures);
  
  # Validate item detail fields
  $errors += validate_fields($xc, \@REQUIRED_ITEM_FIELDS, $fileforlog, $logger, $captures);

  # Final error reporting
  $logger->logError("${fileforlog}LibraryShipNotice required values errors: $errors");
  if ($errors > 0) {
    $logger->logError("${fileforlog}Validation failed");
    $logger->log("LibraryShipNotice errors detected -> must die.");
    die;
  }
  
  $logger->log("Validation success.");
}

sub validateEditxContent {
  my ($self, $xml_doc, $fileforlog, $logger) = @_;
  
  # Default values for optional parameters
  $fileforlog //= "API Request: ";
  
  # Create logger if not provided
  if (!$logger) {
    my $config = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new;
    my $settings = $config->getSettings();
    my $logPath = $settings->{'settings'}->{'log_directory'} || '/tmp';
    $logger = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger->new($logPath);
  }
  
  my $xc = XML::LibXML::XPathContext->new($xml_doc);
  my $captures = {};
  my @error_messages = ();
  
  # Validate all sections and collect errors
  validate_fields($xc, \@REQUIRED_HEADER_FIELDS, $fileforlog, $logger, $captures, \@error_messages);
  validate_vendor($captures, $fileforlog, $logger, \@error_messages);
  validate_fields($xc, \@REQUIRED_SUMMARY_FIELDS, $fileforlog, $logger, $captures, \@error_messages);
  validate_fields($xc, \@REQUIRED_ITEM_FIELDS, $fileforlog, $logger, $captures, \@error_messages);

  return @error_messages;
}

sub parse_xml {
  my ($filename, $fileforlog, $logger) = @_;
  
  my $xc;
  try {
    system("xmllint --noout $filename");
    
    my $parser = XML::LibXML->new();
    my $doc = XML::LibXML->load_xml(location => $filename);
    $xc = XML::LibXML::XPathContext->new($doc);
    
    my @nodes = $xc->findnodes('LibraryShipNotice');
    if (!@nodes) {
      $logger->logError("${fileforlog}Not a LibraryShipNotice XML file");
      die;
    }
  } catch {
    $logger->logError("${fileforlog}XML parser cannot parse the file. $_");
    die;
  };
  
  return ($xc, {});
}

sub validate_fields {
  my ($xc, $fields, $fileforlog, $logger, $captures, $error_messages) = @_;
  my $errors = 0;
  
  foreach my $field (@$fields) {
    my $xpath = $field->{xpath};
    my $name = $field->{name};
    my $validator = $field->{validator};
    my $capture_key = $field->{capture};
    
    my @nodes = $xc->findnodes($xpath);
    
    if (!@nodes) {
      my $error_msg = "${name} not present";
      $logger->logError("${fileforlog}${error_msg}");
      push @$error_messages, $error_msg if $error_messages;
      $errors++;
      next;
    }
    
    # For single-value fields (header/summary), check just the first node
    # For multi-value fields (item details), check all nodes
    my $is_multi_value = $xpath =~ /ItemDetail/;
    my @nodes_to_check = $is_multi_value ? @nodes : ($nodes[0]);
    
    foreach my $node (@nodes_to_check) {
      my $val = $node->textContent // '';
      
      if ($val eq "") {
        my $error_msg = "${name} not present";
        $logger->logError("${fileforlog}${error_msg}");
        push @$error_messages, $error_msg if $error_messages;
        $errors++;
        next;
      }
      
      # Log first occurrence
      if ($node == $nodes_to_check[0]) {
        $logger->log("${name}: $val");
      }
      
      # Capture value if requested
      if ($capture_key) {
        $captures->{$capture_key} = $val;
      }
      
      # Run custom validator if provided
      if ($validator) {
        my $validation_result = $validator->($val, $node, $fileforlog, $logger, $error_messages);
        $errors += $validation_result if defined $validation_result;
      }
    }
  }
  
  return $errors;
}

sub validate_seller {
  my ($val, $node, $fileforlog, $logger, $error_messages) = @_;
  
  my $valid = $val eq 'Kirjavälitys Oy' || $val eq 'Booky.fi Oy' || $val eq 'BTJ Finland Oy';
  
  if (!$valid) {
    my $error_msg = "SellerParty PartyName Nameline '$val' is unknown.";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  return 0;
}

sub validate_vendor {
  my ($captures, $fileforlog, $logger, $error_messages) = @_;
  
  my $vendoridentifier = $captures->{vendor};
  my $buyeridentifier = $captures->{buyer};
  
  my ($san, $qualifier) = ($vendoridentifier, 91);
  
  if (!$san) {
    $san = $buyeridentifier;
    $qualifier = 92;
  }
  
  if (!$san) {
    my $error_msg = "No vendor in shipment notice.";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  my $dbh = C4::Context->dbh;
  my $stmnt = $dbh->prepare(
    "SELECT vendor_id FROM vendor_edi_accounts 
     WHERE san = ? AND id_code_qualifier=? AND transport='FILE' AND orders_enabled='1'"
  );
  
  if (!$stmnt->execute($san, $qualifier)) {
    my $error_msg = "Database error checking vendor: $DBI::errstr";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  my $bookseller = $stmnt->fetchrow_array();
  
  if (!$bookseller) {
    my $error_msg = "No vendor for SAN $san (qualifier $qualifier) in vendor_edi_accounts.";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  return 0;
}

sub validate_fund {
  my ($val, $node, $fileforlog, $logger, $error_messages) = @_;
  
  my $dbh = C4::Context->dbh;
  my $stmnt = $dbh->prepare("SELECT budget_code FROM aqbudgets WHERE budget_code = ?");
  
  if (!$stmnt->execute($val)) {
    my $error_msg = "Database error checking fund: $DBI::errstr";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  my $budget_id = $stmnt->fetchrow_array();
  
  if (!$budget_id) {
    my $error_msg = "No matching FundNumber found: $val";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  return 0;
}

sub validate_message_type {
  my ($val, $node, $fileforlog, $logger, $error_messages) = @_;
  my $errors = 0;
  
  if ($val ne "04" && $val ne "01") {
    my $error_msg = "Wrong type of MessageType found: $val";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  if ($val eq "01") {
    $logger->log("MessageType 01 found, passing xml test");
    return 0;
  }
  
  # MessageType 04 - validate embedded MARCXML
  $logger->log("MessageType 04 present, testing xml");
  
  my $parent = $node->parentNode;
  my @messageLineNodes = $parent->findnodes('MessageLine');
  
  if (!@messageLineNodes) {
    my $error_msg = "MessageLine not present";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  my $xml = $messageLineNodes[0]->textContent;
  
  if ($xml eq "") {
    my $error_msg = "MessageLine not present";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  }
  
  try {
    my $marcxml = MARC::Record->new_from_xml($xml, 'UTF-8');
    my $test = $marcxml->subfield('245', 'a');
    $logger->log("MessageLine marcxml 245a: $test");
  } catch {
    my $error_msg = "MessageLine marcxml $_";
    $logger->logError("${fileforlog}${error_msg}");
    push @$error_messages, $error_msg if $error_messages;
    return 1;
  };
  
  return 0;
}

1;
