#!/usr/bin/perl

# Self-contained tests for cronjobs/notify_failed_editx.sh. The script is run
# against stub config, database and mail helpers, so no Koha instance, database
# or mail server is needed.

use strict;
use warnings;
use utf8;

use Test::More;
use FindBin qw($Bin);
use File::Copy qw(copy move);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use MIME::Base64 qw(decode_base64);
use Encode qw(decode);

my $script = "$Bin/../cronjobs/notify_failed_editx.sh";

plan skip_all => "notify_failed_editx.sh not found at $script" unless -f $script;

my $xmllint = `command -v xmllint 2> /dev/null`;
chomp $xmllint;
plan skip_all => 'xmllint is required to run the notification test' unless $xmllint;

my $root     = tempdir( CLEANUP => 1 );
my $pending  = "$root/pending";
my $failed   = "$root/failed";
my $archived = "$root/archived";
my $logdir   = "$root/log/editx";
my $bin      = "$root/bin";
my $fail_bin = "$root/bin-fail";
my $cronjobs = "$root/cronjobs";

make_path( $pending, $failed, $archived, $logdir, $bin, $fail_bin, $cronjobs );

my $koha_conf = "$root/koha-conf.xml";
my $mail_args = "$root/mail-args.txt";
my $mail_body = "$root/mail-body.txt";
my $db_output = "$root/db-output.txt";
my $error_log = "$logdir/error.log";

sub write_text {
    my ( $path, $text ) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return;
}

