#!/usr/bin/env python3
"""Resolve the e2e environment, the links to test and the rows to run. Stdlib only.

Reads e2e/e2e-env.json (the one table of hosts, slugs and backend URLs, same shape as the native
SDKs' scripts/e2e-env.json) and e2e/e2e-flows.json (the one table of rows), plus the run's choices
from the environment:

  LINKTRAIL_ENV                 prod | dev (empty = default_environment; test = dev)
  E2E_CUSTOM_LINK               \\
  E2E_SUBDOMAIN_LINK             | each a full URL (https://<host>/<slug>) or a bare slug;
  E2E_CUSTOM_PROBLISTIC_LINK     | empty = the slot's default slug on the environment's host
  E2E_SUBDOMAIN_PROBLISTIC_LINK /
  E2E_LINK_TYPES                link-type matrix: all (default), none, or a comma list
  E2E_EXPECT_VOUCHER            voucher the deferred flows must show (empty = expect.voucher)

Commands:

  resolve --format shell|env    KEY=value lines (shell-quoted for `eval`, or plain for $GITHUB_OUTPUT)
  plan [row …]                  the rows to run, one per line, fields separated by US (0x1f, so
                                empty fields survive `IFS=$'\x1f' read`):
                                  row yaml kind consent url link_type reward_model path_re custom_data_re skip
                                a row with a non-empty `skip` is reported as skipped with that reason
                                (a link type or reward link this environment has no link for). With no
                                arguments: every row. An argument is a flow (its plain row and its
                                link-type rows) or one link-type row (<flow>__<type>).

A bad choice (unknown environment, a link on the wrong host, an unknown link type or row) fails fast:
exit 2 with one "ERROR: …" line on stderr (a ::error annotation in CI).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "e2e-env.json"
FLOWS = HERE / "e2e-flows.json"
SLOTS = ("custom_link", "subdomain_link", "custom_problistic_link", "subdomain_problistic_link")
HOST_FIELDS = ("subdomain_host", "custom_host")
BACKEND_CHECKS = ("earning", "reengagement_open_count", "events")
REWARD_MODELS = ("per_event", "rev_share")
KINDS = ("local", "deferred", "problistic", "reengagement", "reopen", "reward", "event")
_SLUG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._~-]{0,127}")
_VOUCHER = re.compile(r"[A-Za-z0-9_-]{1,64}")
_TYPE = re.compile(r"[a-z][a-z0-9_]{0,31}")
_EVENT = re.compile(r"[A-Za-z0-9_.-]{1,64}")
_PATH = re.compile(r"/[A-Za-z0-9._~/-]{0,200}")
_ROW = re.compile(r"[a-z][a-z0-9_]{0,63}")
# Java regex metacharacters (Maestro matches text selectors as Java regexes).
_REGEX_META = set("\\^$.|?*+()[]{}")


class TargetError(ValueError):
    """A choice that can't be resolved. The message is shown to the person who started the run."""


def java_regex_literal(text: str) -> str:
    return "".join("\\" + c if c in _REGEX_META else c for c in text)


def env_var(slot: str) -> str:
    return "E2E_" + slot.upper()


def _link_ok(link) -> bool:
    return isinstance(link, dict) and link.get("host") in HOST_FIELDS and bool(_SLUG.fullmatch(link.get("slug") or ""))


