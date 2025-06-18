#!/usr/bin/perl
use Modern::Perl;
use LWP::UserAgent;
use HTTP::Request;
use JSON;
use XML::LibXML;

my $url = 'http://127.0.0.1:8080/api/v1/contrib/kohasuomi/editx';

# Initialize UserAgent
my $ua = LWP::UserAgent->new;

# Test: POST request with valid XML
sub test_post_valid_xml {
    my $xml_body = <<'XML';
<ShipNotice>
    <ShipNoticeNumber>12345</ShipNoticeNumber>
</ShipNotice>
XML

    my $req = HTTP::Request->new(POST => $url);
    $req->header('Content-Type' => 'application/xml');
    $req->content($xml_body);

    my $response = $ua->request($req);
    if ($response->is_success) {
        say "POST valid XML test passed: " . $response->decoded_content;
    } else {
        say "POST valid XML test failed: " . $response->status_line;
    }
}

# Test: POST request with invalid XML
sub test_post_invalid_xml {
    my $xml_body = '<ShipNotice>
    <ShipNoticeNumber>12345
</ShipNotice>';

    my $req = HTTP::Request->new(POST => $url);
    $req->header('Content-Type' => 'application/xml');
    $req->content($xml_body);

    my $response = $ua->request($req);
    if ($response->code == 400) {
        say "POST invalid XML test passed: " . $response->decoded_content;
    } else {
        say "POST invalid XML test failed: " . $response->status_line;
    }
}



# Test: GET request to retrieve messages
sub test_get_messages {
    my $req = HTTP::Request->new(GET => $url);
    $req->header('Accept' => 'application/json');


    my $response = $ua->request($req);
    if ($response->is_success) {
        say "GET messages test passed: " . $response->decoded_content;
    } else {
        say "GET messages test failed: " . $response->status_line;

    }

}


sub test_put_update_status {
    my $id = 1;
    my $status = 'completed'; 

    my $req = HTTP::Request->new(PUT => "$url/$id?status=$status");
    $req->header('Content-Type' => 'application/json');

    my $response = $ua->request($req);
    if ($response->is_success) {
        say "PUT update status test passed: " . $response->decoded_content;
    } else {
        say "PUT update status test failed: " . $response->status_line;
    }
}



# Execute tests
test_post_valid_xml();
test_post_invalid_xml();
test_get_messages();
test_put_update_status();



