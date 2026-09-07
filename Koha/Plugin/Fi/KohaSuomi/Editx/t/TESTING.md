# EDItX Test Data Population Script

## Overview

The `populate_test_data.pl` script creates comprehensive test data for the EDItX plugin, including:
- **Vendors** in Koha's acquisitions system (aqbooksellers)
- **Budget periods** (aqbudgetperiods)
- **Funds/Budgets** (aqbudgets)
- **EDItX shipment notices** covering various real-world scenarios

## Usage

### Basic Usage

```bash
cd Koha/Plugin/Fi/KohaSuomi/Editx/t
perl populate_test_data.pl
```

This will create all test data using default borrowernumber 51.

### Specify Borrowernumber

```bash
perl populate_test_data.pl --borrowernumber=42
```

Use a valid borrowernumber from your Koha instance as the budget owner.

### Clear Existing Test Data

```bash
perl populate_test_data.pl --clear
```

This will remove all existing test records before populating new data.

### Combined Options

```bash
perl populate_test_data.pl --clear --borrowernumber=99
```

Clear existing data and create new data with specified borrowernumber.

### Get Help

```bash
perl populate_test_data.pl --help
```

## Test Data Created

### 1. CURRENCY (EUR in `currency` table)

The script ensures EUR currency exists for order processing. If EUR already exists in your Koha instance, it will not be modified.

### 2. BRANCH (CPL in `branches` table)

The script ensures CPL (Central Library) branch exists. If CPL already exists, it will not be modified.

### 3. LOCATION (AIK in `authorised_values` table)

The script ensures AIK (General Collection) location exists in LOC category. If AIK already exists, it will not be modified.

### 4. VENDORS (3 records in `aqbooksellers` + EDI accounts in `vendor_edi_accounts`)

- **TEST Vendor BTJ Finland** (FI-BTJ-TEST, SAN: 12345)
- **TEST Vendor Booky** (FI-BOOKY-TEST, SAN: 23456)
- **TEST Vendor Academic Press** (FI-ACADEMIC-TEST, SAN: 34567)

All vendors include contact information, URLs, are set as active, and have corresponding EDI accounts configured for FILE transport with orders enabled.

**NOTE**: Baskets are created automatically by the EDItX processor when processing orders. The basket name will match the ShipNoticeNumber from the EDItX message.

### 5. BUDGET PERIODS (2 records in `aqbudgetperiods`)

- **TEST Budget Period [Current Year]** - €100,000 total
- **TEST Budget Period [Next Year]** - €120,000 total

### 6. FUNDS/BUDGETS (5 records in `aqbudgets`)

| Fund Code | Fund Name | Amount |
|-----------|-----------|--------|
| TESTFUND2025 | TEST General Acquisitions Fund | €50,000 |
| TESTLOC2025 | TEST Location-specific Fund | €20,000 |
| OUPKAIK2025 | TEST OUP KAIK Fund | €15,000 |
| TEST_CHILDREN | TEST Children's Books Fund | €10,000 |
| TEST_ACADEMIC | TEST Academic Books Fund | €30,000 |

### 7. EDITX MESSAGES (16 XML records)

Each record is stored with its ShipNoticeNumber (SN001-SN016) in the database name column.

#### PENDING (3 records)
- **SN001** - Single book order (€15.50)
- **SN002** - 5 copies of same book (€22.00)
- **SN003** - Expensive academic book (€95.00)

#### PROCESSING (2 records)
- **SN004** - Currently being imported (5 min ago)
- **SN005** - 10 items batch (15 min ago)

#### COMPLETED (3 records)
- **SN006** - Imported 2 hours ago
- **SN007** - Imported 5 hours ago
- **SN008** - Completed yesterday

#### FAILED (5 records)
- **SN009** - Invalid ISBN format error
- **SN010** - Non-existent fund reference
- **SN011** - Malformed XML structure
- **SN012** - Duplicate shipment notice
- **SN013** - Network timeout

#### EDGE CASES (3 records)
- **SN014** - Finnish special characters (Ä, Ö, Å)
- **SN015** - High-value collector item (€499.99)
- **SN016** - 1-month-old pending order

## Requirements

### Perl Modules
- `Modern::Perl`
- `C4::Context`
- `DateTime`

### Database Access
- Running Koha instance with database configured
- Write permissions to acquisitions tables

### Important: Budget Owner

The script uses borrowernumber 51 as the **default** budget owner. You should specify a valid borrowernumber from your Koha instance using the `--borrowernumber` flag.

#### Find Valid Borrower IDs

```bash
mysql -e "SELECT borrowernumber, surname, firstname FROM borrowers WHERE flags > 0 LIMIT 10;"
```

Or in SQL:

```sql
SELECT borrowernumber, surname, firstname FROM borrowers WHERE flags > 0 LIMIT 10;
```

#### Use the Flag

Once you have a valid borrowernumber, use it with the `--borrowernumber` flag:

```bash
perl populate_test_data.pl --borrowernumber=42
```

The script will validate that the borrowernumber exists before creating budgets and will show a warning if it doesn't.

## Database Tables

The script populates these tables:

| Table | Records | Purpose |
|-------|---------|---------|
| `aqbooksellers` | 3 | Vendors for acquisitions |
| `aqbudgetperiods` | 2 | Budget time periods |
| `aqbudgets` | 5 | Funds for purchasing |
| `koha_plugin_fi_kohasuomi_editx_contents` | 16 | EDItX messages |

## Testing Workflow

### 1. Prepare Environment

```bash
# Ensure you're in the plugin test directory
cd Koha/Plugin/Fi/KohaSuomi/Editx/t

# Find a valid borrowernumber
mysql -e "SELECT borrowernumber, surname FROM borrowers LIMIT 5;"
```

### 2. Populate Test Data

