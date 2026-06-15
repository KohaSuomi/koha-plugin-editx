package Koha::Plugin::Fi::KohaSuomi::Editx;
## It's good practice to use Modern::Perl
use Modern::Perl;
## Required for all plugins
use base qw(Koha::Plugins::Base);
## We will also need to include any Koha libraries we want to access
use File::Spec;
use File::Temp qw(tempfile);
use C4::Context;
use Koha::DateUtils qw(dt_from_string);
use Koha::Token;
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(url_escape);
use Text::CSV_XS;
use utf8;
## Here we set our plugin version
our $VERSION = "2.0.0";
## Here is our metadata, some keys are required, some are optional
our $metadata = {
    author          => 'Lari Strand',
    date_authored   => '2022-04-05',
    date_updated    => '2026-05-21',
    minimum_version => '21.05',
    maximum_version => '',
    version         => $VERSION
};

sub get_localized_metadata {
    my ($self) = @_;
    my $lang = C4::Languages::getlanguage() || 'en';
    my ($name, $description);

    if ( $lang eq 'sv-SE' ) {
        $name = "EDItX-plugin";
        $description = "Lägger till EDItX-funktionalitet i Koha. (Lokala databaser)";
    } elsif ( $lang eq 'fi-FI' ) {
        $name = "EDItX-plugin";
        $description = "Lisää EDItX-toiminnallisuuden Kohaan. (Paikalliskannat)";
    } else {
        $name = "EDItX-plugin";
        $description = "Adds EDItX functionality to Koha. (Local databases)";
    }
    return ($name, $description);
}

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

    my ($name, $description) = $self->get_localized_metadata();
    $self->{'metadata'}->{'name'} = $name;
    $self->{'metadata'}->{'description'} = $description;

    return $self;
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;
    $self->drop_editx_contents_table();
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
    $self->drop_editx_contents_table();
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

