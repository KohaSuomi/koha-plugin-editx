# Tuotantopäivitys (master@4180701 → ks25-v2 / v2.0.0)

Tuotanto on `master`-haaralla (commit 4180701, v1.0.2), jossa ei ole REST-rajapintaa eikä configure-näkymää. Tämä versio tuo ne uutena. Muut putkeen liittyvät muutokset ovat jo tuotannossa (sanomat `edifact_messages`-taulussa jne.).

Versiopäivitys 1.0.2 → 2.0.0 käynnistää Kohassa automaattisesti `upgrade()`-metodin. Avaa päivityksen jälkeen **Tools → Plugins → EDItX-plugin**, jotta se käynnistyy.

## 1. Configure-näkymä (uusi)

Asetukset tallennetaan nyt `plugin_data`-tauluun; `procurement-config.xml` toimii vain varalla (jos tietokannassa ei ole arvoa, se kopioidaan XML:stä sellaisenaan).

1. Avaa **Tools → Plugins → EDItX-plugin → Configure** ja tarkista kentät, jotka aiemmin lukivat XML-tiedostosta: `authoriser`, `allowed_locations`, `productform_alternative_triggers`, `automatch_biblios`, `use_finna_materialtype` sekä notifications `mailto`/`mailfrom`. Tallenna.
2. **Mailto-pilkut:** sähköpostiosoitteet on oltava pilkulla eroteltuina samalla rivillä (`osoite1@esim.fi,osoite2@esim.fi`). XML:stä kopioitu arvo menee kantaan sellaisenaan – jos pilkut puuttuvat, validointi hylkää tallennuksen.
3. **Product form -kartta** (`map_productform`, ONIX → productform) ylläpidetään nyt Configure-sivulla CSV-muodossa.

Huom: polkuasetukset (`import_*`, `log_directory`) eivät ole muokattavissa Configure-sivulla, ne tulevat edelleen XML:stä.

## 2. REST-rajapinta (uusi)

Päätepisteet (namespace `kohasuomi`):

- `POST /api/v1/contrib/kohasuomi/editx` – lisää EDItX-sanoman suoraan `edifact_messages`-tauluun.
- `PUT /api/v1/contrib/kohasuomi/editx/{id}` – muuttaa viestin statuksen (uudelleenajo `NEW`).

Käyttöliittymässä EDI-sanomat-sivulla (`acqui/edifactmsgs.pl`) on uusi **"Aja uudelleen"** -painike, joka kutsuu PUT-päätepistettä (`js/editxButton.js`).

Tarkista tuotannossa:

1. REST-API on käytössä ja pluginin reitit latautuvat (`/api/v1/contrib/kohasuomi/...`).
2. API-todennus toimii: nykyisissä Koha-versioissa riittää kirjautunut intranet-käyttäjä (eväste), vanhemmissa tarvitaan API-avain (OAuth2).
3. Käyttäjällä, joka lisää viestejä tai käyttää Rerun-painiketta, on **`acquisition → edi_manage`** -alioikeus.

## 3. Ajastukset (cron)

Päivitä koha-käyttäjän crontab seuraavasti. Ainoastaan `process_edi_messages.pl` on kokonaan uusi ajuri; `runEditXImport.pl` on muuttunut (siirtää tiedostot `edifact_messages`-tauluun) ja `.sh`-skriptit lukevat nyt asetukset tietokannasta `exportEditXConfig.pl`:n kautta (ei enää suoraan XML:stä) – varmista siis, että Configure on tallennettu ennen kuin ajastukset aktivoituvat.

```cron
*/1 06-22 * * *  $TRIGGER cronjobs/runEditXImport.pl          # tiedostot (import_tmp_path) -> edifact_messages
*/1 06-22 * * *  $TRIGGER cronjobs/process_edi_messages.pl    # UUSI: edifact_messages NEW -> tilaus
45 23 * * *      $TRIGGER cronjobs/notify_failed_editx.sh     # virheilmoitussähköpostit (sis. Elasticsearch-tarkistuksen ja edifact_messages FAILED -sanomat)
00 21 * * *      $TRIGGER cronjobs/requeue_failed_editx.sh    # vanhentuneet/virheelliset tiedostot -> failed_archived / uudelleenjonoon
```

- `exportEditXConfig.pl` **ei** ole ajastettava job, vaan `.sh`-skriptien avuksi tehty config-seuraaja (voi ajaa käsin asetusten tarkistukseen).
- `notify_failed_editx_elastic.sh` ja `notify-failed-editx_old.sh` ovat vanhentuneita, älä ajasta niitä.

## 4. Siivous huomioitavaa

### Viivakoodiseedin siirto (ennen ensimmäistä ajomallia uudella versiolla)

Tuotanto pitää viivakoodien vapaata numeroa `sequences.item_barcode_nextval`-sarakkeessa, uusi versio lukee sen `plugin_data.next_barcode`-avaimesta (`Koha::Plugin::Fi::KohaSuomi::Editx`). Jotta numerointi jatkuu katkeamatta (eikä saman päivän viivakoodit ala alusta), kopioi arvo `plugin_data`-tauluun **ennen kuin uusi versio tuottaa ensimmäisen viivakoodin**:

```sql
INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
SELECT 'Koha::Plugin::Fi::KohaSuomi::Editx', 'next_barcode', item_barcode_nextval
FROM sequences
ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value);
```

Tarkistus:

```sql
SELECT plugin_value FROM plugin_data
WHERE plugin_class='Koha::Plugin::Fi::KohaSuomi::Editx' AND plugin_key='next_barcode';
```

### Vanha sequences-taul

Kun arvo on siirretty ja `sequences`-taulu on vahvistettu tyhjäksi muuhun käyttöön, se ei ole uudessa versiossa enää käytössä ja sen voi pudottaa:

```sql
DROP TABLE IF EXISTS sequences;
```

- `map_productform` ja `aqbudgets_spend_log` varmistetaan olemassa oleviksi `upgrade()`-metodin toimesta.

## 5. Testaus

1. Configure-sivun tallennus ja mailto-pilkkuvalidointi.
2. REST: lähetä EDItX-sanoma POST-päätepisteeseen tai aja viesti uudelleen "Aja uudelleen" -painikkeella (status → `NEW`).
3. Seuraa lokeja: pluginin oma loki (`logdir/editx`) ja Koha:n API-loki (`interface: api`).