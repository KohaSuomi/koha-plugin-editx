package Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;
use Modern::Perl;
use XML::LibXML;
use Koha::Plugin::Fi::KohaSuomi::Editx;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler;
use C4::Context;
use Scalar::Util qw(blessed);


## This is the Database module for the Editx plugin
## It handles all database operations related to Editx contents
sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{_params} = $params;
    bless($self, $class);
    return $self;
}

sub plugin {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::Editx->new();
}


sub editx {
    my ($self) = @_;
    return $self ->plugin->get_qualified_table_name('contents');
}


sub dbh {
    my ($self) = @_;
    return C4::Context->dbh;
}


sub create {
    ## This method creates a new Editx content in the database
    ## It takes a hash reference of data to insert into the Editx table
    ## It returns a hash reference with the status and message of the operation
    my ($self, $data) = @_;
    my $dbh = $self->dbh;
    my $table = $self->editx;   
    my $ship_notice_value = $data->{ship_notice_number};
    
    my $xml_doc = $data->{xml_doc};
    my $sql = "INSERT INTO $table ( name, content ) VALUES (?, ?)";
    my $sth = $dbh->prepare($sql);
    $sth->execute($ship_notice_value, $xml_doc);

    return { status => 201, message => "Data saved successfully"};
}



sub read {

    ## This method retrieves a specific Editx content by its ID
    ## It takes the content ID as a parameter and returns an array reference of hash references
    my ($self, $id) = @_;
    my $table = $self->editx;
    my $dbh = $self->dbh;
    
    my $sql = "SELECT * FROM $table WHERE id = ?";
    my $sth = $dbh->prepare($sql);

    $sth->execute($id);
    return $sth->fetchall_arrayref({})  if $sth->rows > 0;
    return [];
}


sub update {
    
    ## This method updates seelected fields in the Editx table
    ## It takes a hash reference of data to update and a hash reference of conditions to match
    ## It returns the number of rows affected by the update operation
    my ($self, $table, $data, $where) = @_;
    $table = $self->editx;
    my $dbh = $self->dbh;

    my @set_fields = keys %$data;
    my @where_fields = keys %$where;


    my $set_clause = join(", ", map { "$_ = ?" } @set_fields);
    my $where_clause = join(" AND ", map { "$_ = ?" } @where_fields);
    my $sql = "UPDATE $table SET $set_clause WHERE $where_clause";
    
    my $sth = $dbh->prepare($sql);
    $sth->execute((@{$data}{@set_fields}, @{$where}{@where_fields}));
    return $sth->rows;
}


sub delete {
   my ($self, $id) = @_;
    my $table = $self->editx;
    my $dbh = $self->dbh;
     
    my $sql = "DELETE FROM $table WHERE id = ?";
    my $sth = $dbh->prepare($sql);

     $sth = $dbh->prepare($sql);
    $sth->execute($id);
    return $sth->rows;
}


sub get_all_contents {
    ## This method retrieves all Editx contents from the database
    ## It returns an array reference of hash references, each representing a content
    my $self = shift;
    my $table = $self->editx;
    my $dbh = C4::Context->dbh;
    my $query = "SELECT * FROM $table ";
    my $sth = $dbh->prepare($query);
    $sth->execute();

    return $sth->fetchall_arrayref({});
}


sub update_status {
    ## This method updates the status of a specific Editx content
    ## It takes the content ID and the new status as parameters
    my ($self, $id, $status) = @_;
    my $table = $self->editx;
    my $dbh = $self->dbh;

    my $sql = "UPDATE $table SET status = ? WHERE id = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($status, $id);

    return $sth->rows > 0;
}


sub get_pending_contents {
    ## This method retrieves all pending Editx contents from the database
    ## It returns an array reference of EditxHandler objects for each pending content
    ## This is useful for processing pending contents
    my $self = shift;
    my $table = $self->editx;
    my $dbh = $self->dbh;
    my $query = "SELECT id, content FROM $table WHERE status = 'pending'";
    my $sth =  $dbh->prepare($query);
    $sth->execute();

    my @orders;
    while (my $row = $sth->fetchrow_hashref) {
        push @orders, Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler->new($row);
    }
    return \@orders;
}



sub mark_order_as_completed {
    ## This method marks a specific Editx content as completed
    ## It takes the content ID as a parameter
    my ($self, $id) = @_;
    return $self->update_status($id, 'completed');
}


sub mark_order_as_failed {
    ## This method marks a specific Editx content as failed
    ## It takes the content ID as a parameter
    my ($self, $id) = @_;
    return $self->update_status($id, 'failed');
}
1;