sub intranet_js {
    my ( $self ) = @_;
    my $pluginpath = $self->get_plugin_http_path();
    return '<script src="' . $pluginpath . '/js/editxButton.js"></script>';
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my @messages;
    my $saved;
    my $procurement_settings =
          $cgi->request_method eq 'POST'
        ? $self->_procurement_settings_from_cgi($cgi)
        : $self->_procurement_settings();

    if ( $cgi->request_method eq 'POST' && $cgi->param('save') ) {
        my $mapping_csv = $cgi->param('mapping_csv') // '';
        if ( !$self->_csrf_token_valid($cgi) ) {
            push @messages, $self->_configure_message( error => 'Configuration was not saved because the security token was invalid. Reload the page and try again.' );
            $self->_output_configure_page(
                mapping_csv            => $mapping_csv,
                procurement_settings   => $procurement_settings,
                messages               => \@messages,
                saved                  => 0,
            );
            return;
        }

        my ( $rows, $parse_messages, $has_blocking_errors ) = $self->_parse_productform_mapping_csv($mapping_csv);
        my ( $procurement_messages, $has_procurement_blocking_errors ) = $self->_validate_procurement_settings( $procurement_settings, 0 );
        push @messages, @$procurement_messages;
        $has_blocking_errors ||= $has_procurement_blocking_errors;

        if ($has_blocking_errors) {
            $self->_output_configure_page(
                mapping_csv            => $mapping_csv,
                procurement_settings   => $procurement_settings,
                messages               => \@messages,
                saved                  => 0,
            );
            return;
        }

        my $save_messages = $self->_save_productform_mappings($rows);
        push @messages, @$save_messages;
        if (@$save_messages) {
            $self->_output_configure_page(
                mapping_csv            => $mapping_csv,
                procurement_settings   => $procurement_settings,
                messages               => \@messages,
                saved                  => 0,
            );
            return;
        }
        $self->store_data(
            {
                %{ $self->_procurement_settings_store_data($procurement_settings) },
                last_configured_by   => ( C4::Context->userenv || {} )->{'number'},
            }
        );
        $saved = 1;
    }

    $self->_output_configure_page(
        mapping_csv            => $self->_productform_mapping_csv(),
        procurement_settings   => $procurement_settings,
        messages               => \@messages,
        saved                  => $saved,
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


sub drop_editx_contents_table {
    my ( $self ) = @_;

    my $dbh = C4::Context->dbh;
    my $editxTable = $self->get_qualified_table_name('contents');

    $dbh->do("DROP TABLE IF EXISTS `$editxTable`");
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
        mapping_csv            => $params{mapping_csv},
        procurement_settings   => $params{procurement_settings},
        messages               => $params{messages},
        saved                  => $params{saved},
        itemtypes_text         => join( ', ', @{ $self->_itemtypes() } ),
        locations_text         => join( ', ', @{ $self->_authorised_values('LOC') } ),
        branches_text          => join( ', ', @{ $self->_branches() } ),
        plugin_display_version => $self->plugin_display_version(),
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

sub _procurement_settings_from_cgi {
    my ( $self, $cgi ) = @_;

    my %settings = map {
        my $value = $self->_trim_csv_value( scalar $cgi->param($_) );
        $_ => $value // ''
    } qw(
        import_tmp_path import_load_path import_archive_path import_failed_path import_failed_archived_path
        authoriser allowed_locations productform_alternative_triggers notification_mailto notification_mailfrom
    );

    $settings{automatch_biblios}       = $cgi->param('automatch_biblios')       ? 'yes' : 'no';
    $settings{use_finna_materialtype} = $cgi->param('use_finna_materialtype') ? 'yes' : 'no';

    return \%settings;
}

sub _procurement_settings {
    my ($self) = @_;

    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
    my $config = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new->getSettings();
    my $settings = $config->{settings} || {};
    my $notifications = $config->{notifications} || {};

    return {
        import_tmp_path                  => $self->_config_scalar( $settings->{import_tmp_path} ),
        import_load_path                 => $self->_config_scalar( $settings->{import_load_path} ),
        import_archive_path              => $self->_config_scalar( $settings->{import_archive_path} ),
        import_failed_path               => $self->_config_scalar( $settings->{import_failed_path} ),
        import_failed_archived_path      => $self->_config_scalar( $settings->{import_failed_archived_path} ),
        authoriser                       => $self->_config_scalar( $settings->{authoriser} ),
        allowed_locations                => $self->_config_scalar( $settings->{allowed_locations} ),
        productform_alternative_triggers => $self->_config_scalar( $settings->{productform_alternative_triggers} ),
        automatch_biblios                => $self->_yes_no_setting( $settings->{automatch_biblios}, 'yes' ),
        use_finna_materialtype           => $self->_yes_no_setting( $settings->{use_finna_materialtype}, 'no' ),
        notification_mailto              => $self->_config_scalar( $notifications->{mailto} ),
        notification_mailfrom            => $self->_config_scalar( $notifications->{mailfrom} ),
    };
}

sub _procurement_settings_store_data {
    my ( $self, $settings ) = @_;

    my %data;
    for my $key (qw(
        authoriser allowed_locations productform_alternative_triggers automatch_biblios use_finna_materialtype
        notification_mailto notification_mailfrom
    )) {
        $data{"procurement_$key"} = $settings->{$key} // '';
    }

    return \%data;
}

sub _validate_procurement_settings {
    my ( $self, $settings, $strict ) = @_;

    my @messages;
    my $has_blocking_errors;
    my $blocking_type = $strict ? 'error' : 'warning';

    for my $field (qw(authoriser allowed_locations)) {
        next if defined $settings->{$field} && $settings->{$field} ne '';
        push @messages, $self->_configure_message( $blocking_type => "$field is required before EDItX import can run." );
        $has_blocking_errors ||= $strict;
    }

    if ( defined $settings->{authoriser} && $settings->{authoriser} ne '' ) {
        if ( $settings->{authoriser} !~ /\A[0-9]+\z/ || !$self->_patron_exists( $settings->{authoriser} ) ) {
            push @messages, $self->_configure_message( $blocking_type => "authoriser must be an existing Koha borrowernumber." );
            $has_blocking_errors ||= $strict;
        }
    }

    my @allowed_locations = $self->_csv_values( $settings->{allowed_locations} );
    my %allowed_locations = map { $_ => 1 } @allowed_locations;
    my %known_locations = map { $_ => 1 } @{ $self->_authorised_values('LOC') };

    if (%known_locations) {
        for my $location (@allowed_locations) {
            next if $known_locations{$location};
            push @messages, $self->_configure_message( $blocking_type => "allowed_locations contains unknown Koha location '$location'." );
            $has_blocking_errors ||= $strict;
        }
    }

    for my $trigger ( $self->_csv_values( $settings->{productform_alternative_triggers} ) ) {
        if ( !%allowed_locations || !$allowed_locations{$trigger} ) {
            push @messages, $self->_configure_message( $blocking_type => "productform_alternative_triggers contains '$trigger', but it is not in allowed_locations." );
            $has_blocking_errors ||= $strict;
        }
        if ( %known_locations && !$known_locations{$trigger} ) {
            push @messages, $self->_configure_message( $blocking_type => "productform_alternative_triggers contains unknown Koha location '$trigger'." );
            $has_blocking_errors ||= $strict;
        }
    }

    for my $email ( $self->_csv_values( $settings->{notification_mailto} ) ) {
        next if $email =~ /\A[^@\s]+@[^@\s]+\z/;
        push @messages, $self->_configure_message( $blocking_type => "Notification recipient '$email' is not a valid simple email address." );
        $has_blocking_errors ||= $strict;
    }

    if ( $settings->{notification_mailfrom} && $settings->{notification_mailfrom} !~ /\A[^@\s]+@[^@\s]+\z/ ) {
        push @messages, $self->_configure_message( $blocking_type => "Notification sender '$settings->{notification_mailfrom}' is not a valid simple email address." );
        $has_blocking_errors ||= $strict;
    }

    return ( \@messages, $has_blocking_errors );
}

sub _default_import_tmp_path {
    my ($self) = @_;

    require Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config;
    my $settings = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Config->new->getSettings();

    return $settings->{settings}->{import_tmp_path} // '';
}

sub _shell_quote {
    my ( $self, $value ) = @_;

    $value //= '';
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub _config_scalar {
    my ( $self, $value ) = @_;

    return '' if !defined $value || ref $value;
    return $value;
}

sub _yes_no_setting {
    my ( $self, $value, $default ) = @_;

    $value = $self->_config_scalar($value);
    return $value eq 'yes' || $value eq 'no' ? $value : $default;
}

sub _csv_values {
    my ( $self, $csv_text ) = @_;

    return grep { $_ ne '' } map {
        my $value = $_;
        $value =~ s/\A\s+|\s+\z//g;
        $value;
    } split ',', ( $csv_text // '' );
}

sub _patron_exists {
    my ( $self, $borrowernumber ) = @_;

    return unless defined $borrowernumber && $borrowernumber =~ /\A[0-9]+\z/;

    my ($exists) = C4::Context->dbh->selectrow_array( 'SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ?', undef, $borrowernumber );
    return $exists ? 1 : 0;
}

sub _authorised_values {
    my ( $self, $category ) = @_;

    my $sth = C4::Context->dbh->prepare('SELECT authorised_value FROM authorised_values WHERE category = ? ORDER BY authorised_value');
    $sth->execute($category);

    my @values;
    while ( my ($value) = $sth->fetchrow_array ) {
        push @values, $value;
    }

    return \@values;
}

sub _branches {
    my ($self) = @_;

    my $sth = C4::Context->dbh->prepare('SELECT branchcode FROM branches ORDER BY branchcode');
    $sth->execute();

    my @branches;
    while ( my ($branchcode) = $sth->fetchrow_array ) {
        push @branches, $branchcode;
    }

    return \@branches;
}

sub _csrf_token_valid {
    my ( $self, $cgi ) = @_;

    return unless $cgi;

    return Koha::Token->new->check_csrf(
        {
            session_id => scalar $cgi->cookie('CGISESSID'),
            token      => scalar $cgi->param('csrf_token'),
        }
    );
}

sub _static_asset_version {
    my ( $self, $path ) = @_;

    my $version = $self->plugin_version();
    $version =~ s/[^A-Za-z0-9_.-]+/_/g;

    my @parts = ($version);
    if ( my $bundle_path = $self->bundle_path ) {
        my $full_path = File::Spec->catfile( $bundle_path, split m{/}, $path );
        if ( my @stat = stat $full_path ) {
            push @parts, $stat[9], $stat[7];
        }
    }

    return join '-', @parts;
}

sub plugin_version {
    my ($self) = @_;

    return $metadata->{version} || $VERSION;
}

sub plugin_display_version {
    my ($self) = @_;

    return $self->plugin_version();
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






