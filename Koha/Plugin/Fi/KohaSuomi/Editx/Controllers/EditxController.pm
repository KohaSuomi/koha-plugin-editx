package Koha::Plugin::Fi::KohaSuomi::Editx::Controllers::EditxController;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Data::Dumper;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use C4::Context;





sub check_authorization {
    my $c = shift;

    unless ($c->req->headers->header('x-koha-authorization') eq 'your-secret-key here') {
        return $c->render(status => 403, openapi => {error => "Unauthorized access"});
    }
}

sub add {
    
    my $c = shift->openapi->valid_input or return;
    check_authorization($c);

    my $req  = $c->req->body;
    warn Data::Dumper::Dumper($req);
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
        warn Data::Dumper::Dumper($req);
        my $result = $db->create({ship_notice_number => $ship_notice_number, xml_doc => $valid_xml->{xml_doc}});
        return $c->render(status => 201, openapi => {message => "Data saved successfully"});
    }
    catch {
        my $error = $_;
        warn Data::Dumper::Dumper($error);
        return $c->render(status => 500, openapi => {error => "Failed to save data"});
    };
}



sub list {
    
    my $c = shift->openapi->valid_input or return;
    check_authorization($c);

    try {
        my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();
        my $contents = $db->get_all_contents();

        return $c->render(status => 200, openapi => $contents); 
    }
    catch {
        my $error = $_;
        warn Data::Dumper::Dumper($error);
        return $c->render(status => 500, openapi => {error => "Failed to retrieve messages"});
    };
}


sub update {
    my $c = shift->openapi->valid_input or return;
    check_authorization($c);

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
        warn Data::Dumper::Dumper($error);
        return $c->render(status => 500, openapi => {error => "Failed to update status"});
    }



}

1;