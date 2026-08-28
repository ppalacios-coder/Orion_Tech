# How parsing works, and how to tune it

The rules live in two places that must stay in step:

- `ExpenseLogger/Parsing/ExpenseParser.swift` — used by the app.
- `bridge/expense_parser.py` — used by the Mac bridge, and the reference
  implementation.

Both are tested against `fixtures/samples.json`.

## The pipeline

1. **Ignore rules.** One-time codes, sign-in alerts, statement notices, password
   changes and percentage-off promotions are dropped before anything else. This
   is what keeps a passcode SMS out of your expense log.
2. **Balance-only check.** Text mentioning a balance but no spending is ignored.
3. **Amount candidates.** Every currency-and-number pair is found, then scored:
   an amount preceded by spending language scores up, one preceded by *balance*,
   *saldo*, *disponible* or *available* scores down. The winner is used — this
   is why `You spent $12.00 at CVS. Available balance: $1,203.11` logs `12.00`.
4. **Number normalisation.** `1.234,56` and `1,234.56` both become `1234.56`.
   For genuinely ambiguous forms like `1.500`, the currency decides: EUR groups
   with `.`, so it reads as fifteen hundred.
5. **Merchant.** Searched after the amount first (`…€45,20 **en MERCADONA**`),
   then anywhere. Filler like *your card* / *tu cuenta* is rejected, and the
   name is cut at words that end it (`with`, `con`, `on`, a sentence-ending
   full stop). Failing that, a run of upper-case words is used.
6. **Card digits, direction, confidence.** Refunds become positive amounts.
   Confidence rises with an explicit currency, a keyword-found merchant, and
   card digits.

Anything below the confidence threshold (Settings, default 0.50) goes to
`expenses.review.txt` instead of the log. Nothing is silently discarded.

## Notifications with no wording

Card issuers often post through Apple Wallet, which uses Apple's three-part
layout and no sentence at all:

```
Banco Industrial      title    — the issuer
Circus Coffee         subtitle — the merchant
GTQ 26.00             body     — the amount
```

Two mechanisms cover this, tried before any keyword matching:

1. **The subtitle**, when the parts are known separately. `parse_notification`
   (Python) / `ExpenseParser.parse(title:subtitle:body:)` (Swift) take it as the
   merchant directly. The Mac bridge uses this path. A subtitle that is only an
   amount is ignored.
2. **The layout**, when all you have is the text. If the amount occupies a line
   by itself, the merchant is the last meaningful line above it; line 0 is
   skipped as the issuer name, and blank, amount-only and timestamp lines
   ("31m ago", "Yesterday, 6:16 PM") are passed over. A candidate line that
   contains spending wording is left to the keyword extractor instead, so
   sentence-style alerts are unaffected.

If there is no subtitle at all, the result has no merchant rather than a wrong
one — the issuer name is never used as a merchant.

## Guatemala specifics

`Q` is treated as a currency symbol mapping to GTQ, with two rules that matter:

- It is a **letter**, so it only counts as currency when not preceded by another
  letter — `REQ12345` is not two hundred quetzales. It may be followed by a full
  stop, because `Q. 45.00` is common.
- GTQ is **not** in `commaDecimal`, so it uses US-style separators:
  `Q1,234.56` is one thousand two hundred, and `Q1.500` would be one and a half.

`US$25.00` resolves to USD rather than GTQ, because `$` matches ahead of any
default, which keeps dollar-account alerts correct.

Card digits are looked up twice: first by a pattern anchored on the word
*tarjeta* or *card*, then by a looser one. That ordering is what stops
`cuenta *4567, tarjeta terminación 1234` from logging the account number.

## Tuning it for your bank

Use the **Test** tab first: paste a real notification and read the result and
the exact line it would write.

**Merchant comes out wrong or truncated.** Add the word your bank uses to
`merchantKeywords` (Swift) / `MERCHANT_KEYWORDS` (Python), or add the word that
should end the name to `merchantTerminators` / `MERCHANT_TERMINATORS`.

**The balance is being logged instead of the amount.** Add your bank's word for
balance to `balanceKeywords` / `BALANCE_KEYWORDS`.

**Something is logged that should not be.** Add a pattern to `ignoreRules` /
`IGNORE_RULES`. Keep it specific — an over-broad rule silently drops real
expenses.

**Refunds show as spending.** Add your bank's word to `creditKeywords` /
`CREDIT_KEYWORDS`.

**A currency is misread.** Add the ISO code to `isoCodes` / `ISO_CODES`, and to
`commaDecimal` / `COMMA_DECIMAL` if it is written `1.234,56`.

## Adding a test case

Whenever you change a rule, add the notification that motivated it to
`fixtures/samples.json`:

```json
{
  "id": "mybank-contactless",
  "text": "MyBank: Pago contactless 4,50 EUR en PANADERIA SOL",
  "expect": { "kind": "expense", "amount": "4.50", "currency": "EUR", "merchant": "PANADERIA SOL" }
}
```

Then run both suites — the corpus is shared, so a change that only fixes one
implementation will fail in the other:

```bash
python3 -m unittest discover -s bridge -t bridge
xcodebuild test -scheme ExpenseLogger -destination 'platform=iOS Simulator,name=iPhone 16'
```

`kind` is one of `expense`, `credit`, `ignored` or `unparsed`. Only `amount`,
`currency`, `merchant` and `card` are optional — supply the ones that matter.

## Sensible privacy note

The `raw` column keeps the original notification text, which is what makes a
mis-parse diagnosable later. If you would rather not keep it, drop the last
field in `LogLine.render` and `format_line`.