def load_config(path=CONFIG) -> dict:
    cfg = json.loads(Path(path).read_text(encoding="utf-8"))
    envs = cfg.get("environments")
    if not isinstance(envs, dict) or not envs:
        raise TargetError(f"{path}: 'environments' must be a non-empty object")
    for name, e in envs.items():
        for key in ("backend_url", "key_secret", *HOST_FIELDS):
            if not isinstance(e.get(key), str) or not e[key]:
                raise TargetError(f"{path}: environment '{name}' is missing '{key}'")
        if not e["backend_url"].startswith("https://"):
            raise TargetError(f"{path}: environment '{name}' backend_url must be https")
        if not isinstance(e.get("override_backend"), bool):
            raise TargetError(f"{path}: environment '{name}' needs a boolean 'override_backend'")
        checks = e.get("backend_checks")
        if not isinstance(checks, dict) or set(checks) != set(BACKEND_CHECKS) \
                or any(not isinstance(checks[c], bool) for c in BACKEND_CHECKS):
            raise TargetError(f"{path}: environment '{name}' needs backend_checks with a boolean "
                              f"{', '.join(BACKEND_CHECKS)} (and nothing else)")
    if cfg.get("default_environment") not in envs:
        raise TargetError(f"{path}: default_environment must be one of {sorted(envs)}")
    for alias, target in (cfg.get("aliases") or {}).items():
        if target not in envs:
            raise TargetError(f"{path}: alias '{alias}' points at unknown environment '{target}'")
    links = cfg.get("links") or {}
    if set(links) != set(SLOTS):
        raise TargetError(f"{path}: 'links' must define exactly {list(SLOTS)}")
    for slot, link in links.items():
        if not _link_ok(link):
            raise TargetError(f"{path}: link '{slot}' needs host in {list(HOST_FIELDS)} and a valid slug")
        if "path" in link and not _PATH.fullmatch(link.get("path") or ""):
            raise TargetError(f"{path}: link '{slot}' path must start with '/'")
    lt = cfg.get("link_types")
    if not isinstance(lt, dict):
        raise TargetError(f"{path}: 'link_types' must be an object (type -> environment -> link)")
    for t, per_env in lt.items():
        if not _TYPE.fullmatch(t) or not isinstance(per_env, dict):
            raise TargetError(f"{path}: link_types: type '{t}' needs a lower-case name and an object per environment")
        for env_name, link in per_env.items():
            if env_name not in envs or not _link_ok(link):
                raise TargetError(f"{path}: link_types.{t}.{env_name} needs a known environment, "
                                  f"host in {list(HOST_FIELDS)} and a valid slug")
    lte = cfg.get("link_type_expect")
    if not isinstance(lte, dict) or not _VOUCHER.fullmatch(lte.get("voucher") or "") \
            or not _VOUCHER.fullmatch(lte.get("source") or "") or not _PATH.fullmatch(lte.get("path") or ""):
        raise TargetError(f"{path}: link_type_expect needs path ('/…'), voucher and source")
    rewarded = cfg.get("rewarded_link_types", [])
    if not isinstance(rewarded, list) or any(t not in lt for t in rewarded) or len(set(rewarded)) != len(rewarded):
        raise TargetError(f"{path}: rewarded_link_types must be distinct link types from link_types")
    rl = cfg.get("reward_links", {})
    if not isinstance(rl, dict) or set(rl) - set(REWARD_MODELS):
        raise TargetError(f"{path}: reward_links keys must be from {list(REWARD_MODELS)}")
    for model, per_env in rl.items():
        for env_name, link in (per_env or {}).items():
            if env_name not in envs or not _link_ok(link) or link.get("link_type") not in lt:
                raise TargetError(f"{path}: reward_links.{model}.{env_name} needs a known environment, host, "
                                  "slug and link_type (one of link_types)")
    rev = cfg.get("reward_events")
    if not isinstance(rev, dict) or not isinstance(rev.get("revenue_minor"), int) \
            or isinstance(rev.get("revenue_minor"), bool) or not 0 < rev["revenue_minor"] <= 10**9 \
            or not _EVENT.fullmatch(rev.get("other_event") or "") or not _EVENT.fullmatch(rev.get("revenue_event") or ""):
        raise TargetError(f"{path}: reward_events needs revenue_minor (positive integer), other_event and revenue_event")
    if not _VOUCHER.fullmatch((cfg.get("expect") or {}).get("voucher") or ""):
        raise TargetError(f"{path}: expect.voucher must be a voucher code")
    return cfg


