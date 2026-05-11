package Koha::Plugin::Fi::KohaSuomi::Editx;
## It's good practice to use Modern::Perl
use Modern::Perl;
## Required for all plugins
use base qw(Koha::Plugins::Base);
## We will also need to include any Koha libraries we want to access
use C4::Context;
use Koha::DateUtils qw(dt_from_string);
use Text::CSV_XS;
use utf8;
## Here we set our plugin version
our $VERSION = "1.0.4";
## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'EDItX-plugin',
    author          => 'Lari Strand',
    date_authored   => '2022-04-05',
    date_updated    => '2025-10-16',
    minimum_version => '21.05',
    maximum_version => '',
    version         => $VERSION,
    description     => 'Adds EDItX functionality to Koha. (Paikalliskannat)',
};


## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;
    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual 
    my $self = $class->SUPER::new($args);
    return $self;
}

sub admin {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'}; 
    my $template = $self->get_template( { file => 'admin_editx.tt' } );
    print $cgi->header(-charset    => 'utf-8');
    print $template->output();
}


## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;
    $self->create_editx_contents_table();
    $self->create_map_productform();
    $self->create_aqbudgets_spend_log();
    $self->sql_insert_data();
    my $dbh = C4::Context->dbh;
    $dbh->do("INSERT IGNORE INTO plugin_data (plugin_class, plugin_key, plugin_value) VALUES ('Koha::Plugin::Fi::KohaSuomi::Editx', 'next_barcode', '1');");
    return 1;
}
## This is the 'upgrade' method. It will be triggered when a newer version of a
## plugin is installed over an existing older version of a plugin
sub upgrade {
    my ( $self, $args ) = @_;
    my $dbh = C4::Context->dbh;
    $self->create_editx_contents_table();
    $self->create_map_productform();
    $self->create_aqbudgets_spend_log();
    $dbh->do("INSERT IGNORE INTO plugin_data (plugin_class, plugin_key, plugin_value) VALUES ('Koha::Plugin::Fi::KohaSuomi::Editx', 'next_barcode', '1');");
    return 1;
}
## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->do("DELETE FROM plugin_data WHERE plugin_class='Koha::Plugin::Fi::KohaSuomi::Editx' AND plugin_key='next_barcode';");
    return 1;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my @messages;
    my $saved;

    if ( $cgi->request_method eq 'POST' && $cgi->param('save') ) {
        my $mapping_csv = $cgi->param('mapping_csv') // '';
        my ( $rows, $parse_messages, $has_blocking_errors ) = $self->_parse_productform_mapping_csv($mapping_csv);
        push @messages, @$parse_messages;

        if ($has_blocking_errors) {
            $self->_output_configure_page(
                mapping_csv    => $mapping_csv,
                messages       => \@messages,
                saved          => 0,
            );
            return;
        }

        my $save_messages = $self->_save_productform_mappings($rows);
        push @messages, @$save_messages;
        if (@$save_messages) {
            $self->_output_configure_page(
                mapping_csv => $mapping_csv,
                messages    => \@messages,
                saved       => 0,
            );
            return;
        }
        $saved = 1;
    }

    $self->_output_configure_page(
        mapping_csv => $self->_productform_mapping_csv(),
        messages    => \@messages,
        saved       => $saved,
    );
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_dir = $self->mbf_dir();
    my $spec_file = $spec_dir . '/openapi.yaml';

    my $schema = JSON::Validator::Schema::OpenAPIv2->new;
    $schema->resolve( $spec_file );
    return $schema->bundle->data;
}

sub api_namespace {
    my ( $self ) = @_;
    
    return 'kohasuomi';
}


