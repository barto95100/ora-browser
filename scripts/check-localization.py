#!/usr/bin/env python3
"""Lists the interface's texts without a French translation.

Usage: check-localization.py <derived data> <Localizable.xcstrings> [--all]

Reads what the compiler found to translate (`.stringsdata`, written by
`xcodebuild -exportLocalizations`, which also adds the new texts to the
catalog) and reports, for the translated zones (`ZONES`, or every file with
--all):
- a text without a French translation, or whose French one lost a
  placeholder (%@, %lld…);
- a text written in the code that the compiler can't see (a `String` given
  to AppKit, an error message…): wrap it in `String(localized:)`, or end the
  line with `// not shown` when it never reaches the screen;
- a text the catalog still has but the code no longer uses (stale).
Exits with 1 when something is reported.
"""

import json
import re
import sys
from pathlib import Path

# Translated zones (a pull request per zone): files or folders, from the root.
ZONES = {
    "menus": [
        "Ombre/App/",
        "Ombre/Features/Browser/",
        "Ombre/Features/FindInPage/",
    ],
}

ROOT = Path(__file__).resolve().parent.parent
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:arg|lld|ld|d|@|f|\.\d+f|%)")
# A text for people: a word of 2+ letters, and a space or a capital first.
PROSE = re.compile(r"^(?=.*[A-Za-z]{2})(?:[A-Z]|.*\s)")
# An enum's raw value shown as is: saved text, never translated.
RAW_VALUE = re.compile(r"\b(?:Text|Label|Button|title:)\(?[^\"]*\.rawValue\b")
# Lines whose texts never reach the screen.
NOT_SHOWN = re.compile(
    r"// not shown|// no translation|logger\.|Logger\(|log\.|print\(|fatalError\(|precondition|assert|"
    r"forKey:|@AppStorage|@SceneStorage|UserDefaults|Notification\.Name|"
    r"systemName:|systemImage:|systemSymbolName:|named:|URL\(string:|"
    r"#Preview|#selector|NSPredicate|evaluateJavaScript|callAsyncJavaScript|"
    r"\.accessibilityIdentifier|identifier:|windowID|openWindow\(id:|"
    r"Text\(verbatim:|LocalizedStringKey|String\(localized:|localized:|"
    r"case \w+ = |static let \w+ = \"|userInfo:|forHTTPHeaderField:|"
    r"UTType|\.json|\.plist|NSPasteboard|contentType"
)


def bare(text: str) -> str:
    """The text without its placeholders or interpolations."""
    return PLACEHOLDER.sub("", re.sub(r"\\\(.*?\)", "", text))


def shape(text: str) -> str:
    return PLACEHOLDER.sub("%arg", text)


def in_zone(path: str, every: bool) -> bool:
    if every:
        return path.startswith("Ombre/")
    return any(path.startswith(prefix) for files in ZONES.values() for prefix in files)


def read_extracted(derived: Path):
    """(file, line, column) of each text the compiler extracted, and its key."""
    found = {}
    for data in derived.glob("Localization/Strings/*Ombre.xcodeproj-Ombre-*/**/*.stringsdata"):
        content = json.loads(data.read_text())
        source = Path(content["source"])
        try:
            path = str(source.relative_to(ROOT))
        except ValueError:
            continue
        for entry in content.get("tables", {}).get("Localizable", []):
            where = entry["location"]
            found.setdefault(path, {})[(where["startingLine"], where["startingColumn"])] = entry["key"]
    return found


def check_catalog(catalog, extracted, every):
    problems = []
    strings = catalog["strings"]
    for key, item in strings.items():
        if item.get("extractionState") == "stale":
            problems.append(f"stale in the catalog (no longer in the code): {key!r}")
    # The parser writes %arg where the catalog has %lld, %@…
    by_shape = {shape(key): item for key, item in strings.items()}
    seen = set()
    for path, entries in sorted(extracted.items()):
        if not in_zone(path, every):
            continue
        for (line, _), key in sorted(entries.items()):
            if key in seen or not PROSE.search(key):
                continue
            seen.add(key)
            item = strings.get(key) or by_shape.get(shape(key), {})
            if item.get("shouldTranslate") is False:
                continue
            french = item.get("localizations", {}).get("fr", {})
            unit = french.get("stringUnit")
            variations = french.get("variations")
            if variations:
                values = [v["stringUnit"]["value"] for kind in variations.values() for v in kind.values()]
            elif unit and unit.get("state") == "translated":
                values = [unit["value"]]
            else:
                problems.append(f"{path}:{line}: no French: {key!r}")
                continue
            wanted = sorted(PLACEHOLDER.findall(key))
            for value in values:
                if sorted(PLACEHOLDER.findall(value)) != wanted and "%#@" not in value:
                    problems.append(f"{path}:{line}: placeholders differ in French: {key!r} -> {value!r}")
    return problems


def check_sources(extracted, every):
    problems = []
    for source in sorted((ROOT / "Ombre").rglob("*.swift")):
        path = str(source.relative_to(ROOT))
        if not in_zone(path, every):
            continue
        known = extracted.get(path, {})
        # A text chosen in an expression is found at the expression's place.
        lines = {}
        for (line, _), key in known.items():
            lines.setdefault(line, set()).add(bare(key))
        in_block = False
        for number, line in enumerate(source.read_text().splitlines(), start=1):
            # Multi-line literals hold scripts and pages, not interface texts.
            if line.count('"""') % 2 == 1:
                in_block = not in_block
                continue
            if in_block or line.lstrip().startswith("//") or NOT_SHOWN.search(line):
                continue
            if RAW_VALUE.search(line):
                problems.append(f"{path}:{number}: raw value shown (give it a translated title): {line.strip()}")
            for match in LITERAL.finditer(line):
                text = match.group(1)
                if not PROSE.search(re.sub(r"\\\(.*?\)", "", text)):
                    continue
                if (number, match.start() + 1) in known or bare(text) in lines.get(number, set()):
                    continue
                problems.append(f"{path}:{number}: not translatable: \"{text}\"")
    return problems


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    derived, catalog_path = Path(sys.argv[1]), Path(sys.argv[2])
    every = "--all" in sys.argv
    extracted = read_extracted(derived)
    if not extracted:
        print("No .stringsdata found: run xcodebuild -exportLocalizations first.")
        return 2
    catalog = json.loads(catalog_path.read_text())
    problems = check_catalog(catalog, extracted, every) + check_sources(extracted, every)
    for problem in problems:
        print(problem)
    zones = "every file" if every else ", ".join(ZONES)
    print(f"{len(problems)} text(s) to translate ({zones}).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