sub read_text {
    my ($path) = @_;
    return unless -f $path;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

sub leftover_archive_lists {
    return [ glob("$logdir/notify_failed_editx.archive.*") ];
}

sub shell_quote {
    my ($text) = @_;
    $text =~ s/'/'\\''/g;
    return "'$text'";
}

# The script looks for its helper scripts next to itself, so it is copied to a
# temporary directory that also holds the stubs. Copy it byte for byte, the
# script itself is UTF-8 and must not be encoded again.
copy( $script, "$cronjobs/notify_failed_editx.sh" )
  or die "Cannot copy $script: $!";
chmod 0755, "$cronjobs/notify_failed_editx.sh";

write_text( "$cronjobs/exportEditXConfig.pl", <<"CONFIG" );
#!/bin/sh
printf "export mailto='test\@example.com'\\n"
printf "export mailfrom=''\\n"
printf "export tmp_path=%s\\n" @{[ shell_quote($pending) ]}
printf "export failed_path=%s\\n" @{[ shell_quote($failed) ]}
printf "export failed_archived_path=%s\\n" @{[ shell_quote($archived) ]}
printf "export log_path=%s\\n" @{[ shell_quote("$root/log") ]}
CONFIG
chmod 0755, "$cronjobs/exportEditXConfig.pl";

write_text( "$cronjobs/get_failed_editx_messages.pl", <<"DB" );
#!/bin/sh
test -f @{[ shell_quote($db_output) ]} && cat @{[ shell_quote($db_output) ]}
exit 0
DB
chmod 0755, "$cronjobs/get_failed_editx_messages.pl";

write_text( "$bin/mail", <<"MAIL" );
#!/bin/sh
printf '%s\\n' "\$@" > @{[ shell_quote($mail_args) ]}
cat > @{[ shell_quote($mail_body) ]}
MAIL
chmod 0755, "$bin/mail";

write_text( "$fail_bin/mail", <<'MAIL' );
#!/bin/sh
cat > /dev/null
exit 1
MAIL
chmod 0755, "$fail_bin/mail";

write_text( $koha_conf, "<koha-conf></koha-conf>\n" );

sub reset_mail {
    unlink $mail_args, $mail_body;
    return;
}

sub run_notify {
    my (%args) = @_;

    reset_mail();

    local $ENV{KOHA_CONF} = $koha_conf;
    local $ENV{PATH} = ( $args{failing_mail} ? $fail_bin : $bin ) . ":$ENV{PATH}";

    my $cmd = 'sh ' . shell_quote("$cronjobs/notify_failed_editx.sh");
    $cmd .= ' --verbose' if $args{verbose};
    my $redir = $args{stderr_file};
    $cmd .= ' 2>' . shell_quote($redir) if $redir;

    my $status = system($cmd);
    return $status >> 8;
}

sub mail_header_args {
    my $text = read_text($mail_args);
    return unless defined $text;
    my @lines = split /\n/, $text;
    return \@lines;
}

sub mail_subject {
    my $args = mail_header_args();
    return unless $args;
    for my $i ( 0 .. $#{$args} ) {
        return $args->[ $i + 1 ] if $args->[$i] eq '-s' && $i < $#{$args};
    }
    return;
}

sub decoded_subject {
    my $subject = mail_subject();
    return unless defined $subject;

    # RFC 2047: whitespace between adjacent encoded words is not part of the
    # text, so decode each word and join the results without the separators.
    return join q{}, map {
        m{\A=\?UTF-8\?B\?([^?]+)\?=\z}
          ? decode( 'UTF-8', decode_base64($1) )
          : $_
    } split /\s+/, $subject;
}

my $valid_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice>
  <Header>
    <ShipNoticeNumber>222</ShipNoticeNumber>
    <IssueDateTime>20261026</IssueDateTime>
  </Header>
  <ItemDetail>
    <CopyDetail>
      <DeliverToLocation>AIK</DeliverToLocation>
    </CopyDetail>
  </ItemDetail>
</LibraryShipNotice>
XML

my $pending_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice>
  <Header>
    <ShipNoticeNumber>333</ShipNoticeNumber>
    <IssueDateTime>20261026</IssueDateTime>
  </Header>
</LibraryShipNotice>
XML

my $db_message = <<'DB';
=== Sanoma: 3875642_20261012 (id 99) ===
Tiedonsiirtopäivä: 2026-10-12
Virhepäivä: 2026-10-26
Virhe:
Editx content validation failed: SubLineNumber not present

DB

my $error_line =
  "2026-10-26 12:00:00 -- Failed to process file new_failure.xml: Could not find matching vendor for file new_failure.xml\n";

my $failed_file = "$failed/new_failure.xml";

subtest 'a successful run reports the failures and archives the stopped files' => sub {

    write_text( $failed_file, $valid_xml );
    write_text( "$pending/incomplete.xml", $pending_xml );
    write_text( $db_output, $db_message );
    write_text( $error_log, $error_line );

    my $exit = run_notify();
    is( $exit, 0, 'script exits successfully' );

    my $args = mail_header_args();
    ok( $args, 'mail was called' );

    is(
        decoded_subject(),
        'EDItX tilaussanomien käsittelyssä oli ongelmia',
        'subject is sent as UTF-8 even though the mail command needs encoded words'
    );

    my $body = read_text($mail_body);
    ok( defined $body && length $body, 'mail has a body' ) || return;

    like( $body, qr/=== Sanoma: new_failure\.xml ===/, 'failed file is listed' );
    like( $body, qr/Sanoman nimi Kohassa: 222_20261026/, 'Koha name of the message is shown' );
    like( $body, qr/Failed to process file new_failure\.xml/, 'excerpt from error.log is shown' );
    like( $body, qr/SubLineNumber not present/, 'reason from the database is shown' );
    like( $body, qr/Sanoma koskee sijainteja\/tilejä: AIK/, 'affected locations are listed' );
    like(
        $body,
        qr/Raportoidut sanomat siirretään ilmoituksen lähettämisen jälkeen/,
        'body tells that the reported files are moved'
    );
    like( $body, qr/jätetty käsittelyjonoon/, 'a file waiting in the queue is still reported' );

    ok( !-e $failed_file, 'reported file is moved away from the fail directory' );
    ok( -e "$archived/new_failure.xml", 'reported file is archived' );
    ok( -e "$pending/incomplete.xml", 'queued file is left in place' );
    is( scalar @{ leftover_archive_lists() }, 0, 'temporary archive list is removed' );

    done_testing();
};

subtest 'the next run does not report the archived file again' => sub {

    my $exit = run_notify();
    is( $exit, 0, 'script exits successfully' );

    my $body = read_text($mail_body);
    ok( defined $body, 'mail is still sent for the database and queued rows' ) || return;

    unlike( $body, qr/=== Sanoma: new_failure\.xml ===/, 'archived file is not reported again' );
    like( $body, qr/SubLineNumber not present/, 'database failures are still reported' );
    like( $body, qr/jätetty käsittelyjonoon/, 'queued file is still reported' );

    done_testing();
};

subtest 'nothing to report sends no mail' => sub {

    unlink "$pending/incomplete.xml";
    write_text( $db_output, '' );

    my $exit = run_notify();
    is( $exit, 0, 'script exits successfully' );
    ok( !-e $mail_args, 'no mail is sent' );

    done_testing();
};

subtest 'a failed mail leaves the files in the fail directory' => sub {

    move( "$archived/new_failure.xml", $failed_file ) or die "Cannot move fixture: $!";

    my $exit = run_notify( failing_mail => 1 );
    isnt( $exit, 0, 'script fails when the mail cannot be sent' );

    ok( -e $failed_file, 'file is left in the fail directory for the next run' );
    ok( !-e "$archived/new_failure.xml", 'file is not archived' );
    is( scalar @{ leftover_archive_lists() }, 0, 'temporary archive list is removed' );

    done_testing();
};

subtest "verbose mode prints the message that will be sent" => sub {

    write_text( "$pending/incomplete.xml", $pending_xml );
    write_text( $db_output, $db_message );
    write_text( $error_log, $error_line );

    my $stderr_file = "$root/verbose-stderr.txt";
    unlink $stderr_file;

    my $exit = run_notify( verbose => 1, stderr_file => $stderr_file );
    is( $exit, 0, "script exits successfully" );

    my $stderr = read_text( $stderr_file );
    ok( defined $stderr, "verbose output was captured" ) || return;
    like( $stderr, qr/--- BEGIN MESSAGE ---/, "verbose output marks the beginning of the message" );
    like( $stderr, qr/Sanoman nimi Kohassa: 222_20261026/, "verbose output contains the message body" );
    like( $stderr, qr/--- END MESSAGE ---/, "verbose output marks the end of the message" );

    ok( -e "$archived/new_failure.xml", "the mail is still sent and archived" );

    done_testing();
};

done_testing();
