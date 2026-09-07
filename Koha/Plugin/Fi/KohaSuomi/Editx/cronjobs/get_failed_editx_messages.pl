#!/usr/bin/perl

use strict;
use warnings;
use Modern::Perl;
use C4::Context;
use utf8;

binmode STDOUT, ':encoding(UTF-8)';

my $dbh = C4::Context->dbh;
my $sth = $dbh->prepare(q{
    SELECT m.id, m.filename, m.transfer_date, e.date AS error_date, e.details
    FROM edifact_messages m
    LEFT JOIN edifact_errors e ON e.message_id = m.id
    WHERE m.message_type = 'EDItX'
      AND m.status = 'FAILED'
      AND COALESCE(e.date, m.transfer_date) = CURDATE()
    ORDER BY m.id DESC, e.id DESC
});
$sth->execute();

my $count = 0;
while ( my $row = $sth->fetchrow_hashref ) {
    $count++;
    print "=== Sanoma: $row->{filename} (id $row->{id}) ===\n";
    print "Tiedonsiirtopäivä: $row->{transfer_date}\n" if defined $row->{transfer_date};
    print "Virhepäivä: $row->{error_date}\n" if defined $row->{error_date};
    print "Virhe:\n$row->{details}\n" if defined $row->{details};
    print "\n";
}

exit 0;