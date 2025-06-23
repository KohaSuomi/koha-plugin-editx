package Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler;


use Modern::Perl;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use XML::LibXML;



sub new {
    my ($class, $data) = @_;
    my $self = {
        data => {
            id      => $data->{id},       # Correctly access $data as a hash reference
            xml_doc => $data->{content}, # Map 'content' to 'xml_doc'
        },
        id => $data->{id}, # Set the id field
    };
    bless($self, $class);
    return $self;
}


sub parse_xml {
    my ($self, $data) = @_;
    
    # Trim whitespace from the input data
    $data //='';
    $data =~ s/^\s+|\s+$//g;

    # Here we parse and validate the XML data
    # If the XML is invalid, we will throw an error
    my $parser = XML::LibXML->new();
    my $xml_doc;
    eval {
        $xml_doc = $parser->parse_string($data);
    };
    if ($@) {
        return {
            status => 400,
            message => "Invalid XML format "
        };
    }

    return { status => 200, xml_doc => $xml_doc };

}






sub extract_ship_notice_number {

    my ($self, $xml_doc) = @_;

    # This method extracts the ShipNoticeNumber from the XML document
    # If the ShipNoticeNumber is not found, we will throw an error

    my ($ship_notice_number) = $xml_doc ->findnodes('//ShipNoticeNumber');
    return $ship_notice_number;
        
}


sub id {
    my $self = shift;
    return $self->{id} // 'undefined';
}

sub process {

    ## This method processes the Editx content
    ## It retrieves the XML data, parses it, and updates the status in the database
    
    my ($self) = @_;

    my $xml_data = $self->{data}->{xml_doc};

    unless (defined $xml_data && $xml_data ne '') {
        die "XML data for order ID " . $self->id;
    }
    print "Debug: XML data for order ID " . $self->id . ":\$xml_data\n";
    

    my $parsed_result = $self->parse_xml($xml_data);
    if ($parsed_result->{status} != 200) {
        die "Error parsing XML: " . $parsed_result->{message};
    }

    my $xml_doc = $parsed_result->{xml_doc};

    my $ship_notice_number = $self->extract_ship_notice_number($xml_doc);
    unless ($ship_notice_number) {
        die "ShipNoticeNumber not found in XML data";
    }

    print "Processing order with ShipNoticeNumber: $ship_notice_number\n";

    my $db = Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database->new();
    $db->update_status($self->{data}->{id}, 'completed');

    return 1;
}

   



1;