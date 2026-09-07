-- Tuotantopäivitys master@4180701 -> ks25-v2 / v2.0.0
-- Aja ennen uuden version käyttöönottoa:
--   mysql -u koha_admin -p koha_db < UPGRADE-ks25-backup.sql

-- 1. Varakopio map_productform-taulusta
--    Configure-sivun tallennus tyhjentää taulun ja kirjoittaa sen uudelleen.
CREATE TABLE IF NOT EXISTS map_productform_backup SELECT * FROM map_productform;

-- 2. Viivakoodiseedin arvon siirto sequences -> plugin_data
--    Uusi versio lukee plugin_data.next_barcode. Kopioi arvo ennen kuin
--    uusi versio tuottaa ensimmäisen viivakoodin.
INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
SELECT 'Koha::Plugin::Fi::KohaSuomi::Editx', 'next_barcode', item_barcode_nextval
FROM sequences
ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value);