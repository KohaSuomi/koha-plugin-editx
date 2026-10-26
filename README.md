# EDItX-plugin

Tämä plugin lisää EDItX tuen Kohaan.

## Käsittelyketju

Sanoma kulkee palvelimella kahdessa vaiheessa, ja vaiheiden väliin jää aineistontoimittajan tietokantaan (`edifact_messages`). Molemmat vaiheet ovat ajastettuja cronjobia.

1. **Aineistontoimittaja -> palvelin.** Toimittaja siirtää XML-sanoman SFTP:llä hakemistoon `import_tmp_path`.
2. **`runEditXImport.pl`** (cron) lukee `import_tmp_path`-hakemiston `*.xml`-tiedostot. Se tarkistaa sanoman duplikaattisuuden, etsii myyjän `vendor_edi_accounts`-taulusta sanoman SAN-tunnusta ja tallentaa sanoman `edifact_messages`-tauluun: `message_type='EDItX'`, `status='NEW'`. Tiedosto siirretään onnistuneesti `import_archive_path`-hakemistoon. Tyhjä, duplikaatti- tai virheellinen tiedosto päätyy `import_failed_path`-hakemistoon.
3. **`process_edi_messages.pl`** (cron) poimii `status='NEW'`-rivit käsittelyyn (katso [Aikataulut](#sanomien-käsittelyn-ja-virhehuomautusten-ajastus)). Se jäsentää sanoman, valitsee sanoman myyjän perusteella olevan käsittelijän ja luo tilauksen sekä siitä kuvailu- ja esinetiedot. Onnistuessa tilaksi asetetaan `OK`, virrheessä `FAILED` ja virhe kirjoitetaan `edifact_errors`-tauluun.
4. **Seuraus.** Käsittelyn jälkeen tilaa voi seurata Kohan EDI-sanomat-sivulla (`acqui/edifactmsgs.pl`). Epäonnistuneet sanomat on mahdollista ajaa uudelleen sivun **Aja uudelleen** -painikkeella.

REST-rajapinta kiertää vaiheet 1-2 ohi ja kirjoittaa sanoman suoraan `edifact_messages`-tauluun tilalla `NEW`, eli käsittely alkaa vaiheesta 3.

Sanoman tunnistee taulussa tiedostonimi, joka muodostetaan kentistä `ShipNoticeNumber` ja `IssueDateTime` (REST-rajapinnalla käyttäjätunnus etuliitteenä). Tämä toimii myös duplikaattien tunnistamisena: sama sanoma hylätään toistamiseksi. Poikkeuksena on sanoma, jonka käsittely on epäonnistunut (`FAILED`): toimittaja saa lähettää saman nimisen sanoman uudelleen korjattuna, ja se hyväksytään uudeksi käsittelyksi. Epäonnistunut sanoma ja sen virheet jäävät tauluun historiaa varten, joten tauluun voi jäädä kaksi riviä samalla tiedostonimellä.

## Käyttöönoton määritykset Koha-palvelimella

Koha-Suomessa uudet kontainerit muodostetaan konew -skriptillä. Pääosa asetuksista tulee uuden kontin muodostamisvaiheessa valmiina. Erikseen täytyy luoda vielä SFTP tiedonsiirtoja varten tunnukset sekä määrittää pluginin asetukset kohdassa [Rajapinnan konfigurointi](#rajapinnan-konfigurointi) kuvatulla tavalla.

## SFTP-tunnukset

SFTP tunnukset ovat muotoa [k]-[r]-editx, mutta jos kyseessä on tuotantotunnus -[r] jätetään pois. Kutakin kimppaa varten tarvitaan periaatteessa kaksi tunnusta. "kimppa-test-editx" ja "kimppa-editx". Tunnukset luodaan makeeditxaccount -skriptillä (host-toolsissa). Skripti luo tunnukset ja ohjeistaa niiden käyttöönoton.

## Rajapinnan konfigurointi

Asetukset tallennetaan `plugin_data`-tauluun ja luetaan sieltä. Ne ylläpidetään kohdassa [Configure](#configure-näkymä) kuvatulla sivulla (Työkalut → Liitännäiset → EDItX-plugin → Määritä).

**XML-tiedosto `procurement-config.xml` on vanhentunut** eikä sitä pidä enää perustaa uusiin asennuksiin.

Vanha XML-tiedosto toimii yhä varalla, jotta olemassa olevat asennukset eivät rikkoudu: kun `plugin_data`-rivin arvo on tyhjä, arvo kopioidaan XML-tiedostosta kantaan ensimmäisellä lukukerralla, ja sitä käytetään siitä eteenpäin. Tyhjä kanta-arvo ei siis tarkoita "ei asetusta" vaan "haetaan XML:stä".

### Mistä kukin asetus tulee

| Asetus | Lähde |
| --- | --- |
| `authoriser`, `allowed_locations`, `productform_alternative_triggers`, `automatch_biblios`, `use_finna_materialtype`, `notifications/mailto`, `notifications/mailfrom` | Configure-näkymä |
| `import_tmp_path`, `import_archive_path`, `import_failed_path`, `import_failed_archived_path` | Vain XML-tiedostosta. Nämä ovat viimeiset asetukset, joiden vuoksi tiedostoa ei voi vielä poistaa. |
| `log_directory` | Lasketaan aina: `<logdir>/editx`. Ei asetettavissa. |
| `import_load_path` | Perinnöisesti mukana, ei enää käytössä (ks. alla). |

Polut saa halutessaan kopioimaan tietokantaan skriptillä `cronjobs/importEditXPathsToDb.pl`, joka täyttää vain tyhjät rivit (`--force` ylikirjoittaa). Tämän jälkeen polut luetaan kannasta eikä tiedostoa enää tarvita niiden osalta.

### Configure-näkymä

Asetukset tallennetaan kantaan **Työkalut → Liitännäiset → EDItX-plugin → Määritä**. Sivulla määritetään käsittelyssäännöt, virheilmoitusten vastaanottajat sekä ONIX ProductForm -mäppäykset (`map_productform`) CSV-muodossa.

Sivulla määritettävät asetukset:

| Asetus | Merkitys |
| --- | --- |
| `authoriser` | EditX-tilausten luovan Koha-käyttäjän borrowernumber. Käyttäjä luo tilauskorit ja tilaukset, ja tähän on tarkoitusta varten lisätty oma editx-käyttäjä. |
| `allowed_locations` | Pilkuilla erotetut hyllypaikkakoodit, jotka hyväksytään, kun EDItX-tilikoodista haetaan kirjasto, hyllypaikka ja vuosi. Tarkistetaan Kohan LOC-arvoista. |
| `productform_alternative_triggers` | Pilkuilla erotetut hyllypaikkakoodit, jotka käyttävät `productform_alternative`-mäppäystä. |
| `automatch_biblios` | Kun käytössä, EDItX-tuonti yrittää yhdistää olemassa olevan tietueen kanssa ennen uuden luomista. Oletuksena päällä. Katso [Bibliotietueiden automaattinen täsmäytys](#bibliotietueiden-automaattinen-täsmäytys). |
| `use_finna_materialtype` | Kun käytössä, 942$c-kentän tieto johdetaan Finna-materiaalityypistä ONIX ProductForm -mäppäyksen sijaan. Oletuksena pois. |
| `notifications/mailto` | Pilkuilla erotetut vastaanottajat, joille apuskriptit raportoivat epäonnistuneesta EDItX-käsittelystä. |
| `notifications/mailfrom` | Ilmoitussähköpostien lähettäjä. |

Sivulla huomioitavaa:

- Sähköpostiosoitteet on oltava pilkulla eroteltuina samalla rivillä. XML:stä kopioitu arvo menee kantaan sellaisenaan, ja validointi hylkää tallennuksen, jos pilkut puuttuvat.
- `authoriser` ja `allowed_locations` ovat pakollisia ennen kuin tuonti voi toimia.
- Tuotantovaiheessa kannattaa varmuuskopioida `map_productform` **ennen** ensimmäistä tallennusta, koska tallennus tyhjentää taulun ja kirjoittaa sen uudelleen CSV:stä. Ohjeet ovat [UPGRADE.md](UPGRADE.md)-tiedostossa.

### Bibliotietueiden automaattinen täsmäytys

Kun `automatch_biblios` on käytössä, EDItX-tuonti yrittää löytää olemassa olevan bibliotietueen ennen uuden tietueen luomista. Täsmäytys tehdään `OrderProcessor::getBiblioItemData`-metodissa.

Ensisijaisesti tarkistetaan ISBN-tunnukset, joita kerätään sekä tilausviestistä (`ItemDetail`) että kopiotiedoista (`CopyDetail`). Jokaiselle ISBN-kandidaatille generoidaan vaihtoehtoiset hakumuodot metodilla `getIsbnLookupForms`:

1. Alkuperäinen muoto sellaisena kuin se esiintyy EDItX-viestissä
2. Muoto ilman väliviivoja ja välilyöntejä
3. Mikäli ISBN on validi (Business::ISBN), generoidaan myös ISBN-10- ja ISBN-13 -muunnokset sekä niistä poistetaan väliviivat

Näin esimerkiksi 10-merkkinen ISBN löytää vastaavan 13-merkkisen ISBN:n ja päinvastoin. Kaikki hakumuodot normalisoidaan väliviivattomiksi, ja haku tehdään `biblioitems.isbn`-kenttää vasten (`getItemsByIsbns`).

Jos yhtään ISBN-täsmäytystä ei löydy, tarkistetaan EAN-tunniste (`getItemsByEan`). Mikäli sekään ei tuota tulosta, käytetään julkaisijan tunnisteen ja vastuunottajan yhdistelmää (`getItemByColumns`).

Löydettäessä täsmäävä rivi palautetaan (`biblionumber`, `biblioitemnumber`, `isbn`). Tätä tietoa käytetään olemassa olevan tietueen hyödyntämiseen eikä uutta tietuetta luoda.

Vanhoista asennuksista päivitettäessä ks. [UPGRADE.md](UPGRADE.md).

### XML-tiedosto (vanhentunut)

> **Vanhentunut.** Uusiin asennuksiin tiedostoa ei luoda. Se on jäljellä vain taaksepäin yhteensopivuutta varten.

Tiedoston polku päätellään `KOHA_CONF`-ympäristömuuttujan arvosta, joten tiedosto on samassa hakemistossa kuin `koha-conf.xml` — tyypillisesti `/etc/koha/procurement-config.xml`.

Ainoa sisältö, jota tiedostosta enää tarvitaan, ovat `import_*`-polut, koska niitä ei tallenneta Configure-näkymään. Avaimet kirjoitetaan `data`-elementin alle `settings`-elementtiin:

| Avain | Tyypillinen polku | Käytös |
| --- | --- | --- |
| `import_tmp_path` | `/home/koha/koha-dev/var/spool/editx/tmp` | Aineistontoimittajan SFTP-sisääntulo |
| `import_archive_path` | `/home/koha/koha-dev/var/spool/editx/archive` | Onnistuneesti käsitellyt tiedostot |
| `import_failed_path` | `/home/koha/koha-dev/var/spool/editx/fail` | Käsittelyssä hylätyt tiedostot |
| `import_failed_archived_path` | `/home/koha/koha-dev/var/spool/editx/failed_archived` | Uudelleenajosta hylätyt vanhentuneet tiedostot |

Polkuihin ei yleensä tarvitse koskea: yllä olevat polut toimivat, jos käyttöönotto tehdään tässä dokumentissa kuvatulla tavalla. Kaikkia muita asetuksia ei tarvitse kirjoittaa tiedostoon lainkaan, vaan ne siirretään Configure-näkymään.

### Milloin tiedoston voi poistaa

Tiedosto voidaan poistaa, kun molemmat sen jäljelle jääneet tehtävät on hoidettu:

1. `import_*`-polut on kopioitu kantaan skriptillä `cronjobs/importEditXPathsToDb.pl`, ja kanta-arvot on varmistettu esimerkiksi skriptillä `cronjobs/checkEditXConfig.pl`.
2. Kaikki käsittelyssäännöt ja ilmoitusasetukset on tallennettu Configure-näkymässä.

Asennuksissa, joissa kanta-arvot on täytetty, tiedoston arvoja ei enää käytetä, ja tiedoston puuttuminen käsitellään harmittomasti: se vain ympäröidään tyhjällä hajautusmäärällä. Tällöin tiedosto voidaan poistaa suoraan. Asennuksissa, joissa kanta-arvot ovat tyhjiä, tiedosto on yhä ainoa lähde `import_*`-poluille — jos polut eivät ole kannassa eikä tiedostossa, `runEditXImport.pl` kaatuu käynnistyksessään.

### Perinnöiset ja käyttämättömät avaimet

`import_load_path` on jäänyt konfiguraatiosta roikkumaan: mikään tuotannossa kutsuttava käsittelyvaihe ei lue sitä, ja sitä käyttää vain moduuli, jota mikään muu moduuli ei lataa. Asetusta ei poistettu, jotta olemassa olevat asennukset eivät rikkoudu. `log_directory`-avainta ei voi asettaa lainkaan, vaan se lasketaan aina.

## Sanomien käsittelyn ja virhehuomautusten ajastus

Ajastukset sanomien käsittelyyn on valmiina koha-käyttäjän crontabissa, mutta uuden kontin luontivaiheessa ne on kommentoitu pois käytöstä. Käyttöönottovaiheessa kommenttimerkit täytyy poistaa seuraavilta riveiltä:

```cron
*/1 06-22 * * *  $TRIGGER cronjobs/runEditXImport.pl          # tiedostot (import_tmp_path) -> edifact_messages
*/1 06-22 * * *  $TRIGGER cronjobs/process_edi_messages.pl    # edifact_messages NEW -> tilaus
45 23 * * *      $TRIGGER cronjobs/notify_failed_editx.sh     # virheilmoitussähköpostit (sis. edifact_messages FAILED -sanomat)
00 21 * * *      $TRIGGER cronjobs/requeue_failed_editx.sh    # vanhentuneet/virheelliset tiedostot -> failed_archived / uudelleenjonoon
```

Molemmat minuutin välein ajettavat skriptit ovat välttämättömiä: `runEditXImport.pl` tuo sanomat tiedostoista tauluun ja `process_edi_messages.pl` muuntaa ne tilauksiksi. Jos jokin näistä on pois ajastuksesta, jälkimmäinen ei tee mitään, vaikka tauluun tulisi uusia `NEW`-rivejä.

Sanomat käsitellään klo 6.00-22.00 välisenä aikana minuutin välein tai niin nopeassa tahdissa kuin mahdollista. Uudelleenjonotus tapahtuu klo 21.00 ja virheilmoitussähköpostit lähetetään klo 23.45.

Virheilmoitussähköposti kokoaa `fail`-hakemiston tiedostot, päivän aikana epäonnistuneet sanomat `edifact_messages`-taulusta sekä tiedostoittain otteet `error.log`-tiedostosta. Duplikaatit kirjoitetaan `error.log`:iin, jotta ne näkyvät sähköpostissa perusteluineen.

`import_failed_path`-hakemiston tiedostot raportoidaan vain kerran: kun ilmoitus on lähetetty onnistuneesti, raportoidut tiedostot siirretään `import_failed_archived_path`-hakemistoon. Jos sähköpostin lähetys epäonnistuu, tiedostot jäävät `fail`-hakemistoon ja ne raportoidaan seuraavalla ajolla. `import_tmp_path`-hakemiston tiedostot raportoidaan joka ajolla, kunnes ne käsitellään tai täyttävät seitsemän vuorokautta ja arkistoidaan. Kannassa epäonnistuneet sanomat (status `FAILED`) haetaan `edifact_messages`-taulusta vain sen päivän osalta, jolloin niiden virhe on kirjattu, joten `FAILED`-rivit jäävät historiaan eivätkä toistu ilmoituksissa. Sähköpostin otsikko ja runko lähetetään UTF-8-merkistönä.

`notify_failed_editx_elastic.sh` ja `notify-failed-editx_old.sh` ovat vanhentuneita eivätkä ne korvaa `notify_failed_editx.sh`:n toimintoja. Älä ajasta niitä.

`process_edi_messages.pl` lukee XSD-skeeman polusta, joka on kovakoodattu arvoon `/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/`. Jos pluginia ei ole asennettu tuohon hakemistoon, skeemavarmistus epäonnistuu ja virhe näkyy lokeissa.

## Sanoma-esimerkki

Sanoman tiedosto tulee olla xml-muodossa.

`Header`-osio sisältää yleisiä tilauksen tietoja, kun taas jokaisella teoksella on oma `ItemDetail`-elementtinsä. `LineNumber`-arvoa tulee kasvattaa jokaisen `ItemDetail`-elementin kohdalla. `Summary`-tagi tarjoaa yhteenvedon kaikista `ItemDetail`-elementeistä.

### Tunnistetut aineistontoimittajat

Käsittelijä valitaan sanoman `SellerParty/PartyName/NameLine`-kentän arvon perusteella. Tunnistettuja toimittajia ovat:

| `NameLine` | Käsittelijä |
| --- | --- |
| `BTJ Finland Oy` | BTJ |
| `Booky.fi Oy` | Booky |
| `Kirjavälitys Oy` | Kirjavälitys |

Jokaisella toimittajalla on omat `ItemDetail`- ja `CopyDetail`-käsittelijänsä, koska kenttien sisältö vaihtelee toimittajan mukaan. Jos `NameLine`-arvoa ei tunnisteta, sanoma käsitellään yleisellä oletuskäsittelijällä, joka ei huomioi toimittajakohtaisia eroja. Sanoma voidaan silti tallentaa tauluun, mutta kentät voivat jäädä puuttumaan.

Alla oleva esimerkkisanoma on BTJ:n lähettämä. Kirjavälityksen ja Bookyn sanomarakenteet poikkeavat esimerkistä.


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

## REST-rajapinta

Plugin tarjoaa REST-rajapinnan ulkopuolisille järjestelmille, jotka haluavat integroitua ja lähettää EDItX-sanomia suoraan Koha-palvelimelle. Rajapinta on käytössä nimiavaruudessa `kohasuomi`, eli sanomat lähetetään osoitteeseen `/api/v1/contrib/kohasuomi/editx`.

### Päätepiste

| Metodi | Osoite | Kuvaus | Oikeus |
| --- | --- | --- | --- |
| POST | `/api/v1/contrib/kohasuomi/editx` | Lisää EDItX-sanoman `edifact_messages`-tauluun statuksella `NEW` | `acquisition: edi_manage` |
| PUT | `/api/v1/contrib/kohasuomi/editx/{id}` | Muuttaa sanoman tilan (esim. `NEW`, jolloin sanoma ajetaan uudelleen) | `acquisition: edi_manage` |

### Todennus (OAuth2)

Todennus tehdään Koha:n OAuth2 client credentials -vuolla.

Hae access token lähettämällä `client_id` ja `client_secret` token-päätepisteeseen:

```
curl -X POST https://<koha-palvelin>/api/v1/oauth/token \
     -d grant_type=client_credentials \
     -d client_id=<CLIENT_ID> \
     -d client_secret=<CLIENT_SECRET>
```

Vastauksena tulee access token:

```json
{
    "access_token": "xxxxxxxxxxxxxxxx",
    "token_type": "Bearer",
    "expires_in": 3600
}
```

Token on voimassa tunnin (`expires_in` 3600 sekuntia), jonka jälkeen haetaan uusi. Jos tunnukset ovat väärät, vastauksena on `403 unauthorized_client`. Vanhentunut tai kelvoton token tuottaa virheen `401`.

Käyttäjällä, joka lähettää sanomia tai käyttää uudelleenajoa, täytyy olla alioikeus **acquisition → edi_manage**.

### Sanoman lähetys

Lähetä EDItX-sanoma XML-merkkijonona POST-pyynnöllä. `Content-Type`-otsakkeen on oltava `application/xml` ja mukaan laitetaan haettu access token `Authorization: Bearer` -otsakkeena. Esimerkki sanoman sisällöstä on kohdassa [Sanoma-esimerkki](#sanoma-esimerkki).

```
curl -X POST https://<koha-palvelin>/api/v1/contrib/kohasuomi/editx \
     -H "Authorization: Bearer <ACCESS_TOKEN>" \
     -H "Content-Type: application/xml" \
     --data @sanoma.xml
```

Sanoma tarkistetaan ennen tallennusta. Tarkistuksessa varmistetaan, että pakolliset kentät ovat paikallaan ja että sanoman SAN-tunnus löytyy `vendor_edi_accounts`-taulusta (kuluttajatunnus `VendorAssignedID`, tunnus 91; varalta myyjätunnus `BuyerAssignedID`, tunnus 92). Kustannuspaikkaa ei tarkisteta tässä vaiheessa, vaan se varmistetaan vasta tilausta luotaessa.

#### Vastaukset

| Tilakoodi | Merkitys |
| --- | --- |
| `201` | Sanoma tallennettu onnistuneesti (`{"message":"Data saved successfully"}`) |
| `400` | Virheellinen XML tai puuttuvat pakolliset kentät. Vastauskappaleen `errors`-listassa kerrotaan kentät ja tuntematon SAN-tunnus. |
| `500` | Odottamaton palvelinvirhe |

`POST`-päätepiste ei palauta `404`-tilakoodia; sellainen kuuluu `PUT`-päätepisteelle.

### Sanoman uudelleenajo

`PUT`-päätepiste vaihtaa sanoman tilan. Asetamalla tila `NEW` pääsee sanoman takaisin käsittelyjonoon.

```
curl -X PUT https://<koha-palvelin>/api/v1/contrib/kohasuomi/editx/<ID> \
     -H "Authorization: Bearer <ACCESS_TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{"status":"NEW"}'
```

Sama toiminto on käytettävissä käyttöliittymästä: EDI-sanomat-sivulla (`acqui/edifactmsgs.pl`) jokaisella sanomalla on **Aja uudelleen** -painike, joka kutsuu tätä päätepistettä. Hyväksyttävät tilat ovat `NEW`, `PROCESSING`, `OK` ja `FAILED`.

### Sanoman elinkaari

Lähetetty sanoma tallentuu `edifact_messages`-tauluun statuksella `NEW`. Ajastettu `process_edi_messages.pl`-skripti käsittelee uudet sanomat tilauksiksi, jonka jälkeen käsittelyä voi seurata Koha:n EDI-sanomat-sivulla.

Tilat kulkevat näin:

| Tila | Merkitys |
| --- | --- |
| `NEW` | Odottaa käsittelyä |
| `PROCESSING` | Käsittely varattu (käsittelijä on lukenut sanoman itselleen) |
| `OK` | Käsitelty onnistuneesti, tilaus luotu |
| `FAILED` | Käsittely epäonnistui; virhe on `edifact_errors`-taulussa |

Epäonnistuneen sanoman toimittaja voi korjata ja lähettää uudelleen samalla `ShipNoticeNumber`- ja `IssueDateTime`-arvolla. Korjattu sanoma tallentuu uutena `NEW`-rivinä, joten käsittely käynnistyy tavallisesti. Vanha `FAILED`-rivi säilyy taulussa virheineen.

`PROCESSING`-tilaan siirtyminen on atominen, joten rinnakkaiset ajot eivät käsittele samaa sanomaa kahteen kertaan. Jos käsittely keskeytyy niin, että sanoma jää `PROCESSING`-tilaan, se pitää palauttaa tilaan `NEW` käsin.

## Apukriptit

Näitä ei ajasteta, ellei toisin mainita.

| Skripti | Käyttötarkoitus |
| --- | --- |
| `cronjobs/checkEditXConfig.pl` | Tulostaa jokaisen asetuksen lähteen (`plugin_data` tai `XML`) ja arvon, ja merkitsee puuttuvat hakemistot tunnuksella `[DIR MISSING]`. Ensimmäinen skripti, joka kannattaa ajaa, kun tuonti ei toimi. |
| `cronjobs/exportEditXConfig.pl` | Tulostaa asetukset `export`-riveinä. Apuskriptit lukevat asetukset tällä tavalla. |
| `cronjobs/importEditXPathsToDb.pl` | Kopioi `import_*`-polut XML-tiedostosta tietokantaan. Täyttää vain tyhjät rivit; `--force` ylikirjoittaa. |
| `cronjobs/get_failed_editx_messages.pl` | Tulostaa päivän aikana epäonnistuneet sanomat niiden virheteksteineen. Käytetään `notify_failed_editx.sh`:n apuna. |

Vanhentuneita skriptejä ei pidä ajastaa: `cronjobs/notify_failed_editx_elastic.sh` ja `cronjobs/notify-failed-editx_old.sh`.

## Vianmääritys

**Sanoma ei ilmesty tauluun.** Tarkista ensin asetukset: `perl cronjobs/checkEditXConfig.pl`. Jos `import_tmp_path` on merkitty `[DIR MISSING]`, hakemisto puuttuu. Tarkista myös, että tiedostolla on `.xml`-pääte ja että se ei ole tyhjä.

**Sanoma päätyy `fail`-hakemistoon.** Tyhjä tiedosto, duplikaatti ja puuttuva myyjä päätyvät sinne. Vastaavat merkinnät ovat pluginin `error.log`-tiedostossa. Duplikaatiksi tulkitaan sanoma, jolla on jo käsitelty tai käsittelyssä oleva rivi samalla nimellä; jos taulussa on vain `FAILED`-tilassa oleva sanoma, korjattu sanoma hyväksytään eikä sitä siirretä `fail`-hakemistoon.

**Sanoma on taulussa mutta tilausta ei syntynyt.** Katso `edifact_messages`-taulun tila ja `edifact_errors`-taulu, ks. [Kehittäjälle](#kehittäjälle-mistä-löytää-virheet).

**Sähköpostia ei tule.** Varmista, että `notify_failed_editx.sh` on ajastettu ja että `notifications/mailto` sisältää pilkulla erotetut osoitteet. Skripti vaatii `xmllint`-, `mail`- ja `perl`-komennot sekä Perl-moduulit `Encode` ja `MIME::Base64`. Jos mitään ei ole reportoitavaa, skripti poistuu hiljaa.

**Sama virheilmoitus toistuu.** Raportoidut `fail`-hakemiston tiedostot siirretään onnistuneen sähköpostin jälkeen `import_failed_archived_path`-hakemistoon, joten ne eivät toistu. Jos sähköpostin lähetys epäonnistuu, siirtoa ei tehdä ja samat tiedostot raportoidaan seuraavalla ajolla. Tarkista tällöin `mail`-komennon toiminta. `edifact_messages`-taulun `FAILED`-rivit raportoidaan vain niiden virhepäivän ajalta.

**Sanoma jää käsittelemättä.** Tarkista, että `process_edi_messages.pl` on ajastettu. Pelkkä `runEditXImport.pl` ei riitä, vaikka tauluun tulisi uusia `NEW`-rivejä.

**Skeemavarmistus epäonnistuu.** `process_edi_messages.pl` odottaa skeemat polusta `/var/lib/koha/plugins/Koha/Plugin/Fi/KohaSuomi/Editx/Procurement/EditX/XmlSchema/`, joka on kovakoodattu.

## Kehittäjälle: mistä löytää virheet

Plugin kirjoittaa kolmeen paikkaan. Se mitä kukin niistä sisältää, riippuu vaiheesta.

| Oire | Mistä etsitään |
| --- | --- |
| Tiedosto ei pääty `edifact_messages`-tauluun | `<logdir>/editx/transaction.log` ja `<logdir>/editx/error.log` |
| Tiedosto hyppää `fail`-hakemistoon | `error.log`. Tätä vaihetta varten ei synny `edifact_errors`-riviä, koska virhe liitetään sanomaan tiedoston alkuperäisellä nimellä, vaikka tauluun tallennetaan sanoma muodostetulla nimellä. Virheilmoitus näyttää siksi sekä `fail`-hakemiston tiedostonimen että Kohassa näkyvän nimen (`ShipNoticeNumber_IssueDateTime`). |
| Sanoma taulussa, tilaus ei syntynyt | `edifact_messages.status` ja `edifact_errors.details`. **Lokitiedostoa ei ole.** |
| REST-pyyntö palautti `400` | Vastauskappaleen `errors`-lista sekä `error.log` |
| REST-pyyntö palautti `500`, tai todennus-/valtuutusvirhe | Kohan oma-loki, jonne kirjoitetaan `Koha::Logger`-olla rajapinnan kautta (`interface => 'api'`) |
| Asetukset eivät ota vaikutusta | `cronjobs/checkEditXConfig.pl` kertoo kunkin avaimen lähteen |
| Testidata ja -skriptit | `t/TESTING.md` sekä apurit `t/populate_test_data.pl` ja `t/seed_automatch_fixtures.pl` |

Pluginin oma loki on aina `<logdir>/editx/`, jossa ovat `transaction.log` (tapahtumat) ja `error.log` (virheet). Hakemisto lasketaan eikä sitä voi asettaa.

### Tilausvaihe ei kirjoita lokeja

Tämä on tärkeää tietää vianmäärityksessä: `process_edi_messages.pl` **ei kirjoita lokeja lainkaan**. Vaikka tilauskäsittely kirjelmöi virheitä, lokiversio luodaan ainoastaan kutsujan antamalla hakemistolla, ja tässä kutsujaksi on jäänyt antamatta hakemisto. Kirjoitus estetään lisäksi olemattomiin tiedostoihin, joten mitään ei pääty levylle huoletta ään.

Tilausvaiheen virheet ovat siksi kannassa:

```sql
SELECT m.id, m.filename, m.status, m.transfer_date, e.date, e.details
FROM edifact_messages m
LEFT JOIN edifact_errors e ON e.message_id = m.id
WHERE m.message_type = 'EDItX'
ORDER BY m.id DESC;
```

Rajattu epäonnistuneisiin:

```sql
SELECT m.id, m.filename, e.details
FROM edifact_messages m
LEFT JOIN edifact_errors e ON e.message_id = m.id
WHERE m.message_type = 'EDItX' AND m.status = 'FAILED';
```

`details`-sarake sisältää Perlin `die`-viestin, joka kertoo virheen suoraan. Alkuperäinen XML löytyy `edifact_messages.raw_msg`-sarakkeesta, joten arkistoidun tiedoston saa kannasta takaisin:

```sql
SELECT raw_msg FROM edifact_messages WHERE id = <id>;
```

Korjaus on pieni: `OrderProcessor.pm` rakentaa lokiversion ilman hakemistoa, joten se kannattai tehdä samalla tavalla kuin `runEditXImport.pl` eli antaa sille `log_directory`-asetuksen arvon.

## Käyttöohjeet

Yleisiin käyttöohjeisiin pääset [tästä](https://koha-suomi.fi/dokumentaatio/editx/)
