from __future__ import annotations

import argparse
import html
import re
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RES_DIR = ROOT / "app" / "src" / "main" / "res"
BASE_STRINGS = RES_DIR / "values" / "strings.xml"
LOCALES_CONFIG = RES_DIR / "xml" / "locales_config.xml"
BATCH_SIZE = 20
MAX_ATTEMPTS = 6
REQUEST_DELAY_SECONDS = 2.0
RETRY_BASE_SECONDS = 5.0
SPLIT_TOKEN = "992220099222"
PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?[sd]|%%")
BRAND_NAME = "Navi Live"
BRAND_TOKEN = "991770099177"
REQUEST_HEADERS = {
    "User-Agent": "NaviLiveLocalizationGenerator/1.0",
}
RESOURCE_QUALIFIER_OVERRIDES = {
    "id": "b+id",
    "zh-Hans": "b+zh+Hans",
    "ckb": "b+ckb",
}
TRANSLATION_TARGET_OVERRIDES = {
    "zh-Hans": "zh-CN",
}


def resource_qualifier(locale: str) -> str:
    if locale in RESOURCE_QUALIFIER_OVERRIDES:
        return RESOURCE_QUALIFIER_OVERRIDES[locale]
    if "-" in locale:
        return "b+" + locale.replace("-", "+")
    return locale


def translation_target(locale: str) -> str:
    return TRANSLATION_TARGET_OVERRIDES.get(locale, locale)


def read_strings() -> list[dict[str, str]]:
    root = ET.parse(BASE_STRINGS).getroot()
    strings: list[dict[str, str]] = []
    for element in root.findall("string"):
        name = element.attrib["name"]
        if element.attrib.get("translatable") == "false":
            continue
        text = "".join(element.itertext())
        strings.append({"name": name, "text": text})
    return strings


def read_locales() -> list[str]:
    android_ns = "{http://schemas.android.com/apk/res/android}"
    root = ET.parse(LOCALES_CONFIG).getroot()
    locales = []
    for locale in root.findall("locale"):
        tag = locale.attrib.get(f"{android_ns}name", "")
        if tag and tag != "en":
            locales.append(tag)
    return locales


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
        f"?client=gtx&sl=en&tl={urllib.parse.quote(target)}&dt=t&q={query}"
    )
    for attempt in range(MAX_ATTEMPTS):
        try:
            request = urllib.request.Request(url, headers=REQUEST_HEADERS)
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read().decode("utf-8")
            time.sleep(REQUEST_DELAY_SECONDS)
            import json

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
        f"?client=gtx&sl=en&tl={urllib.parse.quote(target)}&dt=t&q={query}"
    )

    for attempt in range(MAX_ATTEMPTS):
        try:
            request = urllib.request.Request(url, headers=REQUEST_HEADERS)
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read().decode("utf-8")
            time.sleep(REQUEST_DELAY_SECONDS)
            import json

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


def xml_escape(text: str) -> str:
    text = re.sub(r"\\+'", "'", text)
    # AAPT interpretuje apostrof jako znak składniowy zasobu tekstowego.
    return html.escape(text, quote=False).replace("'", "\\'")


def update_locale_file(locale: str, items: list[dict[str, str]]) -> None:
    locale_dir = RES_DIR / f"values-{resource_qualifier(locale)}"
    output = locale_dir / "strings.xml"
    if not output.exists():
        raise RuntimeError(f"Missing Android locale file: {output}")

    translations = {item["name"]: item["text"] for item in items}
    with output.open("r", encoding="utf-8", newline="") as handle:
        contents = handle.read()
    newline = "\r\n" if "\r\n" in contents else "\n"
    missing_names = set(translations)
    updated_lines: list[str] = []
    string_pattern = re.compile(
        r'^(?P<indent>\s*)<string name="(?P<name>[^"]+)"(?P<attributes>[^>]*)>'
        r".*</string>(?P<trailing>\s*)$",
    )
    for line in contents.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        line_ending = line[len(body):]
        match = string_pattern.match(body)
        name = match.group("name") if match else None
        if name in translations:
            updated_lines.append(
                f'{match.group("indent")}<string name="{name}"{match.group("attributes")}>'
                f'{xml_escape(translations[name])}</string>{match.group("trailing")}{line_ending}',
            )
            missing_names.discard(name)
        else:
            updated_lines.append(line)

    if missing_names:
        updated_contents = "".join(updated_lines)
        closing_index = updated_contents.rfind("</resources>")
        if closing_index < 0:
            raise RuntimeError(f"Missing resources closing tag: {output}")
        prefix = updated_contents[:closing_index]
        if not prefix.endswith(("\n", "\r")):
            prefix += newline
        inserted = "".join(
            f'    <string name="{item["name"]}">{xml_escape(item["text"])}</string>{newline}'
            for item in items
            if item["name"] in missing_names
        )
        updated_contents = prefix + inserted + updated_contents[closing_index:]
    else:
        updated_contents = "".join(updated_lines)

    with output.open("w", encoding="utf-8", newline="") as handle:
        handle.write(updated_contents)


def read_existing_locale(locale: str) -> dict[str, str]:
    output = RES_DIR / f"values-{resource_qualifier(locale)}" / "strings.xml"
    if not output.exists():
        return {}
    root = ET.parse(output).getroot()
    data: dict[str, str] = {}
    for element in root.findall("string"):
        data[element.attrib["name"]] = "".join(element.itertext())
    return data


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--rewrite-existing",
        action="store_true",
        help="Regenerate locale files from the base strings even when translations already exist.",
    )
    parser.add_argument(
        "--translate-fallbacks",
        action="store_true",
        help="Tłumaczy tylko wartości asystenta, które nadal są dokładnym angielskim fallbackiem.",
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
        help="Locale tags to regenerate. When omitted, all locales except exclusions are processed.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    base_items = read_strings()
    locales = read_locales()
    only_locales = set(args.only_locales)
    excluded_locales = set(args.exclude_locales)
    for locale in locales:
        if only_locales and locale not in only_locales:
            print(f"skip {locale}", flush=True)
            continue
        if locale in excluded_locales:
            print(f"skip {locale}", flush=True)
            continue

        existing = read_existing_locale(locale)
        if args.rewrite_existing:
            items_to_translate = base_items
        else:
            items_to_translate = [
                item for item in base_items
                if item["name"] not in existing or (
                    args.translate_fallbacks
                    and item["name"].startswith(("assistant_", "format_assistant_"))
                    and existing[item["name"]].strip() == item["text"].strip()
                )
            ]
        if not items_to_translate:
            print(f"skip {locale}", flush=True)
            continue

        translated_items: list[dict[str, str]] = []
        for index in range(0, len(items_to_translate), BATCH_SIZE):
            chunk = items_to_translate[index : index + BATCH_SIZE]
            translated_texts = translate_texts([item["text"] for item in chunk], locale)
            for item, translated in zip(chunk, translated_texts, strict=True):
                translated_items.append({"name": item["name"], "text": translated})

        update_locale_file(locale, translated_items)
        print(f"generated {locale}", flush=True)


if __name__ == "__main__":
    main()
