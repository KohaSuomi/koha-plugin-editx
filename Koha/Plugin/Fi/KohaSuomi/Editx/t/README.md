# EDItX Plugin Test Scripts

This directory contains test scripts and test data population utilities for the EDItX plugin.

## Files

### Main Scripts

- **`populate_test_data.pl`** - Comprehensive test data generator
  - Creates vendors, budgets, and EDItX messages
  - Supports `--clear` and `--borrowernumber` flags
  - See [TESTING.md](TESTING.md) for full documentation

- **`test_editx.pl`** - API endpoint tester
  - Tests POST, GET, PUT operations
  - Validates XML handling
  - Tests error scenarios

- **`xml_data.pl`** - Sample EDItX XML generator
  - Contains example LibraryShipNotice XML
  - Useful for manual testing

### Documentation

- **`TESTING.md`** - Complete testing guide
  - Installation and setup
  - Usage examples
  - Troubleshooting
  - Customization guide

## Quick Start

### 1. Populate Test Data

```bash
# With specific borrowernumber (recommended)
perl populate_test_data.pl --borrowernumber=42

# Or with default borrowernumber 51
perl populate_test_data.pl
```

This creates:
- **EUR currency** (if not already present)
- **3 vendors** with EDI accounts (TEST Vendor BTJ Finland, Booky, Academic Press)
- **2 budget periods** (current and next year)
- **5 funds** (TESTFUND2025, TESTLOC2025, OUPKAIK2025, etc.)
- **16 EDItX messages** (pending, processing, completed, failed scenarios)

**Note**: Baskets are created automatically by the EDItX processor when orders are processed.

### 2. Verify Test Data

```bash
# Check EUR currency
koha-mysql <instance> -e "SELECT currency, symbol, isocode FROM currency WHERE currency = 'EUR';"

# Check vendors
koha-mysql <instance> -e "SELECT name FROM aqbooksellers WHERE name LIKE 'TEST%';"

# Check vendor EDI accounts
koha-mysql <instance> -e "SELECT v.name, e.san, e.id_code_qualifier FROM aqbooksellers v JOIN vendor_edi_accounts e ON v.id=e.vendor_id WHERE v.name LIKE 'TEST%';"

# Check funds
koha-mysql <instance> -e "SELECT budget_code, budget_name FROM aqbudgets WHERE budget_code LIKE 'TEST%';"

# Check EDItX messages (by ShipNoticeNumber)
koha-mysql <instance> -e "SELECT name, status FROM koha_plugin_fi_kohasuomi_editx_contents WHERE name LIKE 'SN%';"

# After processing EDItX messages, check created baskets
koha-mysql <instance> -e "SELECT b.basketno, b.basketname, s.name as vendor FROM aqbasket b JOIN aqbooksellers s ON b.booksellerid=s.id WHERE b.basketname LIKE 'SN%' ORDER BY b.basketname;"
```

### 3. Test Plugin

1. Access Koha staff interface
2. Navigate to EDItX plugin admin
3. Process test messages
4. Verify results

### 4. Clean Up

```bash
perl populate_test_data.pl --clear
```

## Requirements

- Running Koha instance
- EDItX plugin installed
- Valid borrowernumber for budget owner (use `--borrowernumber` flag)
- Database write permissions

## Important Notes

### Budget Owner ID

Specify a valid borrowernumber when running the script:

```bash
# Find a valid borrowernumber
koha-mysql <instance> -e "SELECT borrowernumber, surname FROM borrowers LIMIT 5;"

# Use it with the --borrowernumber flag
perl populate_test_data.pl --borrowernumber=42
```

### Test Data Prefix

All test data uses predictable prefixes for easy identification and cleanup:
- Vendors: `TEST%`
- Budget periods: `TEST Budget Period%`
- Funds: `TEST%` or `%2025`
- EDItX messages: `SN%` (ShipNoticeNumbers: SN001-SN016)

## Test Scenarios

The populate script creates diverse test scenarios:

### EDItX Message Statuses
- **pending**: Fresh messages waiting to be processed
- **processing**: Messages currently being imported
- **completed**: Successfully imported messages
- **failed**: Various failure scenarios (invalid ISBN, missing fund, malformed XML, etc.)

### Edge Cases
- Unicode/special characters (Finnish Ä, Ö, Å)
- High-value items (€499.99)
- Old pending orders (1 month old)
- Multiple copies of same item
- Large batches

## Troubleshooting

### Common Issues

**"Cannot add or update a child row"**
- Use `--borrowernumber` flag with valid borrowernumber

**"Can't locate C4/Context.pm"**
- Run in Koha shell: `koha-shell <instance> -c "cd /path/to/t && perl populate_test_data.pl --borrowernumber=42"`

**"Table doesn't exist"**
- Install EDItX plugin first

**Duplicate entries**
- Clear first: `perl populate_test_data.pl --clear`

See [TESTING.md](TESTING.md) for detailed troubleshooting.

## Development

### Adding New Test Scenarios

Edit `populate_test_data.pl` and add to the appropriate section:

```perl
insert_test_record(
    'TEST_NEW_SCENARIO.xml',
    generate_editx_xml({
        ship_notice_num => 'SN999',
        isbn => '9789999999999',
        title => 'New Test Book',
        author => 'New, Author',
        fund => 'TESTFUND2025',
        price => '25.00',
    }),
    'pending',
    undef,
    undef
);
```

### Adding New Vendors

```perl
{
    name => 'TEST My Vendor',
    address1 => 'Custom Street 99',
    accountnumber => 'FI-MYVENDOR-TEST',
    notes => 'My custom test vendor',
    active => 1,
    # ... other fields like phone, postal, url, etc.
}
```

### Adding New Funds

```perl
{
    budget_code => 'TEST_MYFUND',
    budget_name => 'TEST My Custom Fund',
    budget_amount => 10000.00,
    budget_period_id => $budget_period_id,
    budget_owner_id => 51,  # Update this!
}
```

## See Also

- [EDItX Plugin README](../../../../README.md)
- [EDItX Main Plugin](../Editx.pm)
- [Import Cronjob](../cronjobs/runEditXImport.pl)

## Support

For issues or questions:
1. Check [TESTING.md](TESTING.md) troubleshooting section
2. Review Koha logs
3. Verify database permissions
4. Check that all prerequisites are installed
