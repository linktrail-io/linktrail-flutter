#!/usr/bin/env python3
"""Checks one response of the private e2e verify endpoint GET /v1/e2e/clicks/<token> (LinkTrail
contract e2e-verify-endpoint; the same rules as the native SDKs' scripts/e2e-verify.py). Stdlib only.
Called by e2e/verify.sh while it polls the endpoint for one row's own click token.

  check --mode M --body F [options]

prints the status, then one detail line (what the backend said), then one line per check this
response reached, CHECK<TAB>name<TAB>pass|fail|skipped<TAB>detail:

  ok        the response matches the mode
  bad       not (yet): verify.sh keeps polling (allow modes) or stops (deny modes hold the window)
  fail      not, and it won't change (fraud, a wrong link type, a malformed field): stops at once
  missing   the backend lacks a field this check needs although backend_checks says it is deployed

Modes:
  allow         installRecorded, attributed, matchType click_token, installCount 1; with --earning on
                also not fraud (earning.excludedAsFraud false, fraudReasons [])
  deny          installRecorded false, installCount 0
  With --link-type (link-type rows) and --earning on, allow / deny also check linkType and the reward:
    rewarded type (--rewarded)  allow earning.counted true and amountMinor == reward.amountMinor
                                (per_install); deny counted false, 0
    other types                 reward null, earning counted false, 0
  With --model (the reward rows' install step): linkType == --link-type, reward.model == --model and
  earning 0 (no event sent yet).
  reopen_allow  --baseline F (the response after the install): openCount +1, installCount and earning
                unchanged (no second reward); openCount needs --open-count on
  reopen_deny   openCount, installCount and earning unchanged
  events_allow  --model, --baseline: per_event earning == 2 × reward.amountMinor; rev_share
                earning == floor(revenue_minor × rateBps / 10000); with --events on also the click's
                events (byName / count / revenue)
  events_deny   earning 0 and, with --events on, events.count 0

  plan-events --model M --body F --revenue-minor N --other-event E --revenue-event R

prints the status, the detail, the events spec the example's E2E panel sends (name[,value,currency]
joined by ';') and how many events that is: per_event sends reward.eventName twice plus E once;
rev_share sends R once in the reward currency and once in another currency (which adds nothing).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REWARD_EVENTS = 2
# Minor-unit exponents that aren't 2 (ISO 4217), to send revenue_minor as a major-unit value.
_EXPONENT = {"BHD": 3, "CLP": 0, "IQD": 3, "ISK": 0, "JOD": 3, "JPY": 0, "KRW": 0, "KWD": 3, "LYD": 3,
             "OMR": 3, "PYG": 0, "TND": 3, "UGX": 0, "VND": 0, "XAF": 0, "XOF": 0}
FRAUD_RULES = {
    "ip_velocity": "more than 20 installs from one IP in an hour (CI runners share public IPs)",
    "device_repeat": "the same device installed again",
    "ctit_too_short": "the install came under 10 s after its click (MIN_CTIT_WAIT)",
}
CONTRACT = "the e2e-verify-endpoint contract"


def _j(v) -> str:
    return json.dumps(v, ensure_ascii=False)


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _amount(obj):
    if not isinstance(obj, dict):
        return None
    v = obj.get("amountMinor")
    return v if _is_int(v) else None


def _money(obj) -> str:
    if not isinstance(obj, dict):
        return _j(obj)
    cur = obj.get("currency")
    return f"{_j(obj.get('amountMinor'))}{' ' + str(cur) if cur else ''}"


def describe(d: dict) -> str:
    parts = [f"{k}={_j(d.get(k))}" for k in ("installRecorded", "attributed", "matchType", "installCount", "openCount")]
    if "linkType" in d:
        parts.append(f"linkType={d.get('linkType')}")
    if "reward" in d:
        r = d.get("reward")
        parts.append("reward=" + (f"{r.get('model')} {_money(r)}" if isinstance(r, dict) else _j(r)))
    if "earning" in d:
        e = d.get("earning")
        if isinstance(e, dict):
            parts.append(f"earning={'counted' if e.get('counted') is True else 'not counted'} {_money(e)}"
                         + (" (excluded as fraud)" if e.get("excludedAsFraud") is True else ""))
        else:
            parts.append(f"earning={_j(e)}")
    if "events" in d and isinstance(d["events"], dict):
        parts.append(f"events.count={_j(d['events'].get('count'))}")
    return " ".join(parts)


def _missing(field: str) -> str:
    return (f"backend has no {field} field in GET /v1/e2e/clicks/:token ({CONTRACT}); set the matching "
            "backend_checks entry false in e2e/e2e-env.json until it is deployed")


class Result:
    def __init__(self):
        self.status = "ok"
        self.problems: list[str] = []
        self.checks: list[tuple[str, str, str]] = []

    def worse(self, status: str, problem: str):
        rank = {"ok": 0, "bad": 1, "fail": 2, "missing": 3}
        if rank[status] > rank[self.status]:
            self.status = status
        self.problems.append(problem)

    def check(self, name: str, status: str, detail: str):
        self.checks.append((name, status, detail))


def install_check(res: Result, mode: str, d: dict):
    if mode == "allow":
        want = {"installRecorded": True, "attributed": True, "matchType": "click_token", "installCount": 1}
    else:
        want = {"installRecorded": False, "installCount": 0}
    for k, v in want.items():
        if d.get(k) != v or type(d.get(k)) is not type(v):
            res.worse("bad", f"{k} {_j(d.get(k))} (want {_j(v)})")


def fraud_check(res: Result, d: dict):
    """A counted allow install must not be fraud. The failure names the rule."""
    if "fraudReasons" not in d:
        res.worse("missing", _missing("fraudReasons"))
        res.check("fraud", "fail", "no fraudReasons field")
        return
    reasons = d.get("fraudReasons")
    e = d.get("earning")
    excluded = e.get("excludedAsFraud") if isinstance(e, dict) else None
    if not isinstance(reasons, list):
        res.worse("fail", f"fraudReasons {_j(reasons)} (want a list)")
        res.check("fraud", "fail", "fraudReasons is not a list")
        return
    if excluded is True or reasons:
        why = ", ".join(f"{r} ({FRAUD_RULES.get(r, 'see the backend fraud rules')})" for r in reasons) or "no reason recorded"
        res.worse("fail", f"install flagged as fraud: {why}")
        res.check("fraud", "fail", why)
        return
    res.check("fraud", "pass", "excludedAsFraud false, fraudReasons []")


def link_type_check(res: Result, d: dict, link_type: str) -> bool:
    if "linkType" not in d:
        res.worse("missing", _missing("linkType"))
        return False
    if d.get("linkType") != link_type:
        res.worse("fail", f"linkType {_j(d.get('linkType'))} (want {_j(link_type)}: the row's link has the wrong type)")
        res.check("link type", "fail", f"{d.get('linkType')} (want {link_type})")
        return False
    res.check("link type", "pass", link_type)
    return True


def reward_check(res: Result, mode: str, d: dict, link_type: str, rewarded: list[str]):
    for field in ("earning", "reward"):
        if field not in d:
            res.worse("missing", _missing(field))
            return
    link_type_check(res, d, link_type)
    reward, earning = d.get("reward"), d.get("earning")
    if not isinstance(earning, dict):
        res.worse("fail", f"earning {_j(earning)} (want an object)")
        return
    counted, amount = earning.get("counted"), _amount(earning)
    before = len(res.problems)
    if link_type in rewarded:
        if not isinstance(reward, dict) or _amount(reward) is None:
            res.worse("bad", f"reward {_j(reward)} (want the {link_type} link's per_install reward with amountMinor)")
        elif mode == "allow":
            if reward.get("model") != "per_install":
                res.worse("fail", f"reward.model {_j(reward.get('model'))} (want per_install on a link-type row)")
            else:
                if counted is not True:
                    res.worse("bad", f"earning.counted {_j(counted)} (want true: the counted install earns the reward)")
                if amount != _amount(reward):
                    res.worse("bad", f"earning.amountMinor {_j(earning.get('amountMinor'))} (want {_amount(reward)}: reward.amountMinor)")
        if mode == "deny":
            if counted is not False:
                res.worse("bad", f"earning.counted {_j(counted)} (want false: a denied install earns nothing)")
            if amount != 0:
                res.worse("bad", f"earning.amountMinor {_j(earning.get('amountMinor'))} (want 0: a denied install earns nothing)")
    else:
        if reward is not None:
            res.worse("fail", f"reward {_j(reward)} (want null: {link_type} links carry no reward)")
        if counted is not False or amount != 0:
            res.worse("bad", f"earning {_money(earning)} counted={_j(counted)} (want not counted, 0: no reward)")
    ok = len(res.problems) == before
    res.check("reward", "pass" if ok else "fail", f"reward {_money(reward)}, earning {_money(earning)}")


def event_reward(d: dict, model: str) -> tuple[str, str, dict | None]:
    if "reward" not in d:
        return "missing", _missing("reward"), None
    r = d.get("reward")
    if not isinstance(r, dict):
        return "fail", f"reward {_j(r)} (want the link's {model} reward)", None
    if r.get("model") != model:
        return "fail", f"reward.model {_j(r.get('model'))} (want {_j(model)}: the link is set up with another model)", None
    if model == "per_event" and (_amount(r) is None or not isinstance(r.get("eventName"), str) or not r["eventName"]):
        return "fail", f"reward {_j(r)} (want amountMinor and eventName for per_event)", None
    if model == "rev_share" and (not _is_int(r.get("rateBps")) or not r.get("currency")):
        return "fail", f"reward {_j(r)} (want rateBps and currency for rev_share)", None
    return "ok", "", r


def reward_install_check(res: Result, d: dict, link_type: str, model: str):
    """The reward rows' install step: the right link and model, and nothing earned before any event."""
    link_type_check(res, d, link_type)
    status, problem, _ = event_reward(d, model)
    if status != "ok":
        res.worse(status, problem)
        return
    e = d.get("earning")
    if "earning" not in d:
        res.worse("missing", _missing("earning"))
    elif _amount(e) != 0:
        res.worse("fail", f"earning {_money(e)} before any event (want 0)")


