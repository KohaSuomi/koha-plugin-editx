package Koha::Plugin::Fi::KohaSuomi::Editx::Controllers::EditxController;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use C4::Context;


sub add {

    ## In this we will handle the addition of new Editx Contents
    ## We will parse the XML, validate it, and then save it to the database
    ## If the XML is invalid, we will return an error response
    my $c = shift->openapi->valid_input or return;
    
    my $req  = $c->req->body;
    try {
        my $handler = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler->new();
        my $valid_xml = $handler->parse_xml($req);
        if ($valid_xml->{status} != 200) {
            warn "Invalid XML: " . $valid_xml->{message};
            return $c->render(status => 400, openapi => {error => "Invalid XML format: " . $valid_xml->{message}});
        }
        my $ship_notice_number_result = $handler->extract_ship_notice_number($valid_xml->{xml_doc});
        my $ship_notice_number = $ship_notice_number_result->{ship_notice_number};
        my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();
        my $result = $db->create({ship_notice_number => $ship_notice_number, xml_doc => $valid_xml->{xml_doc}});
        return $c->render(status => 201, openapi => {message => "Data saved successfully"});
    }
    catch {
        my $error = $_;
        return $c->render(status => 500, openapi => {error => "Failed to save data"});
    };
}


sub list {

    ## In this method we will handle the retrieval of all Editx contents
    ## We will fetch all contents from the database and return them
    my $c = shift->openapi->valid_input or return;

    try {
        my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();
        my $contents = $db->get_all_contents();

        return $c->render(status => 200, openapi => $contents); 
    }
    catch {
        my $error = $_;
        return $c->render(status => 500, openapi => {error => "Failed to retrieve messages"});
    };
}


sub update {

    ## In this method we will handle the update of Editx contents
    ## We will update the status of a specific content based on the ID provided
    my $c = shift->openapi->valid_input or return;

    my $id = $c->validation->param('id');
    my $status = $c->validation->param('status');

    unless ($status =~ /^(pending|processing|completed|failed)$/) {
        return $c->render(status => 400, openapi => {error => "Invalid status value"});

    }
    try {
        my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();
        my $result = $db->update_status($id, $status);

        if ($result) {
            return $c->render(status => 200, openapi => {message => "Status updated successfully"});
        } else {
            return $c->render(status => 404, openapi => {error => "Content not found"});
        }
    }
    catch {
        my $error = $_;
        return $c->render(status => 500, openapi => {error => "Failed to update status"});
    }
}
1;