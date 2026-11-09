#!/usr/bin/env python3
"""Adds French translations to the catalog.

Usage: add-translations.py <Localizable.xcstrings> <translations.json>
The JSON maps an English text to its French one, or to {"one": …, "other": …}
for a number (plural). Existing translations are replaced.
"""

import json
import sys
from pathlib import Path


def main():
    catalog_path, table_path = Path(sys.argv[1]), Path(sys.argv[2])
    catalog = json.loads(catalog_path.read_text())
    table = json.loads(table_path.read_text())
    strings = catalog["strings"]
    missing = []
    for english, french in table.items():
        if english not in strings:
            missing.append(english)
            continue
        if isinstance(french, dict):
            plural = {form: {"stringUnit": {"state": "translated", "value": text}} for form, text in french.items()}
            localization = {"variations": {"plural": plural}}
        else:
            localization = {"stringUnit": {"state": "translated", "value": french}}
        strings[english].setdefault("localizations", {})["fr"] = localization
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")
    for english in missing:
        print(f"not in the catalog: {english!r}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