sub create_editx_contents_table {
    my ( $self ) = @_;

    my $dbh = C4::Context->dbh;
    my $editxTable = $self->get_qualified_table_name('contents');

    $dbh->do("CREATE TABLE IF NOT EXISTS `$editxTable` (
    `id` int NOT NULL AUTO_INCREMENT,
    `name` varchar(255) NOT NULL,
    `content` longtext NOT NULL,
    `status` ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    `statusmessage` varchar(255) DEFAULT NULL,
    `transfer_time` datetime DEFAULT NULL,
    `timestamp` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ");
}

sub create_map_productform {
    my ( $self ) = @_;
    my $dbh = C4::Context->dbh;
    my $map_productform_table = 'map_productform';
    $dbh->do("CREATE TABLE IF NOT EXISTS `$map_productform_table` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `onix_code` varchar(2) DEFAULT NULL,
            `productform` varchar(10) DEFAULT NULL,
            `productform_alternative` varchar(10) DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ");
};

sub create_aqbudgets_spend_log {
    my ( $self ) = @_;
    my $dbh = C4::Context->dbh;
    my $aqbudgets_spend_log_table = 'aqbudgets_spend_log';
    $dbh->do("CREATE TABLE IF NOT EXISTS `$aqbudgets_spend_log_table` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `monetary_amount` decimal(18,2) NOT NULL,
        `timestamp` datetime DEFAULT NULL,
        `origin` varchar(100) DEFAULT NULL,
        `fund` varchar(45) DEFAULT NULL,
        `account` varchar(100) DEFAULT NULL,
        `itemtype` varchar(45) DEFAULT NULL,
        `copy_quantity` int(11) DEFAULT NULL,
        `total_amount` decimal(18,2) DEFAULT NULL,
        `location` varchar(45) DEFAULT NULL,
        `collection` varchar(20) DEFAULT NULL,
        `biblionumber` int(11) DEFAULT NULL,
        PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ");
};

sub _output_configure_page {
    my ( $self, %params ) = @_;

    my $template = $self->get_template( { file => 'configure.tt' } );
    $template->param(
        mapping_csv    => $params{mapping_csv},
        messages       => $params{messages},
        saved          => $params{saved},
        itemtypes_text => join( ', ', @{ $self->_itemtypes() } ),
        last_upgraded  => $self->retrieve_data('last_upgraded'),
    );

    return $self->output_html( $template->output() );
}

sub _parse_productform_mapping_csv {
    my ( $self, $mapping_csv ) = @_;

    my $csv = Text::CSV_XS->new(
        {
            binary           => 1,
            allow_whitespace => 1,
            blank_is_undef   => 1,
        }
    );
    my %itemtypes = map { $_ => 1 } @{ $self->_itemtypes() };
    my ( @rows, @messages, %seen_onix_codes );
    my $has_blocking_errors;
    my $line_number = 0;

    open my $fh, '<', \$mapping_csv or die "Cannot read product form mapping CSV: $!";

    while ( my $fields = $csv->getline($fh) ) {
        $line_number++;
        next unless grep { defined $_ && $_ ne '' } @$fields;
        next if $line_number == 1 && $self->_is_productform_mapping_csv_header($fields);

        if ( @$fields != 3 ) {
            push @messages, $self->_configure_message( error => "Line $line_number has " . scalar(@$fields) . " columns; expected 3." );
            $has_blocking_errors = 1;
            next;
        }

        my ( $onix_code, $productform, $productform_alternative ) = map { $self->_trim_csv_value($_) } @$fields;

        unless ($onix_code) {
            push @messages, $self->_configure_message( error => "Line $line_number has no ONIX code." );
            $has_blocking_errors = 1;
            next;
        }

        if ( $seen_onix_codes{$onix_code}++ ) {
            push @messages, $self->_configure_message( warning => "Line $line_number repeats ONIX code '$onix_code'; the later value will win." );
        }

        if ( $productform && !$itemtypes{$productform} ) {
            push @messages, $self->_configure_message( warning => "Line $line_number: item type '$productform' does not exist; productform was stored as NULL." );
            $productform = undef;
        }

        if ( $productform_alternative && !$itemtypes{$productform_alternative} ) {
            push @messages, $self->_configure_message( warning => "Line $line_number: item type '$productform_alternative' does not exist; productform_alternative was stored as NULL." );
            $productform_alternative = undef;
        }

        push @rows,
            {
                onix_code               => $onix_code,
                productform             => $productform,
                productform_alternative => $productform_alternative,
            };
    }

    if ( !$csv->eof ) {
        my ( $code, $message, $position ) = $csv->error_diag();
        push @messages, $self->_configure_message( error => "CSV parse failed at line $line_number, position $position: $message ($code)." );
        $has_blocking_errors = 1;
    }

    close $fh;

    unless (@rows) {
        push @messages, $self->_configure_message( error => 'No product form mappings found in CSV.' );
        $has_blocking_errors = 1;
    }

    return ( \@rows, \@messages, $has_blocking_errors );
}

sub _save_productform_mappings {
    my ( $self, $rows ) = @_;

    my $dbh = C4::Context->dbh;
    my $map_productform_table = 'map_productform';
    my @messages;

    my $saved = eval {
        $dbh->begin_work;
        $dbh->do("DELETE FROM $map_productform_table") or die $dbh->errstr;

        my $sth = $dbh->prepare( "
            INSERT INTO $map_productform_table (onix_code, productform, productform_alternative)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                productform = VALUES(productform),
                productform_alternative = VALUES(productform_alternative)
        " );

        for my $row (@$rows) {
            $sth->execute( $row->{onix_code}, $row->{productform}, $row->{productform_alternative} ) or die $dbh->errstr;
        }

        $dbh->commit;
        1;
    };

    if ( !$saved ) {
        my $error = $@ || $dbh->errstr;
        eval { $dbh->rollback };
        push @messages, $self->_configure_message( error => "Could not save product form mappings: $error" );
    }

    return \@messages;
}

sub _productform_mapping_csv {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    my $map_productform_table = 'map_productform';
    my $sth = $dbh->prepare( "
        SELECT onix_code, productform, productform_alternative
        FROM $map_productform_table
        ORDER BY onix_code
    " );
    $sth->execute();

    my $csv = Text::CSV_XS->new(
        {
            binary => 1,
            eol    => "\n",
        }
    );
    my $mapping_csv = '';

    open my $fh, '>', \$mapping_csv or die "Cannot write product form mapping CSV: $!";
    $csv->print( $fh, [qw(onix_code productform productform_alternative)] );

    while ( my $row = $sth->fetchrow_hashref ) {
        $csv->print(
            $fh,
            [
                $row->{onix_code}               // '',
                $row->{productform}             // '',
                $row->{productform_alternative} // '',
            ]
        );
    }

    close $fh;

    return $mapping_csv;
}

sub _itemtypes {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare('SELECT itemtype FROM itemtypes ORDER BY itemtype');
    $sth->execute();

    my @itemtypes;
    while ( my ($itemtype) = $sth->fetchrow_array ) {
        push @itemtypes, $itemtype;
    }

    return \@itemtypes;
}

sub _is_productform_mapping_csv_header {
    my ( $self, $fields ) = @_;

    return unless @$fields == 3;

    my @header = map { lc( $self->_trim_csv_value($_) // '' ) } @$fields;
    return $header[0] eq 'onix_code'
        && $header[1] eq 'productform'
        && $header[2] eq 'productform_alternative';
}

sub _trim_csv_value {
    my ( $self, $value ) = @_;

    return unless defined $value;

    $value =~ s/\A\x{FEFF}//;
    $value =~ s/\A\s+|\s+\z//g;
    return $value eq '' || uc($value) eq 'NULL' ? undef : $value;
}

sub _configure_message {
    my ( $self, $type, $text ) = @_;

    return {
        type        => $type,
        alert_class => $type eq 'error' ? 'danger' : $type,
        text        => $text,
    };
}

sub _table_exists {
    my ( $self, $table_name ) = @_;

    my $sth = C4::Context->dbh->prepare("SHOW TABLES LIKE ?");
    $sth->execute($table_name);

    return $sth->fetchrow_array ? 1 : 0;
}

sub _quote_identifier {
    my ( $self, $identifier ) = @_;

    $identifier =~ s/`/``/g;
    return "`$identifier`";
}

1;






