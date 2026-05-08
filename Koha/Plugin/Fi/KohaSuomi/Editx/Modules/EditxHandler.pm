package Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler;
use Modern::Perl;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use XML::LibXML;
use Data::Dumper;



sub new {
    my ($class, $xml_doc) = @_;
    my $self = {
        data => {
            xml_doc => $xml_doc, # Tallenna XML-dokumentti
        },
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

    my ($ship_notice_number) = $xml_doc->findnodes('//ShipNoticeNumber');
    return $ship_notice_number;        
}

sub id {
    my $self = shift;
    return $self->{id} // 'undefined';
}

1;