def load_flows(path=FLOWS) -> list[dict]:
    rows = json.loads(Path(path).read_text(encoding="utf-8")).get("flows")
    if not isinstance(rows, list) or not rows:
        raise TargetError(f"{path}: 'flows' must be a non-empty list")
    seen = set()
    for r in rows:
        name = r.get("flow")
        if not isinstance(name, str) or not _ROW.fullmatch(name) or "__" in name or name in seen:
            raise TargetError(f"{path}: bad or duplicate flow name {name!r}")
        seen.add(name)
        if r.get("kind") not in KINDS:
            raise TargetError(f"{path}: {name}: kind must be one of {list(KINDS)}")
        if r.get("consent") not in ("allow", "deny"):
            raise TargetError(f"{path}: {name}: consent must be allow or deny")
        if not isinstance(r.get("yaml"), str) or not (HERE / "flows" / r["yaml"]).is_file():
            raise TargetError(f"{path}: {name}: yaml {r.get('yaml')!r} is not a file in e2e/flows")
        if not isinstance(r.get("expected"), str) or not r["expected"]:
            raise TargetError(f"{path}: {name}: 'expected' must say what the row asserts")
        kind = r["kind"]
        needs_slot = kind in ("deferred", "problistic", "reengagement") and not r.get("link_type_only")
        if needs_slot and r.get("slot") not in SLOTS:
            raise TargetError(f"{path}: {name}: slot must be one of {list(SLOTS)}")
        if kind == "reward" and r.get("reward_model") not in REWARD_MODELS:
            raise TargetError(f"{path}: {name}: reward_model must be one of {list(REWARD_MODELS)}")
        if r.get("link_type_only") and not r.get("link_type_matrix"):
            raise TargetError(f"{path}: {name}: link_type_only needs link_type_matrix")
        if kind == "reopen" and not r.get("link_type_only"):
            raise TargetError(f"{path}: {name}: reopen rows run per link type only (link_type_only)")
    return rows


def resolve_environment(cfg: dict, requested: str) -> tuple[str, str]:
    req = (requested or "").strip().lower()
    name = req or cfg["default_environment"]
    name = (cfg.get("aliases") or {}).get(name, name)
    if name not in cfg["environments"]:
        choices = sorted(set(cfg["environments"]) | set(cfg.get("aliases") or {}))
        raise TargetError(f"unknown e2e environment '{requested}': use one of {', '.join(choices)}")
    return name, req or name


def resolve_link(cfg: dict, env_name: str, slot: str, value: str) -> str:
    """A slot's input (empty, bare slug or full URL) → the https URL to test, validated."""
    env = cfg["environments"][env_name]
    host_field = cfg["links"][slot]["host"]
    host = env[host_field].lower()
    raw = (value or "").strip()
    where = f"{env_var(slot)} / {slot}"
    if not raw:
        return f"https://{host}/{cfg['links'][slot]['slug']}"
    if "://" not in raw:
        if not _SLUG.fullmatch(raw):
            raise TargetError(f"{where}: '{raw}' is neither a slug nor a full URL (https://{host}/<slug>)")
        return f"https://{host}/{raw}"
    try:
        u = urllib.parse.urlsplit(raw)
        port = u.port
    except ValueError as exc:
        raise TargetError(f"{where}: '{raw}' is not a valid URL ({exc})") from None
    if u.scheme != "https" or u.username or u.password or port is not None or u.query or u.fragment:
        raise TargetError(f"{where}: '{raw}' must be https://<host>/<slug> (no credentials, port, query or fragment)")
    got = (u.hostname or "").lower()
    if got != host:
        raise TargetError(f"{where}: host '{got or '<none>'}' is not the {env_name} "
                          f"{host_field.replace('_', ' ')} '{host}'. Pick the matching environment or a {env_name} link.")
    slug = u.path[1:] if u.path.startswith("/") else ""
    if not _SLUG.fullmatch(slug):
        raise TargetError(f"{where}: '{raw}' needs exactly one path segment, the slug (https://{host}/<slug>)")
    return f"https://{host}/{slug}"


def select_link_types(cfg: dict, value: str) -> list[str]:
    known = list(cfg["link_types"])
    raw = (value or "").strip().lower()
    if raw in ("", "all"):
        return known
    if raw == "none":
        return []
    wanted = [x.strip() for x in raw.split(",") if x.strip()]
    unknown = [t for t in wanted if t not in known]
    if unknown or not wanted:
        raise TargetError(f"E2E_LINK_TYPES: unknown or empty '{raw}' (use all, none or a comma list of {', '.join(known)})")
    return [t for t in known if t in wanted]


def _url(cfg: dict, env_name: str, link: dict) -> str:
    return f"https://{cfg['environments'][env_name][link['host']].lower()}/{link['slug']}"