def reopen_check(res: Result, mode: str, d: dict, base: dict, open_count: bool):
    if d.get("installCount") != base.get("installCount"):
        res.worse("bad", f"installCount {_j(d.get('installCount'))} (want {_j(base.get('installCount'))}: "
                         "re-engagement must not record a second install)")
    if "earning" in base and d.get("earning") != base.get("earning"):
        res.worse("bad", f"earning {_money(d.get('earning'))} (want {_money(base.get('earning'))} as after the install: no second reward)")
    if not open_count:
        res.check("open count", "skipped", "not on this backend yet (backend_checks.reengagement_open_count)")
        return
    if "openCount" not in d or not _is_int(base.get("openCount")):
        res.worse("missing", _missing("openCount"))
        return
    want = base["openCount"] + (1 if mode == "reopen_allow" else 0)
    if d.get("openCount") != want:
        why = "the open must be recorded once" if mode == "reopen_allow" else "an open without consent records nothing"
        res.worse("bad", f"openCount {_j(d.get('openCount'))} (want {want}: {why})")
        res.check("open count", "fail", f"{base['openCount']}→{d.get('openCount')} (want {want})")
    else:
        res.check("open count", "pass", f"{base['openCount']}→{want}")


def other_currency(currency: str) -> str:
    return "EUR" if currency.upper() == "USD" else "USD"


