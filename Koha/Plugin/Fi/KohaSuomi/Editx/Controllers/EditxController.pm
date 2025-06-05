package Koha::Plugin::Fi::KohaSuomi::Editx::Controllers::EditxController;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Data::Dumper;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use C4::Context;




sub add {
    my $c = shift->openapi->valid_input or return;
    

    my $req  = $c->req->json;
    warn Data::Dumper::Dumper($req);
    try {
        my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();
        my $result = $db->create($req);
        return $c->render(status => 201, openapi => {message => "Data saved  successfully"});
    } catch {
        my $error = $_;
        warn Data::Dumper::Dumper($error);
        return $c->render(status => 500, openapi => {error => "Failed to save data"});
    }
}

1;