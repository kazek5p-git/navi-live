from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES_DIR = ROOT / "NaviLive" / "Resources"
BASE_LOCALE = "en"
BATCH_SIZE = 20
MAX_ATTEMPTS = 6
REQUEST_DELAY_SECONDS = 2.0
RETRY_BASE_SECONDS = 5.0
SPLIT_TOKEN = "992220099222"
BRAND_NAME = "Navi Live"
BRAND_TOKEN = "991770099177"
REQUEST_HEADERS = {
    "User-Agent": "NaviLiveLocalizationGenerator/1.0",
}
PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?[@dfisu]|%%")
STRINGS_LINE_PATTERN = re.compile(
    r'^\s*"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)";\s*$',
)
DEFAULT_LOCALES = [
    "pl",
    "ru",
    "uk",
    "ar",
    "fa",
    "tr",
    "de",
    "fr",
    "es",
    "it",
    "pt",
    "ro",
    "cs",
    "sk",
    "be",
    "lt",
    "lv",
    "et",
    "hu",
    "fi",
    "hr",
    "sr",
    "el",
    "bn",
    "hi",
    "id",
    "vi",
    "zh-Hans",
    "ja",
    "ko",
    "ckb",
]
TRANSLATION_TARGET_OVERRIDES = {
    "zh-Hans": "zh-CN",
}


def locale_dir(locale: str) -> Path:
    return RESOURCES_DIR / f"{locale}.lproj"


def translation_target(locale: str) -> str:
    return TRANSLATION_TARGET_OVERRIDES.get(locale, locale)


def strings_unescape(text: str) -> str:
    return (
        text.replace(r"\n", "\n")
        .replace(r"\"", '"')
        .replace(r"\\", "\\")
    )


def strings_escape(text: str) -> str:
    return (
        text.replace("\\", r"\\")
        .replace('"', r"\"")
        .replace("\n", r"\n")
    )


def protect_placeholders(text: str) -> tuple[str, list[str]]:
    placeholders = PLACEHOLDER_PATTERN.findall(text)
    protected = text
    for index, placeholder in enumerate(placeholders):
        protected = protected.replace(placeholder, f"99177{index}77199", 1)
    protected = protected.replace(BRAND_NAME, BRAND_TOKEN)
    return protected, placeholders


def restore_placeholders(text: str, placeholders: list[str]) -> str:
    restored = text.replace(BRAND_TOKEN, BRAND_NAME)
    for index, placeholder in enumerate(placeholders):
        restored = restored.replace(f"99177{index}77199", placeholder)
    return restored


def translate_single_text(text: str, target_locale: str) -> str:
    protected, placeholders = protect_placeholders(text)
    query = urllib.parse.quote(protected)
    target = translation_target(target_locale)
    url = (
        "https://translate.googleapis.com/translate_a/single"
        f"?client=gtx&sl={BASE_LOCALE}&tl={urllib.parse.quote(target)}&dt=t&q={query}"
    )
    for attempt in range(MAX_ATTEMPTS):
        try:
            request = urllib.request.Request(url, headers=REQUEST_HEADERS)
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read().decode("utf-8")
            time.sleep(REQUEST_DELAY_SECONDS)
            data = json.loads(raw)
            translated = "".join(part[0] for part in data[0]).strip()
            return restore_placeholders(translated, placeholders)
        except Exception:
            if attempt == MAX_ATTEMPTS - 1:
                raise
            time.sleep(RETRY_BASE_SECONDS + (attempt * RETRY_BASE_SECONDS))
    raise RuntimeError(f"Translation failed for locale {target_locale}")


def translate_texts(texts: list[str], target_locale: str) -> list[str]:
    protected_items: list[str] = []
    placeholders_per_item: list[list[str]] = []
    for text in texts:
        protected, placeholders = protect_placeholders(text)
        protected_items.append(protected)
        placeholders_per_item.append(placeholders)

    payload = f" {SPLIT_TOKEN} ".join(protected_items)
    query = urllib.parse.quote(payload)
    target = translation_target(target_locale)
    url = (
        "https://translate.googleapis.com/translate_a/single"
        f"?client=gtx&sl={BASE_LOCALE}&tl={urllib.parse.quote(target)}&dt=t&q={query}"
    )

    for attempt in range(MAX_ATTEMPTS):
        try:
            request = urllib.request.Request(url, headers=REQUEST_HEADERS)
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read().decode("utf-8")
            time.sleep(REQUEST_DELAY_SECONDS)
            data = json.loads(raw)
            translated = "".join(part[0] for part in data[0])
            pieces = translated.split(f" {SPLIT_TOKEN} ")
            if len(pieces) != len(texts):
                pieces = translated.split(SPLIT_TOKEN)
            if len(pieces) != len(texts) or any(SPLIT_TOKEN in piece for piece in pieces):
                return [translate_single_text(text, target_locale) for text in texts]
            return [
                restore_placeholders(piece.strip(), placeholders)
                for piece, placeholders in zip(pieces, placeholders_per_item, strict=True)
            ]
        except Exception:
            if attempt == MAX_ATTEMPTS - 1:
                time.sleep(RETRY_BASE_SECONDS * 2)
                return [translate_single_text(text, target_locale) for text in texts]
            time.sleep(RETRY_BASE_SECONDS + (attempt * RETRY_BASE_SECONDS))
    raise RuntimeError(f"Translation failed for locale {target_locale}")