def major_units(minor: int, currency: str) -> str:
    exp = _EXPONENT.get(currency.upper(), 2)
    if exp == 0:
        return str(minor)
    return f"{minor // 10 ** exp}.{minor % 10 ** exp:0{exp}d}"


def events_check(res: Result, d: dict, model: str, reward: dict, consent: str, other_event: str,
                 revenue_event: str, revenue_minor: int):
    if "events" not in d:
        res.worse("missing", _missing("events"))
        return
    ev = d.get("events")
    if not isinstance(ev, dict) or not _is_int(ev.get("count")) or not isinstance(ev.get("byName"), dict) \
            or not isinstance(ev.get("revenue"), list):
        res.worse("fail", f"events {_j(ev)} (want {{count, byName, revenue}})")
        res.check("events", "fail", "malformed events field")
        return
    revenue = {}
    for r in ev["revenue"]:
        if not isinstance(r, dict) or not isinstance(r.get("currency"), str) or not _is_int(r.get("amountMinor")):
            res.worse("fail", f"events.revenue entry {_j(r)} (want {{currency, amountMinor}})")
            return
        revenue[r["currency"].upper()] = r["amountMinor"]
    if consent == "deny":
        want_names, want_rev = {}, {}
    elif model == "per_event":
        want_names, want_rev = {reward["eventName"]: REWARD_EVENTS, other_event: 1}, {}
    else:
        cur = str(reward["currency"]).upper()
        want_names = {revenue_event: 2}
        want_rev = {cur: revenue_minor, other_currency(cur): revenue_minor}
    want_count = sum(want_names.values())
    got = f"count {ev['count']} byName {_j(ev['byName'])} revenue {_j(ev['revenue'])}"
    if ev["count"] != want_count or ev["byName"] != want_names or revenue != want_rev:
        res.worse("bad", f"events {got} (want count {want_count} byName {_j(want_names)} revenue {_j(want_rev)})")
        res.check("events", "fail", got)
    else:
        res.check("events", "pass", got)