def resolve(environ=None, config=CONFIG) -> dict:
    """The full set of resolved values (ordered). Raises TargetError on a bad choice."""
    environ = os.environ if environ is None else environ
    cfg = load_config(config)
    name, requested = resolve_environment(cfg, environ.get("LINKTRAIL_ENV", ""))
    env = cfg["environments"][name]
    voucher = (environ.get("E2E_EXPECT_VOUCHER") or "").strip() or cfg["expect"]["voucher"]
    if not _VOUCHER.fullmatch(voucher):
        raise TargetError(f"E2E_EXPECT_VOUCHER: '{voucher}' must be a voucher code (letters, digits, '-' or '_')")
    selected = select_link_types(cfg, environ.get("E2E_LINK_TYPES", ""))
    run = [t for t in selected if cfg["link_types"][t].get(name)]
    out = {
        "LINKTRAIL_ENV": name,
        "E2E_ENV_REQUESTED": requested,
        "BACKEND_URL": env["backend_url"],
        "BASE_OVERRIDE": env["backend_url"] if env["override_backend"] else "",
        "KEY_SECRET": env["key_secret"],
        "SUBDOMAIN_HOST": env["subdomain_host"],
        "CUSTOM_HOST": env["custom_host"],
        # The custom host goes into the example's linkDomains (*.linktrail.io needs no entry).
        "E2E_LINK_DOMAINS": env["custom_host"],
        "E2E_CHECK_EARNING": "1" if env["backend_checks"]["earning"] else "0",
        "E2E_CHECK_OPEN_COUNT": "1" if env["backend_checks"]["reengagement_open_count"] else "0",
        "E2E_CHECK_EVENTS": "1" if env["backend_checks"]["events"] else "0",
    }
    for slot in SLOTS:
        out[env_var(slot)] = resolve_link(cfg, name, slot, environ.get(env_var(slot), ""))
    out.update({
        "E2E_EXPECT_VOUCHER": voucher,
        "E2E_LINK_TYPES": ",".join(selected) if selected else "none",
        "E2E_LINK_TYPES_RUN": ",".join(run),
        "E2E_LINK_TYPES_SKIPPED": ",".join(t for t in selected if t not in run),
        "E2E_REWARDED_LINK_TYPES": ",".join(cfg.get("rewarded_link_types") or []),
        "E2E_REVENUE_MINOR": str(cfg["reward_events"]["revenue_minor"]),
        "E2E_OTHER_EVENT": cfg["reward_events"]["other_event"],
        "E2E_REVENUE_EVENT": cfg["reward_events"]["revenue_event"],
    })
    return out


def _custom_data_re(voucher: str, link_type: str = "", source: str = "") -> str:
    # E2EState.formatCustomData sorts the keys: linkType < source < voucher.
    parts = []
    if link_type:
        parts.append("linkType=" + java_regex_literal(link_type))
    if source:
        parts.append("source=" + java_regex_literal(source))
    parts.append("voucher=" + java_regex_literal(voucher))
    return "customData: .*" + ".*".join(parts) + ".*"


