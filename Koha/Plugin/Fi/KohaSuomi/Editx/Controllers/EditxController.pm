package Koha::Plugin::Fi::KohaSuomi::Editx::Controllers::EditxController;
use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator;
use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage;
use C4::Context;
use Koha::Logger;


sub add {
    ## In this method we'll handle the addition of new Editx Contents
    ## We will parse the XML, validate it, and then save it to the database
    ## If the XML is invalid, we will return an error response
    my $c = shift->openapi->valid_input or return;
    my $logger = Koha::Logger->get({ interface=> 'api' });   
    my $req  = $c->req->body;
    my $current_user = $c->stash('koha.user');
    try {
        my $edi_message = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage->new();
        my $valid_xml = $edi_message->parse_xml($req);
        my $validator = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Validator->new();
        my @errors = $validator->validateEditxContent($valid_xml);
        if (@errors) {
            $logger->error("Validation failed for Editx content: " . Data::Dumper::Dumper(\@errors) . " errors found");
            return $c->render(status => 400, openapi => {
                error => "Invalid Editx content",
                errors => \@errors
            });
        }
        $edi_message->newEdiMessage($valid_xml, $current_user->userid);
        return $c->render(status => 201, openapi => {message => "Data saved successfully"});
    }
    catch {
        my $error = $_;
        $logger->error("Failed to add Editx content: $error");
        return $c->render(status => 500, openapi => {error => "Something went wrong, check logs for details"});
    };
}

sub update {
    ## In this method we will handle the update of Editx contents
    ## We will update the status of a specific content based on the ID provided
    my $c = shift->openapi->valid_input or return;
    my $logger = Koha::Logger->get({ interface => 'api' });
    my $id = $c->validation->param('id');
    my $body = $c->req->json;
    my $status = $body->{status};
    
    try {
        my $edi_message = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EdiMessage->new();
        my $result = $edi_message->update($id, $status);

        if ($result) {
            return $c->render(status => 200, openapi => {message => "Status updated successfully"});
        } else {
            return $c->render(status => 404, openapi => {error => "Content not found"});
        }
    }
    catch {
        my $error = $_;
        $logger->error("Failed to update status for content ID $id: $error");
        return $c->render(status => 500, openapi => {error => "Something went wrong, check logs for details"});
    }
}

1;