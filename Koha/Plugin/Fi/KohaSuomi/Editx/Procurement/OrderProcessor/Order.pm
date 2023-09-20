#!/usr/bin/perl
package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor::Order;

use Moose;
use C4::Context;
use C4::Acquisition;
use Data::Dumper;

sub createOrder {
    my $self = shift;
    my ($copyDetail, $itemDetail, $order, $biblio, $basketNumber, $basketName) = @_;
    my $price = $itemDetail->getPriceFixedRPExcludingTax();
    my $tax_price = $itemDetail->getPriceFixedRPExcludingTax();
    my $budgetId = $self->getBudgetId($copyDetail->getFundNumber());
    
    my $orderinfo;

        $order = Koha::Acquisition::Order->new(
            {
                basketno           => $basketNumber,
                biblionumber       => $biblio,
                title              => $itemDetail->getTitle(),
                quantity           => $copyDetail->getCopyQuantity(),
                order_vendornote   => $order->getFileName(),
                order_internalnote => $basketName,     
                rrp                => $price,
                rrp_tax_excluded   => $price,
                rrp_tax_included   => $price,
                ecost              => $price,
                ecost_tax_excluded => $price,
                ecost_tax_included => $price,
                replacementprice   => $price,
                unitprice          => $price,
                unitprice_tax_excluded => $price,
                unitprice_tax_included => $price,
                listprice          => $price,
                budget_id          => $budgetId,
                currency           => $itemDetail->getPriceSRPECurrency(),
                orderstatus => 'new'
            }
        )->store;

    return $order->ordernumber;
}

sub createOrderItem
{
   my $self = shift;
   my $itemnumber = shift;
   my $ordernumber = shift;

   my $order = Koha::Acquisition::Orders->find({ ordernumber => $ordernumber });
   $order->add_item( $itemnumber );
}

sub getBudgetId {
   my $self = shift;
   my $fundNumber = $_[0];
   my $dbh = C4::Context->dbh;

   my $stmnt = $dbh->prepare("SELECT max(budget_id) FROM aqbudgets WHERE budget_code = ?");
   $stmnt->execute($fundNumber);
   my $budgetId = $stmnt->fetchrow_array();
   $stmnt->finish();

   return $budgetId;
}


1;