def plan(args: list[str], environ=None, config=CONFIG, flows=FLOWS) -> list[dict]:
    """The rows to run, in the table's order (link-type rows after the plain ones, type by type)."""
    environ = os.environ if environ is None else environ
    cfg = load_config(config)
    values = resolve(environ, config)
    name = values["LINKTRAIL_ENV"]
    table = load_flows(flows)
    by_name = {r["flow"]: r for r in table}
    selected_types = [t for t in values["E2E_LINK_TYPES"].split(",") if t and t != "none"]
    lte = cfg["link_type_expect"]
    voucher = values["E2E_EXPECT_VOUCHER"]

    want_plain: set[str] = set()
    want_types: dict[str, set[str]] = {}
    if not args:
        want_plain = {r["flow"] for r in table}
        want_types = {r["flow"]: set(selected_types) for r in table if r.get("link_type_matrix")}
    for a in args:
        a = a.removesuffix(".yaml")
        base, _, lt = a.partition("__")
        row = by_name.get(base)
        if row is None:
            raise TargetError(f"unknown e2e row '{a}' (rows: {', '.join(by_name)})")
        if lt:
            if not row.get("link_type_matrix"):
                raise TargetError(f"'{base}' has no link-type rows")
            if lt not in cfg["link_types"]:
                raise TargetError(f"unknown link type '{lt}' (link types: {', '.join(cfg['link_types'])})")
            want_types.setdefault(base, set()).add(lt)
        else:
            want_plain.add(base)
            if row.get("link_type_matrix"):
                want_types.setdefault(base, set()).update(selected_types)

    def mk(r, row, url="", link_type="", reward_model="", path_re="", custom_re="", skip=""):
        return {"row": row, "yaml": r["yaml"], "kind": r["kind"], "consent": r["consent"], "url": url,
                "link_type": link_type, "reward_model": reward_model, "path_re": path_re,
                "custom_data_re": custom_re, "skip": skip}

    out: list[dict] = []
    for r in table:
        f = r["flow"]
        if f not in want_plain or r.get("link_type_only"):
            continue
        kind = r["kind"]
        if kind in ("deferred", "problistic", "reengagement"):
            slot = r["slot"]
            path = cfg["links"][slot].get("path", "")
            out.append(mk(r, f, url=values[env_var(slot)],
                          path_re=java_regex_literal(path) if path else "/.+",
                          custom_re=_custom_data_re(voucher)))
        elif kind == "reward":
            model = r["reward_model"]
            link = (cfg.get("reward_links") or {}).get(model, {}).get(name)
            if link:
                out.append(mk(r, f, url=_url(cfg, name, link), link_type=link["link_type"], reward_model=model,
                              path_re=java_regex_literal(lte["path"]), custom_re=_custom_data_re(lte["voucher"])))
            else:
                out.append(mk(r, f, reward_model=model, skip=f"no {name} {model} link in e2e/e2e-env.json reward_links"))
        else:
            out.append(mk(r, f))
    for t in cfg["link_types"]:
        for r in table:
            if t not in want_types.get(r["flow"], set()):
                continue
            row = f"{r['flow']}__{t}"
            link = cfg["link_types"][t].get(name)
            if not link:
                out.append(mk(r, row, link_type=t, skip=f"no {name} link for link type {t} in e2e/e2e-env.json"))
                continue
            allow = r["consent"] == "allow"
            out.append(mk(r, row, url=_url(cfg, name, link), link_type=t,
                          path_re=java_regex_literal(lte["path"]),
                          custom_re=_custom_data_re(lte["voucher"], t if allow else "", lte["source"] if allow else "")))
    return out


SEP = "\x1f"
PLAN_FIELDS = ("row", "yaml", "kind", "consent", "url", "link_type", "reward_model", "path_re", "custom_data_re", "skip")


def format_values(values: dict, fmt: str) -> str:
    lines = []
    for k, v in values.items():
        if "\n" in v or "\r" in v:
            raise TargetError(f"{k}: value has a line break")
        lines.append(f"{k}={shlex.quote(v)}" if fmt == "shell" else f"{k}={v}")
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("resolve")
    r.add_argument("--format", choices=["shell", "env"], default="shell")
    pl = sub.add_parser("plan")
    pl.add_argument("rows", nargs="*")
    a = p.parse_args(argv)
    try:
        if a.cmd == "resolve":
            values = resolve()
            sys.stdout.write(format_values(values, a.format))
            alias = f" (requested '{values['E2E_ENV_REQUESTED']}')" if values["E2E_ENV_REQUESTED"] != values["LINKTRAIL_ENV"] else ""
            print(f"e2e targets: environment {values['LINKTRAIL_ENV']}{alias}, backend {values['BACKEND_URL']}", file=sys.stderr)
            for slot in SLOTS:
                print(f"  {slot}: {values[env_var(slot)]}", file=sys.stderr)
            if values["E2E_LINK_TYPES_RUN"]:
                print(f"  link types: {values['E2E_LINK_TYPES_RUN']}", file=sys.stderr)
            if values["E2E_LINK_TYPES_SKIPPED"]:
                print(f"NOTICE: link types skipped on {values['LINKTRAIL_ENV']} (no link in e2e/e2e-env.json): "
                      f"{values['E2E_LINK_TYPES_SKIPPED']}", file=sys.stderr)
        else:
            for row in plan(a.rows):
                if any(SEP in row[k] or "\n" in row[k] for k in PLAN_FIELDS):
                    raise TargetError(f"{row['row']}: a value has a separator or line break")
                print(SEP.join(row[k] for k in PLAN_FIELDS))
    except (TargetError, OSError, json.JSONDecodeError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::error title=e2e targets::{exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
