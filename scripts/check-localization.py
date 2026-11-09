#!/usr/bin/env python3
"""Lists the interface's texts without a French translation.

Usage: check-localization.py <derived data> <Localizable.xcstrings> [--all] [--committed <catalog>]

Reads what the compiler found to translate (`.stringsdata`, written by
`xcodebuild -exportLocalizations`, which also adds the new texts to the
catalog) and reports, for the translated zones (`ZONES`, or every file with
--all):
- a text without a French translation, or whose French one lost a
  placeholder (%@, %lld…);
- a text written in the code that the compiler can't see (a `String` given
  to AppKit, an error message…): wrap it in `String(localized:)`, or end the
  line with `// not shown` when it never reaches the screen;
- a text the catalog still has but the code no longer uses (stale);
- with --committed, a text of the code missing from that catalog (the CI
  passes the committed one: the export adds the new texts to the file).
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
        "Ombre/Shared/Components/Dialog/",
        "Ombre/Core/Utilities/ClipboardUtils.swift",
    ],
    "onboarding": [
        "Ombre/Features/Onboarding/",
        "Ombre/Features/Importer/",
    ],
    "sidebar": [
        "Ombre/Features/Sidebar/",
        "Ombre/Features/Tabs/",
        "Ombre/Features/Launcher/",
        "Ombre/Features/Peek/",
        "Ombre/Features/Search/",
        "Ombre/Features/Player/",
    ],
    "settings": [
        "Ombre/Features/Settings/",
        "Ombre/Core/Constants/KeyboardShortcuts.swift",
        "Ombre/Core/Utilities/SettingsStore.swift",
    ],
}

ROOT = Path(__file__).resolve().parent.parent
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:arg|ll[du]|l[du]|lf|[du@f]|\.\d+f|%)")
# A text for people: a word of 2+ letters, and a space or a capital first.
PROSE = re.compile(r"^(?=.*[A-Za-z]{2})(?:[A-Z]|.*\s)")
# An enum's raw value shown as is: saved text, never translated.
RAW_VALUE = re.compile(
    r"\b(?:Text|Label|Button|title:|help|accessibilityLabel)\(?[^\"]*\.rawValue\b|\\\([^()\"]*\.rawValue\)"
)
# Lines whose texts never reach the screen.
NOT_SHOWN = re.compile(
    r"// not shown|// no translation|\blogger\.|\bLogger\(|\bprint\(|\bfatalError\(|\bprecondition|\bassert|"
    r"#Preview|#selector|NSPredicate|evaluateJavaScript|callAsyncJavaScript|case \w+ = \""
)
# A text given to one of these is a name or a key, not shown: only it is skipped.
NOT_SHOWN_ARGUMENT = re.compile(
    r"(?:forKey|systemName|systemImage|systemSymbolName|named|identifier|id|forHTTPHeaderField|"
    r"forResource|ofType|withExtension|contentType|userInfo|verbatim|localized|defaultValue)\s*:\s*"
    r'"(?:[^"\\\n]|\\.)*"'
    r"|(?:@AppStorage\(|@SceneStorage\(|Notification\.Name\(|URL\(string:|UTType\(|"
    r"NSPasteboard\.PasteboardType\(|\.accessibilityIdentifier\()\s*"
    r'"(?:[^"\\\n]|\\.)*"'
    r"|(?:saveOrLog|subfolder)\(\s*\"(?:[^\"\\\n]|\\.)*\""
    r"|static let \w+ = \"(?:[^\"\\\n]|\\.)*\""
)


def bare(text: str) -> str:
    """The text without its placeholders or interpolations."""
    return PLACEHOLDER.sub("", re.sub(r"\\\(.*?\)", "", text))


def blank(match) -> str:
    """Spaces in place of a skipped text: the other texts keep their column."""
    return " " * len(match.group(0))


def code_part(line: str) -> str:
    """The line without its trailing comment (a // outside a string)."""
    in_string = escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = not in_string
        elif not in_string and line.startswith("//", index):
            return line[:index]
    return line


def placeholders(text: str) -> list:
    """The placeholders' kinds, positions aside (%1$@ is a %@)."""
    return sorted(re.sub(r"%\d+\$", "%", found) for found in PLACEHOLDER.findall(text))


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
        # Left by a file since removed or renamed (the folder is kept).
        if not source.exists():
            continue
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
            wanted = placeholders(key)
            for value in values:
                if placeholders(value) != wanted and "%#@" not in value:
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
            for match in LITERAL.finditer(NOT_SHOWN_ARGUMENT.sub(blank, code_part(line))):
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
    if "--committed" in sys.argv:
        # The catalog as committed, before the export added the code's new texts.
        committed = json.loads(Path(sys.argv[sys.argv.index("--committed") + 1]).read_text())["strings"]
        for key, item in sorted(catalog["strings"].items()):
            if key not in committed and item.get("extractionState") != "stale":
                problems.append(f"not in the committed catalog (run scripts/check-localization.sh): {key!r}")
    for problem in problems:
        print(problem)
    zones = "every file" if every else ", ".join(ZONES)
    print(f"{len(problems)} text(s) to translate ({zones}).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
