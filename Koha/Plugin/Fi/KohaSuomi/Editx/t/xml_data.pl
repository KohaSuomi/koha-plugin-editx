#!/usr/bin/perl
use C4::Context;
use XML::LibXML;

my $xml_data = '<?xml version="1.0" encoding="UTF-8"?>
<LibraryShipNotice version="1.0">
    <Header>
        <ShipNoticeNumber>12345</ShipNoticeNumber>
        <IssueDateTime>20250205T1730</IssueDateTime>
        <PurposeCode>Original</PurposeCode>
        <DateCoded>
            <Date>20250205</Date>
            <DateQualifierCode>Shipped</DateQualifierCode>
        </DateCoded>
        <BuyerParty>
            <PartyID>
                <PartyIDType>VendorAssignedID</PartyIDType>
                <Identifier>12345</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>Kohala;FI-KOHA;016</NameLine>
            </PartyName>
        </BuyerParty>
        <SellerParty>
            <PartyID>
                <PartyIDType>BuyerAssignedID</PartyIDType>
                <Identifier>FI-BTJ</Identifier>
            </PartyID>
            <PartyName>
                <NameLine>BTJ Finland Oy</NameLine>
            </PartyName>
        </SellerParty>
    </Header>
    <ItemDetail>
        <LineNumber>1</LineNumber>
        <ProductID>
            <ProductIDType>EAN13</ProductIDType>
            <Identifier>9789510506103</Identifier>
        </ProductID>
        <ProductID>
            <ProductIDType>ISBN</ProductIDType>
            <Identifier>978-951-0-50610-3</Identifier>
        </ProductID>
        <ItemDescription>
            <ProductForm>BK</ProductForm>
            <Title>Izak.</Title>
            <Author>Elstelä, Joel</Author>
            <SeriesTitle></SeriesTitle>
            <VolumeOrPart/>
            <EditionStatement/>
            <CityOfPublication></CityOfPublication>
            <PublisherName>WSOY</PublisherName>
            <YearOfPublication>2024</YearOfPublication>
        </ItemDescription>
        <QuantityShipping>1</QuantityShipping>
        <ReferenceCoded>
            <ReferenceTypeCode>VendorsOrderReference</ReferenceTypeCode>
            <ReferenceNumber>12345</ReferenceNumber>
            <ReferenceDate>05.02.2025</ReferenceDate>
        </ReferenceCoded>
        <PricingDetail>
            <Price>
                <MonetaryAmount>13.68</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>FixedRPIncludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <PricingDetail>
            <Price>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <CountryCode>FI</CountryCode>
                <PriceQualifierCode>FixedRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <PricingDetail>
            <Price>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
                <PriceQualifierCode>SRPExcludingTax</PriceQualifierCode>
                <Tax>
                    <TaxTypeCode>VAT</TaxTypeCode>
                    <Percent>14</Percent>
                </Tax>
            </Price>
        </PricingDetail>
        <CopyDetail>
            <SubLineNumber>1</SubLineNumber>
            <CopyQuantity>1</CopyQuantity>
            <DeliverToLocation>OUPKAIK2025</DeliverToLocation>
            <DestinationLocation>OUPKAIK2025</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <LocationCode>FI-KOHA;210;1</LocationCode>
            <ReaderInterestCode/>
            <FundDetail>
                <FundNumber>OUPKAIK2025</FundNumber>
                <MonetaryAmount>12.00</MonetaryAmount>
            </FundDetail>
            <Message>
                <MessageType>04</MessageType>
                <MessageLine>&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
