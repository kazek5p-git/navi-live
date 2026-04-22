#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib import error, parse, request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


API_BASE = "https://api.appstoreconnect.apple.com"
DEFAULT_BUNDLE_ID = "com.kazek.navilive"
DEFAULT_MARKETING_VERSION = "1.0"
DEFAULT_BUILD_NUMBER = "1"
DEFAULT_REPO_URL = "https://github.com/kazek5p-git/navi-live"
DEFAULT_PRIVACY_URL = "https://kazek5p-git.github.io/navi-live/privacy/"
DEFAULT_FEEDBACK_EMAIL = "kazek5p@gmail.com"
DEFAULT_CONTACT_FIRST_NAME = "Kazimierz"
DEFAULT_CONTACT_LAST_NAME = "Parzych"
DEFAULT_CONTACT_PHONE = "+48501711753"


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def load_env_required(name: str) -> str:
    value = os.environ.get(name) or os.environ.get(name.upper())
    if value:
        return value
    value = os.environ.get(name.lower())
    if value:
        return value
    raise RuntimeError(f"Missing required environment variable: {name}")


def load_sectioned_text(path: Path) -> dict[str, str]:
    raw = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    sections: dict[str, str] = {}
    current_key: str | None = None
    buffer: list[str] = []
    label_map = {
        "POLSKI": "pl",
        "ENGLISH": "en-US",
    }
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped in label_map:
            if current_key is not None:
                sections[current_key] = "\n".join(buffer).strip()
            current_key = label_map[stripped]
            buffer = []
            continue
        if current_key is not None:
            buffer.append(line)
    if current_key is not None:
        sections[current_key] = "\n".join(buffer).strip()
    if not sections:
        raise RuntimeError(f"Unable to parse localized sections from {path}")
    return sections


@dataclass
class AscClient:
    key_id: str
    issuer_id: str
    key_path: Path
    token_ttl_seconds: int = 900

    def __post_init__(self) -> None:
        key_data = self.key_path.read_bytes()
        self.private_key = serialization.load_pem_private_key(key_data, password=None)
        if not isinstance(self.private_key, ec.EllipticCurvePrivateKey):
            raise RuntimeError("ASC API key is not an EC private key.")
        self._token = ""
        self._token_expires_at = 0.0

    def _issue_token(self) -> str:
        now = int(time.time())
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer_id, "aud": "appstoreconnect-v1", "exp": now + self.token_ttl_seconds}
        signing_input = (
            base64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
            + "."
            + base64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        ).encode("ascii")
        der_signature = self.private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der_signature)
        raw_signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        token = signing_input.decode("ascii") + "." + base64url(raw_signature)
        self._token = token
        self._token_expires_at = now + self.token_ttl_seconds - 30
        return token

    def token(self) -> str:
        if not self._token or time.time() >= self._token_expires_at:
            return self._issue_token()
        return self._token

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None, query: dict[str, str] | None = None) -> dict[str, Any]:
        url = API_BASE + path
        if query:
            url += "?" + parse.urlencode(query)
        body = None
        headers = {
            "Authorization": f"Bearer {self.token()}",
            "Accept": "application/json",
        }
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = request.Request(url, data=body, headers=headers, method=method.upper())
        try:
            with request.urlopen(req) as resp:
                raw = resp.read()
        except error.HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"ASC API {method} {path} failed: HTTP {exc.code}\n{body_text}") from exc
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))


def first_data(result: dict[str, Any]) -> dict[str, Any]:
    data = result.get("data")
    if isinstance(data, list):
        if not data:
            raise RuntimeError("Expected at least one item but ASC returned none.")
        return data[0]
    if not data:
        raise RuntimeError("ASC response missing data.")
    return data


def get_app(client: AscClient, bundle_id: str) -> dict[str, Any]:
    result = client.request("GET", "/v1/apps", query={"filter[bundleId]": bundle_id, "limit": "2"})
    items = result.get("data", [])
    if len(items) != 1:
        raise RuntimeError(f"Expected exactly one app for bundle id {bundle_id}, got {len(items)}.")
    return items[0]


def get_beta_review_detail(client: AscClient, app_id: str) -> dict[str, Any]:
    return first_data(client.request("GET", f"/v1/apps/{app_id}/betaAppReviewDetail"))


def patch_beta_review_detail(client: AscClient, review_id: str, notes: str, first_name: str, last_name: str, email: str, phone: str) -> None:
    payload = {
        "data": {
            "type": "betaAppReviewDetails",
            "id": review_id,
            "attributes": {
                "contactFirstName": first_name,
                "contactLastName": last_name,
                "contactEmail": email,
                "contactPhone": phone,
                "demoAccountRequired": False,
                "notes": notes,
            },
        }
    }
    client.request("PATCH", f"/v1/betaAppReviewDetails/{review_id}", payload)


