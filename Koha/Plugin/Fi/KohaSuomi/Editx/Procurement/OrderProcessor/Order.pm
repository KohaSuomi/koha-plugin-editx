#!/usr/bin/perl
package Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::OrderProcessor::Order;

use Moose;
use C4::Context;
use C4::Acquisition;
use Data::Dumper;

use Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger;

has 'logger' => (
    is      => 'rw',
    isa => 'Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger',
    reader => 'getLogger',
    writer => 'setLogger'
);

sub BUILD {
    my $self = shift;
    $self->setLogger(new Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger)
        unless $self->getLogger();
}

sub createOrder {
    my $self = shift;
    my ($copyDetail, $itemDetail, $order, $biblio, $basketNumber, $authoriser) = @_;
    my $price = $itemDetail->getPriceFixedRPExcludingTax();
    my $tax_price = $itemDetail->getPriceFixedRPExcludingTax();
    my $budgetId = $self->getBudgetId($copyDetail->getFundNumber());
    unless ($budgetId) {
        if (my $logger = $self->getLogger()) {
            $logger->logError("Budget ID not found for fund number: " . $copyDetail->getFundNumber());
        }
        die "Budget ID not found for fund number: " . $copyDetail->getFundNumber()."\n";
    }
        $order = Koha::Acquisition::Order->new(
            {
                basketno           => $basketNumber,
                biblionumber       => $biblio,
                title              => $itemDetail->getTitle(),
                quantity           => $copyDetail->getCopyQuantity(),
                order_vendornote   => $order->getFileName(),
                order_internalnote => $itemDetail->getReferenceNumber(),  
                created_by         => $authoriser,    
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

sub getOrderProgress {
   my $self = shift;
   my $reference = $_[0];
   my $fileName  = $_[1];

   return { orders => 0, items => 0 } if !$reference || !$fileName;

   my $dbh = C4::Context->dbh;

   # An order row is written before its items, so the order alone does not
   # prove the line was written completely: compare the linked items with the
   # quantity the order was created for.
   my $stmnt = $dbh->prepare(
      "SELECT o.ordernumber, o.quantity,
              (SELECT COUNT(*) FROM aqorders_items oi WHERE oi.ordernumber = o.ordernumber) AS itemcount
       FROM aqorders o
       WHERE o.order_internalnote = ? AND o.order_vendornote = ?" );
   $stmnt->execute( $reference, $fileName );

   my %progress = ( orders => 0, items => 0, quantity => 0, complete => 0 );
   while ( my $row = $stmnt->fetchrow_hashref ) {
      $progress{orders}++;
      $progress{items} += $row->{itemcount};
      $progress{quantity} += $row->{quantity};
   }
   $stmnt->finish();

   # A line counts as written only when every one of its orders has all of the
   # items it was created for. A line that died between createOrder and the
   # item loop has an order and too few items, and must still be processed.
   $progress{complete} = ( $progress{orders} && $progress{items} >= $progress{quantity} ) ? 1 : 0;

   return \%progress;
}


1;