def read_strings_file(path: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = STRINGS_LINE_PATTERN.match(raw_line)
        if not match:
            raise RuntimeError(f"Unable to parse .strings line in {path}: {raw_line}")
        entries.append(
            {
                "key": strings_unescape(match.group("key")),
                "value": strings_unescape(match.group("value")),
            },
        )
    return entries


def read_existing_strings(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return {
        entry["key"]: entry["value"]
        for entry in read_strings_file(path)
    }


def update_strings_file(path: Path, entries: list[dict[str, str]]) -> None:
    if not path.exists():
        raise RuntimeError(f"Missing iOS localization file: {path}")

    translations = {entry["key"]: entry["value"] for entry in entries}
    with path.open("r", encoding="utf-8", newline="") as handle:
        contents = handle.read()
    newline = "\r\n" if "\r\n" in contents else "\n"
    missing_keys = set(translations)
    updated_lines: list[str] = []
    for line in contents.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        line_ending = line[len(body):]
        match = STRINGS_LINE_PATTERN.match(body)
        if match and match.group("key") in translations:
            key = match.group("key")
            updated_lines.append(
                f'"{strings_escape(key)}" = "{strings_escape(translations[key])}";{line_ending}',
            )
            missing_keys.discard(key)
        else:
            updated_lines.append(line)

    updated_contents = "".join(updated_lines)
    if missing_keys:
        if updated_contents and not updated_contents.endswith(("\n", "\r")):
            updated_contents += newline
        updated_contents += "".join(
            f'"{strings_escape(entry["key"])}" = "{strings_escape(entry["value"])}";{newline}'
            for entry in entries
            if entry["key"] in missing_keys
        )

    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(updated_contents)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--rewrite-existing",
        action="store_true",
        help="Regenerate target .strings files even when translations already exist.",
    )
    parser.add_argument(
        "--exclude-locales",
        nargs="*",
        default=[],
        help="Locale tags to leave untouched, for example pl.",
    )
    parser.add_argument(
        "--only-locales",
        nargs="*",
        default=[],
        help="Locale tags to generate. When omitted, all configured locales except exclusions are processed.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    base_dir = locale_dir(BASE_LOCALE)
    base_files = sorted(base_dir.glob("*.strings"))
    only_locales = set(args.only_locales)
    excluded_locales = set(args.exclude_locales)

    for locale in DEFAULT_LOCALES:
        if locale == BASE_LOCALE:
            continue
        if only_locales and locale not in only_locales:
            print(f"skip {locale}", flush=True)
            continue
        if locale in excluded_locales:
            print(f"skip {locale}", flush=True)
            continue

        target_dir = locale_dir(locale)
        target_dir.mkdir(parents=True, exist_ok=True)
        generated_any = False

        for base_file in base_files:
            base_entries = read_strings_file(base_file)
            target_file = target_dir / base_file.name
            existing = read_existing_strings(target_file)
            entries_to_translate = (
                base_entries
                if args.rewrite_existing
                else [entry for entry in base_entries if entry["key"] not in existing]
            )
            if not entries_to_translate:
                continue

            translated_entries: list[dict[str, str]] = []
            for index in range(0, len(entries_to_translate), BATCH_SIZE):
                chunk = entries_to_translate[index : index + BATCH_SIZE]
                translated_texts = translate_texts([entry["value"] for entry in chunk], locale)
                for entry, translated in zip(chunk, translated_texts, strict=True):
                    translated_entries.append({"key": entry["key"], "value": translated})

            update_strings_file(target_file, translated_entries)
            generated_any = True

        print(("generated" if generated_any else "skip") + f" {locale}", flush=True)


if __name__ == "__main__":
    main()
