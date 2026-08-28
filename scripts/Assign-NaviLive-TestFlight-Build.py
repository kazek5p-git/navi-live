#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
import sys
import time
from pathlib import Path
from typing import Any


def load_metadata_module() -> Any:
    source_path = Path(__file__).with_name("Update-NaviLive-AppStoreConnect-Metadata.py")
    spec = importlib.util.spec_from_file_location("navilive_asc_metadata", source_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Nie można załadować modułu ASC: {source_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def required_environment(name: str, fallback: str | None = None) -> str:
    value = os.environ.get(name)
    if not value and fallback:
        value = os.environ.get(fallback)
    if not value:
        raise RuntimeError(f"Brak zmiennej środowiskowej {name}.")
    return value


def get_build(client: Any, app_id: str, build_number: str) -> dict[str, Any] | None:
    result = client.request(
        "GET",
        "/v1/builds",
        query={"filter[app]": app_id, "filter[version]": build_number, "limit": "10"},
    )
    builds = result.get("data", [])
    if len(builds) > 1:
        raise RuntimeError(f"App Store Connect zwrócił więcej niż jeden build {build_number}.")
    return builds[0] if builds else None


def get_build_details(client: Any, build_id: str) -> dict[str, Any]:
    result = client.request("GET", f"/v1/builds/{build_id}", query={"include": "betaGroups"})
    build = result.get("data")
    if not build:
        raise RuntimeError(f"App Store Connect nie zwrócił szczegółów buildu {build_id}.")
    return build


def wait_for_valid_build(
    client: Any,
    app_id: str,
    build_number: str,
    timeout_seconds: int,
    poll_seconds: int,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    while True:
        build = get_build(client, app_id, build_number)
        if build is not None:
            state = build.get("attributes", {}).get("processingState")
            print(f"Build {build_number}: stan przetwarzania {state}.", flush=True)
            if state == "VALID":
                return build
            if state in {"FAILED", "INVALID"}:
                raise RuntimeError(f"Build {build_number} ma nieprawidłowy stan: {state}.")
        else:
            print(f"Build {build_number} nie jest jeszcze widoczny w App Store Connect.", flush=True)

        if time.monotonic() >= deadline:
            raise RuntimeError(
                f"Przekroczono czas oczekiwania na przetworzenie buildu {build_number}."
            )
        time.sleep(poll_seconds)


def build_group_ids(build: dict[str, Any]) -> set[str]:
    relationship = (
        build.get("relationships", {})
        .get("betaGroups", {})
        .get("data", [])
    )
    return {
        item["id"]
        for item in relationship
        if item.get("type") == "betaGroups" and item.get("id")
    }


def find_group(groups: list[dict[str, Any]], name: str, internal: bool) -> dict[str, Any]:
    matches = [
        group
        for group in groups
        if group.get("attributes", {}).get("name") == name
        and group.get("attributes", {}).get("isInternalGroup") is internal
    ]
    if len(matches) != 1:
        kind = "wewnętrzną" if internal else "zewnętrzną"
        raise RuntimeError(
            f"Nie znaleziono dokładnie jednej grupy {kind} '{name}' dla aplikacji."
        )
    return matches[0]


def assign_group(client: Any, build: dict[str, Any], group: dict[str, Any]) -> None:
    build_id = build["id"]
    group_id = group["id"]
    group_name = group["attributes"]["name"]
    if group_id in build_group_ids(build):
        print(f"Build {build['attributes'].get('version')} jest już w grupie {group_name}.")
        return

    client.request(
        "POST",
        f"/v1/betaGroups/{group_id}/relationships/builds",
        {"data": [{"type": "builds", "id": build_id}]},
    )
    print(f"Przypięto build {build['attributes'].get('version')} do grupy {group_name}.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Przypina przetworzony build Navi Live do grup TestFlight."
    )
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--internal-group-name", default="Internal Testing")
    parser.add_argument("--external-group-name", default="External Testing")
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--poll-seconds", type=int, default=20)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.build_number.isdigit():
        raise RuntimeError("Numer buildu musi zawierać wyłącznie cyfry.")
    if args.timeout_seconds < 1 or args.poll_seconds < 1:
        raise RuntimeError("Czas oczekiwania i odstęp odpytywania muszą być dodatnie.")

    module = load_metadata_module()
    key_path = Path(required_environment("ASC_API_KEY_PATH", "ASC_KEY_PATH"))
    client = module.AscClient(
        key_id=required_environment("ASC_KEY_ID"),
        issuer_id=required_environment("ASC_ISSUER_ID"),
        key_path=key_path,
    )
    app = module.get_app(client, module.DEFAULT_BUNDLE_ID)
    build = wait_for_valid_build(
        client=client,
        app_id=app["id"],
        build_number=args.build_number,
        timeout_seconds=args.timeout_seconds,
        poll_seconds=args.poll_seconds,
    )
    build = get_build_details(client, build["id"])
    groups = client.request(
        "GET",
        "/v1/betaGroups",
        query={"filter[app]": app["id"], "limit": "50"},
    ).get("data", [])
    internal_group = find_group(groups, args.internal_group_name, internal=True)
    external_group = find_group(groups, args.external_group_name, internal=False)

    for group in (internal_group, external_group):
        assign_group(client, build, group)
        build = get_build_details(client, build["id"])

    final_group_ids = build_group_ids(build)
    expected_group_ids = {internal_group["id"], external_group["id"]}
    if not expected_group_ids.issubset(final_group_ids):
        raise RuntimeError("Nie udało się potwierdzić przypięcia buildu do obu grup TestFlight.")
    print("Build jest przypięty do grupy wewnętrznej i zewnętrznej.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