def events_earning_check(res: Result, mode: str, d: dict, base: dict, model: str, revenue_minor: int,
                         events_on: bool, other_event: str, revenue_event: str):
    consent = "allow" if mode == "events_allow" else "deny"
    if "earning" not in d:
        res.worse("missing", _missing("earning"))
        return
    if consent == "deny":
        if d.get("installCount") != 0:
            res.worse("bad", f"installCount {_j(d.get('installCount'))} (want 0)")
        if _amount(d.get("earning")) != 0:
            res.worse("bad", f"earning {_money(d.get('earning'))} (want 0: a denied install earns nothing)")
        reward = d.get("reward") if isinstance(d.get("reward"), dict) else {}
    else:
        status, problem, reward = event_reward(d, model)
        if status != "ok":
            res.worse(status, problem)
            return
        if _amount(base.get("earning")) != 0:
            res.worse("fail", f"baseline earning {_money(base.get('earning'))} (want 0 before any event)")
        want = REWARD_EVENTS * _amount(reward) if model == "per_event" else (revenue_minor * reward["rateBps"]) // 10000
        if _amount(d.get("earning")) != want:
            res.worse("bad", f"earning.amountMinor {_j((d.get('earning') or {}).get('amountMinor'))} (want {want}: "
                             + ("2 × reward.amountMinor" if model == "per_event" else
                                f"floor({revenue_minor} × {reward['rateBps']} / 10000)") + ")")
            res.check("event earning", "fail", _money(d.get("earning")))
        else:
            res.check("event earning", "pass", f"{want} ({model})")
    if events_on:
        events_check(res, d, model, reward or {}, consent, other_event, revenue_event, revenue_minor)
    else:
        res.check("events", "skipped", "not on this backend yet (backend_checks.events)")