```bash
# With specific borrowernumber (recommended)
perl populate_test_data.pl --borrowernumber=42

# Or with default borrowernumber 51
perl populate_test_data.pl
```

Expected output:
```
Creating test vendors...
  Created vendor: TEST Vendor BTJ Finland (ID: XXX)
  Created vendor: TEST Vendor Booky (ID: XXX)
  Created vendor: TEST Vendor Academic Press (ID: XXX)

Creating test budget periods...
  Created budget period: TEST Budget Period 2026 (ID: XXX)
  Created budget period: TEST Budget Period 2027 (ID: XXX)

Creating test budgets/funds...
  Using borrowernumber 42 as budget owner
  Created fund: TESTFUND2025 - TEST General Acquisitions Fund (ID: XXX)
  ...

Populating test data...
Creating PENDING test records...
  Inserted: SN001 (status: pending)
  ...

============================================================
Test data population completed!
============================================================
```

### 3. Verify Data

```bash
"SELECT id, name, accountnumber FROM aqbooksellers WHERE name LIKE 'TEST%';"

"SELECT budget_id, budget_code, budget_name, budget_amount FROM aqbudgets WHERE budget_code LIKE 'TEST%' OR budget_code LIKE '%2025';"

"SELECT id, name, status FROM koha_plugin_fi_kohasuomi_editx_contents WHERE name LIKE 'SN%';"
```

### 4. Test Plugin

1. Access Koha staff interface
2. Navigate to **Acquisitions**
3. Verify test vendors appear in vendor list
4. Check that test funds are available for ordering
5. Access **EDItX plugin admin interface**
6. Process pending EDItX messages
7. Verify completed/failed statuses

### 5. Clean Up

```bash
perl populate_test_data.pl --clear
```

## Sample XML Structure

Each EDItX message contains:

```xml
<LibraryShipNotice version="1.0">
  <Header>
    <ShipNoticeNumber>...</ShipNoticeNumber>
    <BuyerParty>...</BuyerParty>
    <SellerParty>...</SellerParty>
  </Header>
  <ItemDetail>
    <ProductID>...</ProductID>
    <ItemDescription>...</ItemDescription>
    <PricingDetail>...</PricingDetail>
    <CopyDetail>
      <FundDetail>
        <FundNumber>TESTFUND2025</FundNumber>
      </FundDetail>
      <Message>
        <!-- Embedded MARC21 record -->
      </Message>
    </CopyDetail>
  </ItemDetail>
</LibraryShipNotice>
```

## Customization

### Add Custom Vendor

Edit the script and add to the `@vendors` array in `create_test_vendors()`:

```perl
{
    name => 'TEST My Custom Vendor',
    address1 => 'Custom Street 99',
    accountnumber => 'FI-CUSTOM-TEST',
    notes => 'My custom test vendor',
    active => 1,
    # ... other fields like phone, postal, url, etc.
}
```

### Add Custom Fund

Edit the script and add to the `@budgets` array in `create_test_budgets()`:

```perl
{
    budget_code => 'TEST_CUSTOM',
    budget_name => 'TEST Custom Fund',
    budget_amount => 25000.00,
    budget_period_id => $budget_period_id,
    budget_owner_id => $owner_id,  # Uses the parameter passed to function
    budget_notes => 'Custom test fund',
}
```

Note: The `$owner_id` parameter comes from the function argument, which is set by the `--borrowernumber` flag.

### Add Custom EDItX Message

```perl
insert_test_record(
    'TEST_MY_SCENARIO.xml',
    generate_editx_xml({
        ship_notice_num => 'SN999',
        isbn => '9789511234599',
        title => 'My Test Book',
        author => 'Custom, Author',
        fund => 'TEST_CUSTOM',  # Use custom fund
        price => '30.00',
    }),
    'pending',
    undef,
    undef
);
```

## Troubleshooting

### "DBD::mysql::st execute failed: Cannot add or update a child row"

**Problem**: Budget owner (borrowernumber) doesn't exist

**Solution**: Use the `--borrowernumber` flag with a valid borrowernumber

```bash
# Find valid borrowernumber
mysql -e "SELECT borrowernumber, surname FROM borrowers LIMIT 5;"

# Run script with valid borrowernumber
perl populate_test_data.pl --borrowernumber=42
```

### "Can't locate C4/Context.pm"

**Problem**: Not running in Koha environment

**Solution**: Use koha-shell or set PERL5LIB:

```bash
koha-shell <instance> -c "cd /path/to/t && perl populate_test_data.pl --borrowernumber=42"
```

### "Table 'koha_plugin_fi_kohasuomi_editx_contents' doesn't exist"

**Problem**: EDItX plugin not installed

**Solution**: Install the EDItX plugin first through Koha's plugin interface

### No funds created but no error

**Problem**: Budget period creation failed silently

**Solution**: Check that budget period was created:

```bash
mysql -e "SELECT * FROM aqbudgetperiods WHERE budget_period_description LIKE 'TEST%';"
```

### Duplicate entry errors when re-running

**Problem**: Test data already exists

**Solution**: Clear first:

```bash
perl populate_test_data.pl --clear
perl populate_test_data.pl
```

## Integration with EDItX Processing

After populating test data, you can process the messages:

```bash
# Run EDItX import cron job manually
cd Koha/Plugin/Fi/KohaSuomi/Editx/crontabs
perl process_editx_contents.pl
```

## See Also

- [EDItX Plugin README](../../../../../README.md)
- [EDItX Plugin Main File](../Editx.pm)
- [EDItX Test Script](test_editx.pl)
- [EDItX Import Cronjob](../cronjobs/runEditXImport.pl)

## Author

Generated for Koha-Suomi EDItX plugin testing

## License

Same as the EDItX plugin (see LICENSE file)
