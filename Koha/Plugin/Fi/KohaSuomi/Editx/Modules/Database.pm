package Koha::Plugin::Fi::KohaSuomi::Editx::Modules::Database;


use Modern::Perl;
use Koha::Plugin::Fi::KohaSuomi::Editx;
use C4::Context;
use Scalar::Util qw(blessed);







sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{_params} = $params;
    bless($self, $class);
    return $self;
}


sub editx {
    my ($self) = @_;
    return $self ->plugin->get_qualified_table_name('editx');
}

sub dbh {
    my ($self) = @_;
    return C4::Context->dbh;
}



sub create {
    my ($self, $data) = @_;
    my $dbh = $self->dbh;
    my $table = $self->editx;

    my $sql = "INSERT INTO $table (content, status ) VALUES (?, ?)";
    my $sth = $dbh->prepare($sql);
    $sth->execute($data->{content}, $data->{status});

    return $dbh->last_insert_id(undef, undef, $table, undef);
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

1;