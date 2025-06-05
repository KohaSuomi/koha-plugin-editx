#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use JSON;

my $url = 'http://127.0.0.1:8080/api/v1/contrib/kohasuomi/editx';



my $data = {
    content => "This is test content",
    status => "active"
};


my $json_data = encode_json($data);


my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(POST => $url);
$req->header('Content-Type' => 'application/json');
$req->header('Accept' => 'application/json');
$req->content($json_data);


my $res = $ua->request($req);

if ($res->is_success) {
    print "Response:\n";
    print $res->decoded_content;
} else {
    print "Error:\n";
    print $res->status_line;
}

