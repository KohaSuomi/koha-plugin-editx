#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 4;
use LWP::UserAgent;
use HTTP::Request;
use Koha::Database;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

=head1 NAME
t::send_xml - Test suite for sending XML files to the Editx API
=head1 DESCRIPTION
This test suite verifies the functionality of sending XML files to the Editx API in Koha.
It includes tests for valid and invalid XML files, updating Editx content, and retrieving Editx contents.
=head1 EXAMPLE
To run the tests, execute the following command:
perl t/send_xml.t or prove t/send_xml.t
=cut

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
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });

    # Get the patron's userid
    my $userid    = $patron->userid;

    # Get XML body
    my $xml_file = 'data/valid_shipnotice.xml';
    open my $fh, '<', $xml_file or die "Cannot open $xml_file: $!";
    local $/;
    my $xml_body = <$fh>;
    close $fh;

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
    # Attempt to access the API with wrong permissions
    # Attempt to access the API with no permissions
    # Attempt to access the API with wrong username/password
    # Try all endpoints with invalid credentials
};

subtest 'POST invalid XML file' => sub {
    # Attempt to post an invalid XML file
};

subtest 'PUT update Editx content' => sub {
    # Attempt to update the status of an Editx content
    # Create a test Editx content first to database
    # Test the update with valid status
    # Test the update with invalid status
    # Test the update with non-existing ID
};

subtest 'GET all Editx contents' => sub {
    # Attempt to retrieve all Editx contents
    # Create a test Editx content first to database
};