def get_beta_app_localizations(client: AscClient, app_id: str) -> dict[str, dict[str, Any]]:
    result = client.request("GET", f"/v1/apps/{app_id}/betaAppLocalizations", query={"limit": "50"})
    return {item["attributes"]["locale"]: item for item in result.get("data", [])}


def upsert_beta_app_localization(
    client: AscClient,
    app_id: str,
    existing: dict[str, dict[str, Any]],
    locale: str,
    description: str,
    feedback_email: str,
    marketing_url: str,
    privacy_url: str,
) -> None:
    create_attributes = {
        "locale": locale,
        "description": description,
        "feedbackEmail": feedback_email,
        "marketingUrl": marketing_url,
        "privacyPolicyUrl": privacy_url,
    }
    update_attributes = {
        "description": description,
        "feedbackEmail": feedback_email,
        "marketingUrl": marketing_url,
        "privacyPolicyUrl": privacy_url,
    }
    if locale in existing:
        loc_id = existing[locale]["id"]
        payload = {"data": {"type": "betaAppLocalizations", "id": loc_id, "attributes": update_attributes}}
        client.request("PATCH", f"/v1/betaAppLocalizations/{loc_id}", payload)
        return
    payload = {
        "data": {
            "type": "betaAppLocalizations",
            "attributes": create_attributes,
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    client.request("POST", "/v1/betaAppLocalizations", payload)


def get_app_info(client: AscClient, app_id: str) -> dict[str, Any]:
    return first_data(client.request("GET", f"/v1/apps/{app_id}/appInfos", query={"limit": "2"}))


def get_app_info_localizations(client: AscClient, app_info_id: str) -> dict[str, dict[str, Any]]:
    result = client.request("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations", query={"limit": "50"})
    return {item["attributes"]["locale"]: item for item in result.get("data", [])}


def upsert_app_info_localization(
    client: AscClient,
    app_info_id: str,
    existing: dict[str, dict[str, Any]],
    locale: str,
    name: str,
    subtitle: str,
    privacy_url: str,
) -> None:
    create_attributes = {
        "locale": locale,
        "name": name,
        "subtitle": subtitle,
        "privacyPolicyUrl": privacy_url,
    }
    update_attributes = {
        "name": name,
        "subtitle": subtitle,
        "privacyPolicyUrl": privacy_url,
    }
    if locale in existing:
        loc_id = existing[locale]["id"]
        payload = {"data": {"type": "appInfoLocalizations", "id": loc_id, "attributes": update_attributes}}
        client.request("PATCH", f"/v1/appInfoLocalizations/{loc_id}", payload)
        return
    payload = {
        "data": {
            "type": "appInfoLocalizations",
            "attributes": create_attributes,
            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": app_info_id}}},
        }
    }
    client.request("POST", "/v1/appInfoLocalizations", payload)


def get_builds(client: AscClient, app_id: str, build_number: str) -> list[dict[str, Any]]:
    result = client.request(
        "GET",
        "/v1/builds",
        query={
            "filter[app]": app_id,
            "filter[version]": build_number,
            "include": "preReleaseVersion",
            "limit": "50",
            "sort": "-uploadedDate",
        },
    )
    included = {item["id"]: item for item in result.get("included", []) if item.get("type") == "preReleaseVersions"}
    builds: list[dict[str, Any]] = []
    for build in result.get("data", []):
        pre_rel = build.get("relationships", {}).get("preReleaseVersion", {}).get("data")
        if pre_rel:
            build["preReleaseVersionAttributes"] = included.get(pre_rel["id"], {}).get("attributes", {})
        else:
            build["preReleaseVersionAttributes"] = {}
        builds.append(build)
    return builds


def wait_for_build(client: AscClient, app_id: str, marketing_version: str, build_number: str, timeout_seconds: int = 900) -> dict[str, Any]:
    deadline = time.time() + timeout_seconds
    while True:
        candidates = get_builds(client, app_id, build_number)
        for build in candidates:
            if build.get("preReleaseVersionAttributes", {}).get("version") == marketing_version:
                return build
        if time.time() >= deadline:
            raise RuntimeError(f"Timed out waiting for build {marketing_version} ({build_number}) in App Store Connect.")
        print(f"Waiting for build {marketing_version} ({build_number}) to appear in ASC...")
        time.sleep(20)


def get_beta_build_localizations(client: AscClient, build_id: str) -> dict[str, dict[str, Any]]:
    result = client.request("GET", f"/v1/builds/{build_id}/betaBuildLocalizations", query={"limit": "50"})
    return {item["attributes"]["locale"]: item for item in result.get("data", [])}


def upsert_beta_build_localization(
    client: AscClient,
    build_id: str,
    existing: dict[str, dict[str, Any]],
    locale: str,
    whats_new: str,
) -> None:
    create_attributes = {"locale": locale, "whatsNew": whats_new}
    update_attributes = {"whatsNew": whats_new}
    if locale in existing:
        loc_id = existing[locale]["id"]
        payload = {"data": {"type": "betaBuildLocalizations", "id": loc_id, "attributes": update_attributes}}
        client.request("PATCH", f"/v1/betaBuildLocalizations/{loc_id}", payload)
        return
    payload = {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": create_attributes,
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    }
    client.request("POST", "/v1/betaBuildLocalizations", payload)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Sync Navi Live TestFlight/App Store Connect metadata.")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--marketing-version", default=DEFAULT_MARKETING_VERSION)
    parser.add_argument("--build-number", default=DEFAULT_BUILD_NUMBER)
    parser.add_argument("--feedback-email", default=DEFAULT_FEEDBACK_EMAIL)
    parser.add_argument("--marketing-url", default=DEFAULT_REPO_URL)
    parser.add_argument("--privacy-url", default=DEFAULT_PRIVACY_URL)
    parser.add_argument("--contact-first-name", default=DEFAULT_CONTACT_FIRST_NAME)
    parser.add_argument("--contact-last-name", default=DEFAULT_CONTACT_LAST_NAME)
    parser.add_argument("--contact-phone", default=DEFAULT_CONTACT_PHONE)
    parser.add_argument("--no-build-localization", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    asc_dir = repo_root / "native-ios" / "AppStoreConnect"

    beta_description = load_sectioned_text(asc_dir / "TestFlight-beta-description.txt")
    review_notes = load_sectioned_text(asc_dir / "TestFlight-review-notes-strict.txt")
    what_to_test = load_sectioned_text(asc_dir / "TestFlight-what-to-test.txt")

    key_path = Path(load_env_required("EXPO_ASC_API_KEY_PATH"))
    key_id = load_env_required("EXPO_ASC_KEY_ID")
    issuer_id = load_env_required("EXPO_ASC_ISSUER_ID")

    client = AscClient(key_id=key_id, issuer_id=issuer_id, key_path=key_path)

    app = get_app(client, args.bundle_id)
    app_id = app["id"]
    print(f"Resolved ASC app: {app_id} ({app['attributes']['name']})")

    review = get_beta_review_detail(client, app_id)
    patch_beta_review_detail(
        client=client,
        review_id=review["id"],
        notes=review_notes["en-US"],
        first_name=args.contact_first_name,
        last_name=args.contact_last_name,
        email=args.feedback_email,
        phone=args.contact_phone,
    )
    print("Updated beta app review detail.")

    beta_localizations = get_beta_app_localizations(client, app_id)
    for locale in ("pl", "en-US"):
        upsert_beta_app_localization(
            client=client,
            app_id=app_id,
            existing=beta_localizations,
            locale=locale,
            description=beta_description[locale],
            feedback_email=args.feedback_email,
            marketing_url=args.marketing_url,
            privacy_url=args.privacy_url,
        )
        print(f"Upserted beta app localization: {locale}")

    app_info = get_app_info(client, app_id)
    app_info_localizations = get_app_info_localizations(client, app_info["id"])
    subtitles = {
        "pl": "Dostępna nawigacja piesza",
        "en-US": "Accessible Walking Navigation",
    }
    for locale in ("pl", "en-US"):
        upsert_app_info_localization(
            client=client,
            app_info_id=app_info["id"],
            existing=app_info_localizations,
            locale=locale,
            name="Navi Live",
            subtitle=subtitles[locale],
            privacy_url=args.privacy_url,
        )
        print(f"Upserted app info localization: {locale}")

    if not args.no_build_localization:
        build = wait_for_build(client, app_id, args.marketing_version, args.build_number)
        build_id = build["id"]
        print(f"Resolved build: id={build_id} version={build['attributes']['version']} marketing={args.marketing_version}")
        build_localizations = get_beta_build_localizations(client, build_id)
        for locale in ("pl", "en-US"):
            upsert_beta_build_localization(
                client=client,
                build_id=build_id,
                existing=build_localizations,
                locale=locale,
                whats_new=what_to_test[locale],
            )
            print(f"Upserted beta build localization: {locale}")

    print("App Store Connect metadata sync completed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover
        eprint(str(exc))
        raise SystemExit(1)
