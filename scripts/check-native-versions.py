#!/usr/bin/env python3
"""Compare the native SDK versions this plugin pins with the latest published ones.

  iOS:     ios/linktrail_flutter.podspec  s.dependency 'LinkTrailSDK', '~> X'  vs CocoaPods trunk
           ios/linktrail_flutter/Package.swift  ios-sdk from: "X"  (must match the podspec pin)
  Android: android/build.gradle.kts  io.linktrail:sdk:X  vs Maven Central

Exit 0 when every pin is the latest. Otherwise prints each mismatch and exits 1, or, with
--warn-only, prints GitHub ::warning annotations and exits 0. Network errors are reported as
warnings and never fail the run in --warn-only mode.
"""
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRUNK = "https://trunk.cocoapods.org/api/v1/pods/LinkTrailSDK"
MAVEN = "https://repo1.maven.org/maven2/io/linktrail/sdk/maven-metadata.xml"


def vkey(v):
    return tuple(int(p) for p in re.findall(r"\d+", v))


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "linktrail-flutter-version-check"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def pin(path, pattern):
    m = re.search(pattern, (ROOT / path).read_text())
    return m.group(1) if m else None


def latest_pod():
    data = json.loads(fetch(TRUNK))
    return max((v["name"] for v in data["versions"]), key=vkey)


def latest_maven():
    meta = ET.fromstring(fetch(MAVEN))
    versions = [v.text for v in meta.iter("version") if v.text and re.fullmatch(r"[\d.]+", v.text)]
    return max(versions, key=vkey)


def main():
    warn_only = "--warn-only" in sys.argv
    problems = []
    checks = [
        ("iOS podspec LinkTrailSDK", pin("ios/linktrail_flutter.podspec", r"dependency\s+'LinkTrailSDK',\s*'[~>=\s]*([\d.]+)'"), latest_pod),
        ("iOS Package.swift ios-sdk", pin("ios/linktrail_flutter/Package.swift", r"ios-sdk\.git\",\s*(?:\.\w+\()?from:\s*\"([\d.]+)\""), latest_pod),
        ("Android io.linktrail:sdk", pin("android/build.gradle.kts", r"io\.linktrail:sdk:([\d.]+)"), latest_maven),
    ]
    cache = {}
    for label, pinned, source in checks:
        if pinned is None:
            problems.append(f"{label}: pin not found in the source")
            continue
        try:
            latest = cache[source] if source in cache else cache.setdefault(source, source())
        except Exception as e:  # network or parse failure
            print(f"::warning title=native versions::{label}: could not read the latest version ({e})")
            continue
        state = "ok" if pinned == latest else "OUTDATED"
        print(f"{label}: pinned {pinned}, latest {latest} — {state}")
        if pinned != latest:
            problems.append(f"{label} pins {pinned}, latest published is {latest}")
    if not problems:
        print("All native SDK pins are the latest published versions.")
        return 0
    for p in problems:
        print(("::warning title=native versions::" if warn_only else "::error title=native versions::") + p)
    return 0 if warn_only else 1


if __name__ == "__main__":
    sys.exit(main())