def plan_events(model: str, d, revenue_minor: int, other_event: str, revenue_event: str):
    """→ (status, detail, spec, count)."""
    if not isinstance(d, dict):
        return "fail", "response is not a JSON object", "", 0
    status, problem, r = event_reward(d, model)
    if status != "ok":
        return status, problem, "", 0
    if model == "per_event":
        if r["eventName"] == other_event:
            return "fail", f"reward.eventName {_j(other_event)} is reward_events.other_event", "", 0
        if any(c in r["eventName"] for c in ",;"):
            return "fail", f"reward.eventName {_j(r['eventName'])} has ',' or ';'", "", 0
        names = [r["eventName"]] * REWARD_EVENTS + [other_event]
        return "ok", f"per_event: {REWARD_EVENTS} × {r['eventName']} + 1 × {other_event}", ";".join(names), len(names)
    cur = str(r["currency"]).upper()
    other = other_currency(cur)
    spec = f"{revenue_event},{major_units(revenue_minor, cur)},{cur};{revenue_event},{major_units(revenue_minor, other)},{other}"
    detail = (f"rev_share: 1 × {revenue_event} {major_units(revenue_minor, cur)} {cur} at {r['rateBps']} bps "
              f"+ 1 × {major_units(revenue_minor, other)} {other} (adds nothing)")
    return "ok", detail, spec, 2


def _load(path):
    if not path:
        return {}
    try:
        d = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return d if isinstance(d, dict) else None


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--mode", required=True, choices=["allow", "deny", "reopen_allow", "reopen_deny", "events_allow", "events_deny"])
    c.add_argument("--body", required=True)
    c.add_argument("--link-type", default="")
    c.add_argument("--rewarded", default="")
    c.add_argument("--model", default="")
    c.add_argument("--baseline", default="")
    c.add_argument("--earning", choices=["on", "off"], default="on")
    c.add_argument("--open-count", choices=["on", "off"], default="on")
    c.add_argument("--events", choices=["on", "off"], default="on")
    c.add_argument("--revenue-minor", type=int, default=0)
    c.add_argument("--other-event", default="e2e_other")
    c.add_argument("--revenue-event", default="e2e_revenue")
    pe = sub.add_parser("plan-events")
    pe.add_argument("--model", required=True, choices=["per_event", "rev_share"])
    pe.add_argument("--body", required=True)
    pe.add_argument("--revenue-minor", type=int, required=True)
    pe.add_argument("--other-event", required=True)
    pe.add_argument("--revenue-event", required=True)
    a = p.parse_args(argv)

    d = _load(a.body)
    if a.cmd == "plan-events":
        status, detail, spec, n = plan_events(a.model, d, a.revenue_minor, a.other_event, a.revenue_event)
        print(status)
        print(detail)
        print(spec)
        print(n)
        return 0

    res = Result()
    if d is None:
        print("bad")
        print("response is not a JSON object")
        return 0
    base = _load(a.baseline) if a.baseline else {}
    earning_on = a.earning == "on"
    if a.mode in ("allow", "deny"):
        install_check(res, a.mode, d)
        if a.model:
            if earning_on:
                reward_install_check(res, d, a.link_type, a.model)
        elif a.link_type:
            if earning_on:
                reward_check(res, a.mode, d, a.link_type, [t for t in a.rewarded.split(",") if t])
            else:
                res.check("reward", "skipped", "not on this backend yet (backend_checks.earning)")
        if a.mode == "allow" and earning_on:
            fraud_check(res, d)
    elif a.mode.startswith("reopen_"):
        if base is None:
            res.worse("fail", "no baseline response from the install step")
        else:
            reopen_check(res, a.mode, d, base, a.open_count == "on")
    else:
        if base is None:
            res.worse("fail", "no baseline response from the install step")
        else:
            events_earning_check(res, a.mode, d, base, a.model, a.revenue_minor, a.events == "on",
                                 a.other_event, a.revenue_event)
    print(res.status)
    print(describe(d) + ("; " + "; ".join(res.problems) if res.problems else ""))
    for name, status, detail in res.checks:
        print(f"CHECK\t{name}\t{status}\t{detail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
