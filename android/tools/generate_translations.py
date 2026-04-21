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
SPLIT_TOKEN = "992220099222"
PLACEHOLDER_PATTERN = re.compile(r"%\d+\$[sd]")
BRAND_NAME = "Navi Live"
BRAND_TOKEN = "991770099177"


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
    url = (
        "https://translate.googleapis.com/translate_a/single"
        f"?client=gtx&sl=en&tl={urllib.parse.quote(target_locale)}&dt=t&q={query}"
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                raw = response.read().decode("utf-8")
            import json

            data = json.loads(raw)
            translated = "".join(part[0] for part in data[0]).strip()
            return restore_placeholders(translated, placeholders)
        except Exception:
            if attempt == 3:
                raise
            time.sleep(1.0 + attempt)
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
    url = (
        "https://translate.googleapis.com/translate_a/single"
        f"?client=gtx&sl=en&tl={urllib.parse.quote(target_locale)}&dt=t&q={query}"
    )

    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                raw = response.read().decode("utf-8")
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
            if attempt == 3:
                raise
            time.sleep(1.0 + attempt)
    raise RuntimeError(f"Translation failed for locale {target_locale}")


def xml_escape(text: str) -> str:
    text = re.sub(r"\\+'", "'", text)
    return html.escape(text, quote=False).replace("'", "\\'")


def write_locale_file(locale: str, items: list[dict[str, str]]) -> None:
    locale_dir = RES_DIR / f"values-{locale}"
    locale_dir.mkdir(parents=True, exist_ok=True)
    output = locale_dir / "strings.xml"
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
    for item in items:
        lines.append(f'    <string name="{item["name"]}">{xml_escape(item["text"])}</string>')
    lines.append("</resources>")
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_existing_locale(locale: str) -> dict[str, str]:
    output = RES_DIR / f"values-{locale}" / "strings.xml"
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
        items_to_translate = base_items if args.rewrite_existing else [
            item for item in base_items if item["name"] not in existing
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

        merged_items = []
        translated_by_name = {item["name"]: item["text"] for item in translated_items}
        for item in base_items:
            text = (
                translated_by_name[item["name"]]
                if args.rewrite_existing or item["name"] not in existing
                else existing[item["name"]]
            )
            merged_items.append(
                {
                    "name": item["name"],
                    "text": text,
                },
            )
        write_locale_file(locale, merged_items)
        print(f"generated {locale}", flush=True)


if __name__ == "__main__":
    main()