&lt;collection xmlns=&quot;http://www.loc.gov/MARC21/slim&quot;&gt;
 &lt;record&gt;
  &lt;leader&gt;00962nam a22002898a 4500&lt;/leader&gt;
  &lt;controlfield tag=&quot;001&quot;&gt;978-951-0-50610-3&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;003&quot;&gt;FI-Woima&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;005&quot;&gt;20240326101401.0&lt;/controlfield&gt;
  &lt;controlfield tag=&quot;008&quot;&gt;240315s2024    fi                  fin&lt;/controlfield&gt;
  &lt;datafield tag=&quot;020&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;978-951-0-50610-3&lt;/subfield&gt;
   &lt;subfield code=&quot;q&quot;&gt;kovakantinen&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;035&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;(FI-BTJ)7459348&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;040&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;FI-Woima&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;fin&lt;/subfield&gt;
   &lt;subfield code=&quot;e&quot;&gt;rda&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;041&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;fin&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;084&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;ykl&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;84.2&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;100&quot; ind1=&quot;1&quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Elstelä, Joel&lt;/subfield&gt;
   &lt;subfield code=&quot;e&quot;&gt;kirjoittaja&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;245&quot; ind1=&quot;1&quot; ind2=&quot;0&quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;Izak.&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;250&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;1. p.&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;260&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;b&quot;&gt;WSOY&lt;/subfield&gt;
   &lt;subfield code=&quot;c&quot;&gt;2024&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;263&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;20240904&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;264&quot; ind1=&quot;3&quot; ind2=&quot;1&quot;&gt;
   &lt;subfield code=&quot;b&quot;&gt;WSOY&lt;/subfield&gt;
   &lt;subfield code=&quot;c&quot;&gt;2024&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;300&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;c&quot;&gt;korkeus 221 mm, leveys 144 mm, paksuus 46 mm&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;336&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;rdacontent&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;teksti&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;txt&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;337&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;rdamedia&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;käytettävissä ilman laitetta&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;n&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;338&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;2&quot;&gt;rdacarrier&lt;/subfield&gt;
   &lt;subfield code=&quot;a&quot;&gt;nide&lt;/subfield&gt;
   &lt;subfield code=&quot;b&quot;&gt;nc&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;500&quot; ind1=&quot; &quot; ind2=&quot; &quot;&gt;
   &lt;subfield code=&quot;a&quot;&gt;EI VIELÄ ILMESTYNYT, arvioitu ilmestymisaika 04.09.2024&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;856&quot; ind1=&quot;4&quot; ind2=&quot;2&quot;&gt;
   &lt;subfield code=&quot;q&quot;&gt;image&lt;/subfield&gt;
   &lt;subfield code=&quot;u&quot;&gt;https://sopimusasiakkaat.booky.fi/image.php?size=medium&amp;amp;id=9789510506103&lt;/subfield&gt;
   &lt;subfield code=&quot;z&quot;&gt;Kansikuva&lt;/subfield&gt;
  &lt;/datafield&gt;
  &lt;datafield tag=&quot;856&quot; ind1=&quot;4&quot; ind2=&quot;2&quot;&gt;
   &lt;subfield code=&quot;q&quot;&gt;text&lt;/subfield&gt;
   &lt;subfield code=&quot;u&quot;&gt;https://sopimusasiakkaat.booky.fi/description.php?ean=9789510506103&lt;/subfield&gt;
   &lt;subfield code=&quot;z&quot;&gt;Kuvaus&lt;/subfield&gt;
  &lt;/datafield&gt;
 &lt;/record&gt;
&lt;/collection&gt;
                </MessageLine>
            </Message>
            <RequestedBy/>
            <ApprovedBy/>
        </CopyDetail>
    </ItemDetail>
    <Summary>
        <NumberOfLines>1</NumberOfLines>
        <UnitsShipped>1</UnitsShipped>
    </Summary>
</LibraryShipNotice> ';
my $parser = XML::LibXML->new();
my $xml_doc = $parser->parse_string($xml_data);

my $ship_notice_number = $xml_doc->findvalue('//ShipNoticeNumber');
my $issue_date_time = $xml_doc->findvalue('//IssueDateTime');


my $name = $ship_notice_number;
my $content = $xml_data;
my $status = 'pending';  # Default status for new entries


my $dbh = C4::Context->dbh;

my $sth = $dbh->prepare("INSERT INTO koha_plugin_fi_kohasuomi_editx_contents(name, content, status) VALUES (?, ?, ?)");
$sth->execute($name, $content, $status);


