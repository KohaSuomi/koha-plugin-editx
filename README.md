# EDItX-plugin

Tämä plugin lisää EDItX tuen Kohaan.

## Käyttöönoton määritykset Koha-palvelimella

Koha-Suomessa uudet kontainerit muodostetaan konew -skriptillä. Pääosa asetuksista tulee uuden kontin muodostamisvaiheessa valmiina. Erikseen täytyy luoda vielä SFTP tiedonsiirtoja varten tunnukset sekä päivittää rajapinnan konfiguraatioon käytettävä procurement-config.xml

## SFTP Tunnukset

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
