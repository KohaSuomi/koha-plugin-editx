# EDItX-plugin

Tämä plugin lisää EDItX tuen Kohaan.

## Käyttöönoton määritykset Koha-palvelimella

Koha-Suomessa uudet kontainerit muodostetaan konew -skriptillä. Pääosa asetuksista tulee uuden kontin muodostamisvaiheessa valmiina. Erikseen täytyy luoda vielä SFTP tiedonsiirtoja varten tunnukset sekä päivittää rajapinnan konfiguraatioon käytettävä procurement-config.xml

## SFTP-tunnukset

SFTP tunnukset ovat muotoa [k]-[r]-editx, mutta jos kyseessä on tuotantotunnus -[r] jätetään pois. Kutakin kimppaa varten tarvitaan periaatteessa kaksi tunnusta. "kimppa-test-editx" ja "kimppa-editx". Tunnukset luodaan makeeditxaccount -skriptillä (host-toolsissa). Skripti luo tunnukset ja ohjeistaa niiden käyttöönoton.

## Rajapinnan konfigurointi

Konfiguraatio on tiedostossa /etc/koha/procurement_config.xml:

```
<?xml version="1.0"?>
<data>
    <settings>
        <import_tmp_path>/home/koha/koha-dev/var/spool/editx/tmp</import_tmp_path> <!-- The folder where files should be first put. The Integrations external entrypoint -->
        <import_load_path>/home/koha/koha-dev/var/spool/editx/load</import_load_path> <!-- The path from where the script reads files to import -->
        <import_archive_path>/home/koha/koha-dev/var/spool/editx/archive</import_archive_path> <!-- The path where files are archived after succesfull import-->
        <import_failed_path>/home/koha/koha-dev/var/spool/editx/fail</import_failed_path> <!-- The path where files are archived if something fails during import-->
        <import_failed_archived_path>/home/koha/koha-dev/var/spool/editx/failed_archived</import_failed_archived_path> <!-- The path where files are archived if something fails during import-->
        <authoriser>nnnnnn</authoriser> <!-- A borrowers id (borrowernumber) used in import, change this! -->
        <allowed_locations>LN,AIK,MUS,OU</allowed_locations>
        <productform_alternative_triggers>LAP</productform_alternative_triggers> <!-- The shelving location that is found in fundnumber, used for assigning productform_alternative from db map_productform-->
        <automatch_biblios>yes</automatch_biblios> <!-- Set to 'no' if you want to create a new biblio and biblioitem on every order. -->
    </settings>
    <notifications>
        <mailto>osoite1@ouka.fi,osoite2@ouka.fi,osoite3@ouka.fi</mailto> <!-- comma separated list of email-addresses to send error reports to -->
    </notifications>
</data>
```

Polkuihin ei yleensä tarvitse koskea, oletuspolut toimivat jos käyttöönotto tehdään tässä dokumentissa kuvatulla tavalla. Authoriser on Kohassa määritelty EditX-tilausten luoja (Kohaan tarkoitusta varten lisätyn editx-käyttäjän borrowernumber) ja allowed_locations kertoo mille hyllypaikoille aineistoa voi hankkia. Kuvailutietueiden tuplakontrollin voi halutessaan kytkeä pois muuttamalla automatch_biblios asetukseksi no. Silloin tilatuista nimekkeistä muodostuu aina uudet kuvailutietueet omine niteineen.

Notifications-osan mailto-elementissä määritellään sähköpostitse lähetettävien virhesanomien vastaanottajat.

## Sanomien käsittelyn ja virhehuomautusten ajastus

Ajastukset sanomien käsittelyyn on valmiina koha-käyttäjän crontabissa, mutta uuden kontin luontivaiheessa ne on kommentoitu pois käytöstä. Käyttöönottovaiheessa kommenttimerkit täytyy poistaa seuraavilta riveiltä:

```
  */1 06-22 * * *    $TRIGGER cronjobs/runEditXImport.pl
  45 23 * * *        $TRIGGER cronjobs/notify_failed_editx.sh
  00 21 * * *        $TRIGGER cronjobs/requeue_failed_editx.sh
```

Sanomat käsitellään klo 6.00-22.00 välisenä aikana minuutin välein tai niin nopeassa tahdissa kuin mahdollista.

## Sanoma-esimerkki

Sanoman tiedosto tulee olla xml-muodossa.

`Header`-osio sisältää yleisiä tilauksen tietoja, kun taas jokaisella teoksella on oma `ItemDetail`-elementtinsä. `LineNumber`-arvoa tulee kasvattaa jokaisen `ItemDetail`-elementin kohdalla. `Summary`-tagi tarjoaa yhteenvedon kaikista `ItemDetail`-elementeistä.


```xml
<?xml version="1.0" encoding="UTF-8"?>
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
                <MonetaryAmount>23.79</MonetaryAmount>
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
                <MonetaryAmount>20.87</MonetaryAmount>
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
            <DeliverToLocation>FOOPKAIK2025</DeliverToLocation>
            <DestinationLocation>FOOPKAIK2025</DestinationLocation>
            <ProcessingInstructionCode>Catalog</ProcessingInstructionCode>
            <CopyValue>
                <MonetaryAmount>12.00</MonetaryAmount>
                <CurrencyCode>EUR</CurrencyCode>
            </CopyValue>
            <LocationCode>FI-KOHA;210;1</LocationCode>
            <ReaderInterestCode/>
            <FundDetail>
                <FundNumber>FOOPKAIK2025</FundNumber>
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
</LibraryShipNotice>
```

## Käyttöohjeet

Yleisiin käyttöohjeisiin pääset [tästä](https://koha-suomi.fi/dokumentaatio/editx/)
