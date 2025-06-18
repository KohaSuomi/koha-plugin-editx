package Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;


use Modern::Perl;
use XML::LibXML;
use Koha::Plugin::Fi::KohaSuomi::Editx;
use Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler;
use C4::Context;
use Scalar::Util qw(blessed);


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
    my ($self, $data) = @_;
    my $dbh = $self->dbh;
    my $table = $self->editx;   
    my $ship_notice_value = $data->{ship_notice_number};
    my $xml_doc = $data->{xml_doc};
    # Insert the data into the database
    my $sql = "INSERT INTO $table ( name, content ) VALUES (?, ?)";
    my $sth = $dbh->prepare($sql);
    $sth->execute($ship_notice_value, $xml_doc);

    return { status => 201, message => "Data saved successfully"};
}



sub read {
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
    my $self = shift;
    my $table = $self->editx;

    my $dbh = C4::Context->dbh;
    my $query = "SELECT * FROM $table ";
    my $sth = $dbh->prepare($query);
    $sth->execute();

    return $sth->fetchall_arrayref({});


}


sub update_status {
    my ($self, $id, $status) = @_;
    my $table = $self->editx;
    my $dbh = $self->dbh;


    my $sql = "UPDATE $table SET status = ? WHERE id = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($status, $id);

    return $sth->rows > 0;
}


sub get_pending_contents {
    my $self = shift;

    my $dbh = $self->dbh;
    my $query = "SELECT * FROM content WHERE status = 'pending'";
    my $sth =  $dbh->prepare($query);
    $sth->execute();

    my @orders;
    while (my $row = $sth->fetchrow_hashref) {
        push @orders, Koha::Plugin::Fi::KohaSuomi::Editx::Modules::EditxHandler->new($row);
    }
    return \@orders;
}

1;