from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


REQUESTED_LOCALES = [
    "en",
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
ANDROID_RESOURCE_QUALIFIERS = {
    "en": "values",
    "id": "values-in",
    "zh-Hans": "values-b+zh+Hans",
    "ckb": "values-b+ckb",
}
ANDROID_LOCALE_CONFIG_ALIASES = {
    "id": ("id", "in"),
}
ANDROID_PLACEHOLDER = re.compile(r"%(?:\d+\$)?[sd]|%%")
IOS_PLACEHOLDER = re.compile(r"%(?:\d+\$)?[@dfisu]|%%")
TRANSLATION_ARTIFACT = re.compile(r"99177|99222|7079|9919")
STRINGS_LINE = re.compile(
    r'^\s*"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)";\s*$',
)


def android_qualifier(locale: str) -> str:
    return ANDROID_RESOURCE_QUALIFIERS.get(locale, f"values-{locale}")


def android_strings(path: Path) -> tuple[dict[str, str], dict[str, bool]]:
    tree = ET.parse(path)
    values: dict[str, str] = {}
    translatable: dict[str, bool] = {}
    for element in tree.getroot().findall("string"):
        name = element.attrib["name"]
        values[name] = "".join(element.itertext())
        translatable[name] = element.attrib.get("translatable") != "false"
    return values, translatable


def ios_unescape(text: str) -> str:
    return (
        text.replace(r"\n", "\n")
        .replace(r"\"", '"')
        .replace(r"\\", "\\")
    )


def ios_strings(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        match = STRINGS_LINE.match(line)
        if not match:
            raise RuntimeError(f"Invalid .strings line: {path}:{line_number}: {line}")
        values[ios_unescape(match.group("key"))] = ios_unescape(match.group("value"))
    return values


def compare_placeholders(
    platform: str,
    locale: str,
    key: str,
    base_value: str,
    localized_value: str,
    pattern: re.Pattern[str],
    errors: list[str],
    file_name: str | None = None,
) -> None:
    base_placeholders = pattern.findall(base_value)
    localized_placeholders = pattern.findall(localized_value)
    if sorted(base_placeholders) != sorted(localized_placeholders):
        location = f"{platform} {locale}"
        if file_name:
            location += f"/{file_name}"
        errors.append(
            f"{location} placeholder mismatch {key}: "
            f"{base_placeholders} != {localized_placeholders}",
        )


def validate_artifacts(
    platform: str,
    locale: str,
    key: str,
    value: str,
    errors: list[str],
    file_name: str | None = None,
) -> None:
    if not TRANSLATION_ARTIFACT.search(value):
        return
    location = f"{platform} {locale}"
    if file_name:
        location += f"/{file_name}"
    errors.append(f"{location} contains translation artifact {key}: {value}")


def validate_android(repo: Path, errors: list[str]) -> None:
    res_dir = repo / "android" / "app" / "src" / "main" / "res"
    locale_config = (res_dir / "xml" / "locales_config.xml").read_text(encoding="utf-8")

    base_values, base_translatable = android_strings(res_dir / "values" / "strings.xml")
    base_keys = {
        key
        for key, is_translatable in base_translatable.items()
        if is_translatable
    }

    for locale in REQUESTED_LOCALES:
        config_tags = ANDROID_LOCALE_CONFIG_ALIASES.get(locale, (locale,))
        if locale != "en" and not any(
            f'android:name="{tag}"' in locale_config
            for tag in config_tags
        ):
            errors.append(f"Android locale_config missing {locale}")

        locale_dir = res_dir / android_qualifier(locale)
        if not locale_dir.exists():
            errors.append(f"Android resource dir missing {locale}: {locale_dir.name}")
            continue

        if locale == "en":
            continue

        localized_values, _ = android_strings(locale_dir / "strings.xml")
        missing = sorted(base_keys - set(localized_values))
        if missing:
            errors.append(f"Android {locale} missing {len(missing)} keys, first: {missing[:5]}")

    for locale_dir in sorted(res_dir.glob("values-*")):
        strings_path = locale_dir / "strings.xml"
        if not strings_path.exists():
            continue

        locale = locale_dir.name.removeprefix("values-")
        localized_values, _ = android_strings(strings_path)
        for key, value in sorted(localized_values.items()):
            validate_artifacts("Android", locale, key, value, errors)
            if key not in base_keys:
                continue
            compare_placeholders(
                "Android",
                locale,
                key,
                base_values[key],
                localized_values[key],
                ANDROID_PLACEHOLDER,
                errors,
            )


def validate_ios(repo: Path, errors: list[str]) -> None:
    resources_dir = repo / "native-ios" / "NaviLive" / "Resources"
    base_dir = resources_dir / "en.lproj"
    base_files = sorted(base_dir.glob("*.strings"))

    for locale in REQUESTED_LOCALES:
        locale_dir = resources_dir / f"{locale}.lproj"
        if not locale_dir.exists():
            errors.append(f"iOS lproj missing {locale}")
            continue

        for base_file in base_files:
            localized_file = locale_dir / base_file.name
            if not localized_file.exists():
                errors.append(f"iOS {locale} missing file {base_file.name}")
                continue

            base_values = ios_strings(base_file)
            localized_values = ios_strings(localized_file)
            missing = sorted(set(base_values) - set(localized_values))
            extra = sorted(set(localized_values) - set(base_values))
            if missing:
                errors.append(
                    f"iOS {locale}/{base_file.name} missing {len(missing)} keys, first: {missing[:5]}",
                )
            if extra:
                errors.append(
                    f"iOS {locale}/{base_file.name} extra {len(extra)} keys, first: {extra[:5]}",
                )

            for key in sorted(set(base_values) & set(localized_values)):
                validate_artifacts(
                    "iOS",
                    locale,
                    key,
                    localized_values[key],
                    errors,
                    file_name=base_file.name,
                )
                compare_placeholders(
                    "iOS",
                    locale,
                    key,
                    base_values[key],
                    localized_values[key],
                    IOS_PLACEHOLDER,
                    errors,
                    file_name=base_file.name,
                )


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    errors: list[str] = []
    validate_android(repo, errors)
    validate_ios(repo, errors)

    if errors:
        print("\n".join(errors))
        print(f"TOTAL_ERRORS={len(errors)}")
        return 1

    print("OK: requested Android and iOS locales exist with matching keys and placeholders")
    return 0


if __name__ == "__main__":
    sys.exit(main())
