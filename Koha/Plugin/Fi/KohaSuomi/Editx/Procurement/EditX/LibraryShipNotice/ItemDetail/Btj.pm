#!/usr/bin/perl
package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::LibraryShipNotice::ItemDetail::Btj;

use Modern::Perl;
use Moose;

extends "Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::LibraryShipNotice::ItemDetail";

sub BUILD {
    my $self = shift;
    $self->setItemObjectName('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::LibraryShipNotice::ItemDetail::CopyDetail::Btj');
}

sub getNotes {
     return 'BtjScr12';
}

1;
