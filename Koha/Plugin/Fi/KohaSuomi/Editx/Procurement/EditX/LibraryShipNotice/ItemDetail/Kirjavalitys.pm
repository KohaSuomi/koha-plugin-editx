#!/usr/bin/perl
package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::LibraryShipNotice::ItemDetail::Kirjavalitys;

use Modern::Perl;
use Moose;

extends "Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::LibraryShipNotice::ItemDetail";

sub BUILD {
    my $self = shift;
    $self->setItemObjectName('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::EditX::LibraryShipNotice::ItemDetail::CopyDetail::Kirjavalitys');
}

sub getNotes {
     return 'KirjavalitysScr12';
}

sub getPriceFixedRPExcludingTax {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPExcludingTax"]/MonetaryAmount')->string_value;
}

sub getPriceFixedRPIncludingTax {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPIncludingTax"]/MonetaryAmount')->string_value;
}

sub getPriceSRPExcludingTax {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPExcludingTax"]/MonetaryAmount')->string_value;
}

sub getPriceSRPIncludingTax {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPIncludingTax"]/MonetaryAmount')->string_value;
}

sub getPriceSRPECurrency {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPExcludingTax"]/CurrencyCode')->string_value;
}

sub getPriceSRPETaxPercent {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPExcludingTax"]/Tax/Percent')->string_value;
}

sub getPriceFixedRPETaxPercent {
    my $self = shift;
    my $xmlData = $self->getXmlData();
    return $xmlData->find('PricingDetail/Price[PriceQualifierCode/text() = "FixedRPExcludingTax"]/Tax/Percent')->string_value;
}



1;
