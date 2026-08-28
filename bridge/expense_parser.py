"""Parse bank notification text into a structured expense record.

This is the reference implementation of the parsing rules. The iOS app ships a
Swift port (ExpenseLogger/Parsing/ExpenseParser.swift) that follows the same
algorithm and is verified against the same corpus in fixtures/samples.json.
Keep the two in sync when changing rules.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Optional

# --- currency -------------------------------------------------------------

SYMBOLS = {"$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₱": "PHP"}

ISO_CODES = [
    "EUR", "USD", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD", "SEK", "NOK", "DKK",
    "PLN", "CZK", "HUF", "RON", "TRY", "MXN", "COP", "CLP", "ARS", "PEN", "BRL",
    "UYU", "DOP", "GTQ", "CRC", "INR", "PHP", "CNY", "HKD", "SGD", "ZAR",
]

# Currencies conventionally written 1.234,56 (group '.', decimal ',').
COMMA_DECIMAL = {
    "EUR", "ARS", "BRL", "CLP", "COP", "CZK", "DKK", "HUF", "IDR", "ISK", "NOK",
    "PLN", "RON", "SEK", "TRY", "UYU", "VND", "CRC",
}


def _convention(currency: Optional[str]) -> tuple[str, str]:
    """Return (group_separator, decimal_separator) for a currency."""
    if currency in COMMA_DECIMAL:
        return (".", ",")
    return (",", ".")


# --- keyword vocabularies -------------------------------------------------

SPEND_KEYWORDS = [
    "spent", "purchase", "purchased", "paid", "payment", "charged", "charge",
    "was used", "transaction", "debit", "withdrawal", "compra", "cargo",
    "pago", "adeudo", "recibo", "domiciliado", "retirada", "gasto",
    "has realizado", "operacion", "operación",
]

CREDIT_KEYWORDS = [
    "refund", "refunded", "credited", "credit of", "reversal", "reversed",
    "abono", "abonado", "devolucion", "devolución", "ingreso", "reembolso",
]

BALANCE_KEYWORDS = [
    "balance", "saldo", "disponible", "available", "limit", "límite", "limite",
    "restante", "remaining",
]

# Merchant-introducing keywords, in priority order.
MERCHANT_KEYWORDS = [
    "at", "en", "to", "from", "a favor de", "para", "comercio", "merchant",
    "de", "in",
]

# Text that ends a merchant name.
MERCHANT_TERMINATORS = re.compile(
    r"\s+(?:was|were|on|with|using|from|por|by|con|mediante|via|el\s+d[ií]a|"
    r"tarjeta|card|ha\s+sido|han\s+sido|has\s+been|have\s+been|"
    r"en\s+(?:tu|su|la|el|nuestra)|balance|saldo|available|disponible)\b"
    r"|\.(?=\s|$)|[;\n]|\s+-\s+|\s*\|\s*",
    re.IGNORECASE,
)

# Merchant candidates that are obviously not merchants.
MERCHANT_BLOCKLIST = {
    "your account", "the account", "tu cuenta", "su cuenta", "account", "cuenta",
    "your card", "tu tarjeta", "la tarjeta", "card", "tarjeta", "us", "you",
    "your", "tu", "su", "mi", "la", "el", "los", "las", "the", "a", "an",
    "efectivo", "cash", "compra", "pago",
}

IGNORE_RULES: list[tuple[str, re.Pattern]] = [
    ("otp", re.compile(r"\b(?:c[oó]digo|code|otp|clave)\b[^\n]{0,40}?\b\d{4,8}\b", re.I)),
    ("otp", re.compile(r"\b(?:verification|verificaci[oó]n|autenticaci[oó]n|one[- ]time|un solo uso)\b", re.I)),
    ("signin", re.compile(r"\b(?:sign[- ]?in|signed in|inicio de sesi[oó]n|log[- ]?in|logged in|acceso a tu cuenta)\b", re.I)),
    ("statement", re.compile(r"\b(?:statement|extracto)\b[^\n]{0,30}\b(?:ready|available|disponible)\b", re.I)),
    ("promo", re.compile(r"\d+\s*%[^\n]{0,30}\b(?:descuento|off|cashback|dto)\b", re.I)),
    ("promo", re.compile(r"\b(?:oferta especial|promoci[oó]n|promotional)\b", re.I)),
    ("security", re.compile(r"\b(?:password|contrase[nñ]a|pin)\b[^\n]{0,30}\b(?:changed|updated|cambiad|actualizad)", re.I)),
]

# --- amount matching ------------------------------------------------------

_ISO_ALT = "|".join(ISO_CODES)
_SYM_ALT = "".join(re.escape(s) for s in SYMBOLS)
_NUM = r"\d[\d.,  ]*\d|\d"

AMOUNT_RE = re.compile(
    rf"(?:(?P<cur1>[{_SYM_ALT}])|(?<![A-Za-z])(?P<iso1>{_ISO_ALT})(?![A-Za-z]))\s*(?P<amt1>{_NUM})"
    rf"|(?P<amt2>{_NUM})\s*(?:(?P<cur2>[{_SYM_ALT}])|(?<![A-Za-z])(?P<iso2>{_ISO_ALT})(?![A-Za-z]))",
    re.IGNORECASE,
)

CARD_RE = re.compile(
    r"(?:ending(?:\s+in)?|terminada\s+en|termina\s+en|acabada\s+en|final|ending\s+with|"
    r"\*+|x{2,}|X{2,}|•{2,})\s*(\d{4})\b",
    re.IGNORECASE,
)


def _normalize_amount(raw: str, currency: Optional[str]) -> Optional[Decimal]:
    s = raw.replace(" ", "").replace(" ", "").strip()
    if not s:
        return None
    group_sep, _ = _convention(currency)
    has_dot, has_comma = "." in s, "," in s
    if has_dot and has_comma:
        dec = "." if s.rfind(".") > s.rfind(",") else ","
        grp = "," if dec == "." else "."
        s = s.replace(grp, "").replace(dec, ".")
    elif has_dot or has_comma:
        sep = "." if has_dot else ","
        parts = s.split(sep)
        if len(parts) > 2:
            s = s.replace(sep, "")          # 1.234.567 -> grouping
        else:
            tail = parts[1]
            if len(tail) == 3:
                # Ambiguous (1,234 / 1.234): grouping if it matches the
                # currency's own convention, otherwise a decimal separator.
                s = s.replace(sep, "") if sep == group_sep else s.replace(sep, ".")
            elif len(tail) in (1, 2):
                s = s.replace(sep, ".")     # decimal
            else:
                s = s.replace(sep, "")      # grouping
    try:
        return Decimal(s)
    except InvalidOperation:
        return None


@dataclass
class AmountCandidate:
    value: Decimal
    currency: Optional[str]
    explicit_currency: bool
    start: int
    end: int
    score: float = 0.0


def _find_amounts(text: str, default_currency: str) -> list[AmountCandidate]:
    out: list[AmountCandidate] = []
    lowered = text.lower()
    for m in AMOUNT_RE.finditer(text):
        sym = m.group("cur1") or m.group("cur2")
        iso = m.group("iso1") or m.group("iso2")
        raw = m.group("amt1") if m.group("amt1") is not None else m.group("amt2")
        if raw is None:
            continue
        currency = SYMBOLS.get(sym) if sym else (iso.upper() if iso else None)
        value = _normalize_amount(raw, currency)
        if value is None:
            continue
        cand = AmountCandidate(
            value=value,
            currency=currency or default_currency,
            explicit_currency=currency is not None,
            start=m.start(),
            end=m.end(),
        )
        # Prefer amounts introduced by spending language, demote balances.
        window = lowered[max(0, m.start() - 45): m.start()]
        if any(k in window for k in BALANCE_KEYWORDS):
            cand.score -= 2.0
        if any(k in window for k in SPEND_KEYWORDS + CREDIT_KEYWORDS):
            cand.score += 1.0
        cand.score -= m.start() / 10000.0   # tie-break toward the earliest
        out.append(cand)
    return out


def _clean_merchant(raw: str) -> str:
    cut = MERCHANT_TERMINATORS.search(raw)
    if cut:
        raw = raw[: cut.start()]
    raw = raw.strip().strip(",;:·-—– \t")
    raw = re.sub(r"\s+", " ", raw)
    return raw[:60].strip()


def _find_merchant(text: str, after: int) -> tuple[Optional[str], bool]:
    """Return (merchant, found_via_keyword). Searches after the amount first."""
    for region_start in (after, 0):
        region = text[region_start:]
        for kw in MERCHANT_KEYWORDS:
            for m in re.finditer(rf"(?<!\w){re.escape(kw)}\s+", region, re.IGNORECASE):
                candidate = _clean_merchant(region[m.end():])
                if not candidate or candidate.lower() in MERCHANT_BLOCKLIST:
                    continue                    # keep scanning this keyword
                if re.fullmatch(r"[\d.,\s]+", candidate):
                    continue
                return candidate, True
        # Fallback: a run of capitalised/upper tokens (typical of card networks).
        caps = re.findall(r"\b[A-Z0-9][A-Z0-9&.'*/-]{2,}(?:\s+[A-Z0-9][A-Z0-9&.'*/-]*){0,3}", region)
        for c in caps:
            if c.lower() in MERCHANT_BLOCKLIST or c.upper() in {u.upper() for u in ISO_CODES}:
                continue
            return _clean_merchant(c), False
    return None, False


@dataclass
class ParsedExpense:
    kind: str                       # expense | credit | ignored | unparsed
    raw: str
    received_at: datetime
    source: Optional[str] = None
    amount: Optional[Decimal] = None
    currency: Optional[str] = None
    merchant: Optional[str] = None
    card: Optional[str] = None
    confidence: float = 0.0
    reason: Optional[str] = None
    tags: list[str] = field(default_factory=list)

    @property
    def signed_amount(self) -> Optional[Decimal]:
        if self.amount is None:
            return None
        return self.amount if self.kind == "credit" else -self.amount

    def dedupe_key(self) -> str:
        basis = f"{self.amount}|{self.currency}|{self.merchant}|{self.raw.strip()}"
        return hashlib.sha1(basis.encode("utf-8")).hexdigest()[:16]


def parse(
    text: str,
    source: Optional[str] = None,
    received_at: Optional[datetime] = None,
    default_currency: str = "EUR",
) -> ParsedExpense:
    received_at = received_at or datetime.now(timezone.utc).astimezone()
    raw = text.strip()
    result = ParsedExpense(kind="unparsed", raw=raw, received_at=received_at, source=source)
    if not raw:
        result.reason = "empty"
        return result

    lowered = raw.lower()

    for name, rule in IGNORE_RULES:
        if rule.search(raw):
            result.kind = "ignored"
            result.reason = name
            return result

    has_spend = any(k in lowered for k in SPEND_KEYWORDS)
    has_credit = any(k in lowered for k in CREDIT_KEYWORDS)
    if not has_spend and not has_credit and any(k in lowered for k in BALANCE_KEYWORDS):
        result.kind = "ignored"
        result.reason = "balance"
        return result

    candidates = _find_amounts(raw, default_currency)
    if not candidates:
        result.reason = "no-amount"
        return result
    best = max(candidates, key=lambda c: c.score)
    if not best.explicit_currency and not (has_spend or has_credit):
        result.reason = "no-currency"
        return result

    merchant, via_keyword = _find_merchant(raw, best.end)
    card_match = CARD_RE.search(raw)

    result.kind = "credit" if has_credit else "expense"
    result.amount = best.value
    result.currency = best.currency
    result.merchant = merchant
    result.card = card_match.group(1) if card_match else None

    confidence = 0.5
    if best.explicit_currency:
        confidence += 0.2
    if merchant:
        confidence += 0.2 if via_keyword else 0.1
    if result.card:
        confidence += 0.1
    if has_spend or has_credit:
        confidence += 0.1
    result.confidence = min(1.0, round(confidence, 2))
    return result


# --- output formats -------------------------------------------------------

def _csv_escape(value: str) -> str:
    if any(c in value for c in ',"\n'):
        return '"' + value.replace('"', '""') + '"'
    return value


def format_line(exp: ParsedExpense, fmt: str = "tsv") -> str:
    ts = exp.received_at.isoformat(timespec="seconds")
    amount = f"{exp.signed_amount:.2f}" if exp.signed_amount is not None else ""
    fields = [
        ts, amount, exp.currency or "", exp.merchant or "", exp.card or "",
        exp.source or "", f"{exp.confidence:.2f}",
        re.sub(r"\s+", " ", exp.raw),
    ]
    if fmt == "tsv":
        return "\t".join(f.replace("\t", " ") for f in fields)
    if fmt == "csv":
        return ",".join(_csv_escape(f) for f in fields)
    if fmt == "jsonl":
        return json.dumps({
            "timestamp": ts,
            "amount": float(exp.signed_amount) if exp.signed_amount is not None else None,
            "currency": exp.currency,
            "merchant": exp.merchant,
            "card": exp.card,
            "source": exp.source,
            "kind": exp.kind,
            "confidence": exp.confidence,
            "raw": exp.raw,
        }, ensure_ascii=False)
    if fmt == "plain":
        sym = next((s for s, c in SYMBOLS.items() if c == exp.currency), "")
        money = f"{sym}{exp.amount}" if sym else f"{exp.amount} {exp.currency or ''}".strip()
        parts = [exp.received_at.strftime("%Y-%m-%d %H:%M"), "—", money, exp.merchant or "?"]
        if exp.card:
            parts.append(f"(*{exp.card})")
        return " ".join(parts)
    raise ValueError(f"unknown format: {fmt}")


HEADERS = {
    "tsv": "timestamp\tamount\tcurrency\tmerchant\tcard\tsource\tconfidence\traw",
    "csv": "timestamp,amount,currency,merchant,card,source,confidence,raw",
}
