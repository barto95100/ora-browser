#!/usr/bin/env python3
"""Adds French translations to the catalog.

Usage: add-translations.py <Localizable.xcstrings> <translations.json> [language]
The JSON maps an English text to its translation (French by default; "en"
for the English forms of a plural), or to {"one": …, "other": …} for a
number (plural). Existing translations are replaced.
"""

import json
import sys
from pathlib import Path


def main():
    catalog_path, table_path = Path(sys.argv[1]), Path(sys.argv[2])
    catalog = json.loads(catalog_path.read_text())
    table = json.loads(table_path.read_text())
    language = sys.argv[3] if len(sys.argv) > 3 else "fr"
    strings = catalog["strings"]
    missing = []
    for english, translation in table.items():
        if english not in strings:
            missing.append(english)
            continue
        if isinstance(translation, dict):
            plural = {form: {"stringUnit": {"state": "translated", "value": text}} for form, text in translation.items()}
            localization = {"variations": {"plural": plural}}
        else:
            localization = {"stringUnit": {"state": "translated", "value": translation}}
        strings[english].setdefault("localizations", {})[language] = localization
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")
    for english in missing:
        print(f"not in the catalog: {english!r}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
