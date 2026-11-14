"""Tests for e2e/e2e-verify.py: the backend rules for each row. Stdlib only:
python3 -m unittest discover -s e2e/tests"""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("e2e_verify", HERE.parent / "e2e-verify.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

ALLOW = {"installRecorded": True, "attributed": True, "matchType": "click_token", "installCount": 1, "openCount": 0,
         "linkType": "influencer", "reward": {"model": "per_install", "amountMinor": 50, "currency": "GBP"},
         "earning": {"counted": True, "amountMinor": 50, "currency": "GBP", "excludedAsFraud": False},
         "fraudReasons": []}
DENY = {"installRecorded": False, "attributed": False, "matchType": None, "installCount": 0, "openCount": 0,
        "linkType": "influencer", "reward": {"model": "per_install", "amountMinor": 50, "currency": "GBP"},
        "earning": {"counted": False, "amountMinor": 0, "currency": "GBP", "excludedAsFraud": False},
        "fraudReasons": []}


def tmp(d) -> str:
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(d, f)
    f.close()
    return f.name


def run(*args) -> tuple[str, str, list[list[str]]]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        v.main(list(args))
    lines = out.getvalue().splitlines()
    return lines[0], lines[1], [l.split("\t")[1:] for l in lines[2:] if l.startswith("CHECK")]


def with_(d, **kw):
    d = json.loads(json.dumps(d))
    d.update(kw)
    return d


class InstallTests(unittest.TestCase):
    def test_allow_ok_and_fraud_checked(self):
        status, _, checks = run("check", "--mode", "allow", "--body", tmp(ALLOW))
        self.assertEqual(status, "ok")
        self.assertIn(["fraud", "pass", "excludedAsFraud false, fraudReasons []"], checks)

    def test_allow_not_yet(self):
        status, detail, _ = run("check", "--mode", "allow", "--body", tmp(with_(ALLOW, installRecorded=False, installCount=0)))
        self.assertEqual(status, "bad")
        self.assertIn("installRecorded false", detail)

    def test_duplicate_install_is_bad(self):
        self.assertEqual(run("check", "--mode", "allow", "--body", tmp(with_(ALLOW, installCount=2)))[0], "bad")

    def test_fraud_fails_and_names_the_rule(self):
        d = with_(ALLOW, fraudReasons=["ip_velocity"])
        status, detail, _ = run("check", "--mode", "allow", "--body", tmp(d))
        self.assertEqual(status, "fail")
        self.assertIn("ip_velocity", detail)

    def test_earning_off_skips_fraud(self):
        d = {k: ALLOW[k] for k in ("installRecorded", "attributed", "matchType", "installCount")}
        status, _, checks = run("check", "--mode", "allow", "--body", tmp(d), "--earning", "off")
        self.assertEqual(status, "ok")
        self.assertEqual(checks, [])

    def test_missing_field_when_deployed(self):
        d = {k: ALLOW[k] for k in ("installRecorded", "attributed", "matchType", "installCount")}
        self.assertEqual(run("check", "--mode", "allow", "--body", tmp(d))[0], "missing")

    def test_deny(self):
        self.assertEqual(run("check", "--mode", "deny", "--body", tmp(DENY))[0], "ok")
        self.assertEqual(run("check", "--mode", "deny", "--body", tmp(ALLOW))[0], "bad")


class RewardTests(unittest.TestCase):
    def check(self, mode, d, lt="influencer", earning="on"):
        return run("check", "--mode", mode, "--body", tmp(d), "--link-type", lt, "--rewarded", "influencer,partner",
                   "--earning", earning)

    def test_rewarded_allow_earns_the_reward(self):
        status, _, checks = self.check("allow", ALLOW)
        self.assertEqual(status, "ok")
        self.assertEqual(checks[0][:2], ["link type", "pass"])
        self.assertEqual([c[:2] for c in checks if c[0] == "reward"], [["reward", "pass"]])

    def test_rewarded_allow_not_counted_is_bad(self):
        d = with_(ALLOW, earning={"counted": False, "amountMinor": 0, "currency": "GBP", "excludedAsFraud": False})
        self.assertEqual(self.check("allow", d)[0], "bad")

    def test_amount_comes_from_the_response(self):
        d = with_(ALLOW, reward={"model": "per_install", "amountMinor": 70, "currency": "GBP"})
        self.assertEqual(self.check("allow", d)[0], "bad")
        d["earning"]["amountMinor"] = 70
        self.assertEqual(self.check("allow", d)[0], "ok")

    def test_rewarded_deny_earns_nothing(self):
        self.assertEqual(self.check("deny", DENY)[0], "ok")

    def test_wrong_link_type_fails(self):
        self.assertEqual(self.check("allow", with_(ALLOW, linkType="partner"))[0], "fail")

    def test_unrewarded_type_has_no_reward(self):
        d = with_(ALLOW, linkType="general", reward=None,
                  earning={"counted": False, "amountMinor": 0, "currency": "GBP", "excludedAsFraud": False})
        self.assertEqual(self.check("allow", d, lt="general")[0], "ok")
        self.assertEqual(self.check("allow", with_(d, reward=ALLOW["reward"]), lt="general")[0], "fail")

    def test_earning_off_records_a_skipped_check(self):
        status, _, checks = self.check("allow", ALLOW, earning="off")
        self.assertEqual(status, "ok")
        self.assertEqual(checks[0][:2], ["reward", "skipped"])


class ReopenTests(unittest.TestCase):
    def test_allow_counts_one_open(self):
        base = tmp(ALLOW)
        self.assertEqual(run("check", "--mode", "reopen_allow", "--body", tmp(with_(ALLOW, openCount=1)), "--baseline", base)[0], "ok")
        self.assertEqual(run("check", "--mode", "reopen_allow", "--body", tmp(ALLOW), "--baseline", base)[0], "bad")

    def test_no_second_install_or_reward(self):
        base = tmp(ALLOW)
        d = with_(ALLOW, openCount=1, installCount=2)
        self.assertEqual(run("check", "--mode", "reopen_allow", "--body", tmp(d), "--baseline", base)[0], "bad")
        d = with_(ALLOW, openCount=1, earning={**ALLOW["earning"], "amountMinor": 100})
        self.assertEqual(run("check", "--mode", "reopen_allow", "--body", tmp(d), "--baseline", base)[0], "bad")

    def test_deny_records_nothing(self):
        base = tmp(DENY)
        self.assertEqual(run("check", "--mode", "reopen_deny", "--body", tmp(DENY), "--baseline", base)[0], "ok")
        self.assertEqual(run("check", "--mode", "reopen_deny", "--body", tmp(with_(DENY, openCount=1)), "--baseline", base)[0], "bad")

    def test_open_count_off_is_skipped(self):
        status, _, checks = run("check", "--mode", "reopen_allow", "--body", tmp(ALLOW), "--baseline", tmp(ALLOW),
                                "--open-count", "off")
        self.assertEqual(status, "ok")
        self.assertEqual(checks, [["open count", "skipped", "not on this backend yet (backend_checks.reengagement_open_count)"]])


PER_EVENT = {"model": "per_event", "amountMinor": 30, "currency": "GBP", "eventName": "purchase"}
REV_SHARE = {"model": "rev_share", "amountMinor": None, "currency": "GBP", "rateBps": 1000}
NO_EVENTS = {"count": 0, "byName": {}, "revenue": []}


class EventTests(unittest.TestCase):
    def test_plan_per_event(self):
        d = tmp(with_(ALLOW, reward=PER_EVENT, earning={**ALLOW["earning"], "amountMinor": 0}))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            v.main(["plan-events", "--model", "per_event", "--body", d, "--revenue-minor", "1999",
                    "--other-event", "e2e_other", "--revenue-event", "e2e_revenue"])
        status, _, spec_, n = out.getvalue().splitlines()
        self.assertEqual((status, spec_, n), ("ok", "purchase;purchase;e2e_other", "3"))

    def test_plan_rev_share_sends_two_currencies(self):
        status, _, spec_, n = v.plan_events("rev_share", with_(ALLOW, reward=REV_SHARE), 1999, "e2e_other", "e2e_revenue")
        self.assertEqual((status, spec_, n), ("ok", "e2e_revenue,19.99,GBP;e2e_revenue,19.99,USD", 2))
        self.assertEqual(v.plan_events("rev_share", with_(ALLOW, reward={**REV_SHARE, "currency": "USD"}), 1999, "o", "r")[2],
                         "r,19.99,USD;r,19.99,EUR")

    def test_plan_wrong_model_fails(self):
        self.assertEqual(v.plan_events("per_event", with_(ALLOW, reward=REV_SHARE), 1, "o", "r")[0], "fail")

    def test_major_units(self):
        self.assertEqual(v.major_units(1999, "JPY"), "1999")
        self.assertEqual(v.major_units(5, "GBP"), "0.05")
        self.assertEqual(v.major_units(1999, "KWD"), "1.999")

    def events(self, mode, d, base, model):
        return run("check", "--mode", mode, "--body", tmp(d), "--baseline", tmp(base), "--model", model,
                   "--revenue-minor", "1999", "--other-event", "e2e_other", "--revenue-event", "e2e_revenue")

    def test_per_event_allow(self):
        base = with_(ALLOW, reward=PER_EVENT, earning={**ALLOW["earning"], "amountMinor": 0}, events=NO_EVENTS)
        d = with_(base, earning={**ALLOW["earning"], "amountMinor": 60},
                  events={"count": 3, "byName": {"purchase": 2, "e2e_other": 1}, "revenue": []})
        status, _, checks = self.events("events_allow", d, base, "per_event")
        self.assertEqual(status, "ok")
        self.assertEqual([c[:2] for c in checks], [["event earning", "pass"], ["events", "pass"]])
        self.assertEqual(self.events("events_allow", with_(d, earning={**ALLOW["earning"], "amountMinor": 30}), base, "per_event")[0], "bad")

    def test_rev_share_allow(self):
        base = with_(ALLOW, linkType="partner", reward=REV_SHARE, earning={**ALLOW["earning"], "amountMinor": 0})
        d = with_(base, earning={**ALLOW["earning"], "amountMinor": 199},
                  events={"count": 2, "byName": {"e2e_revenue": 2},
                          "revenue": [{"currency": "GBP", "amountMinor": 1999}, {"currency": "USD", "amountMinor": 1999}]})
        self.assertEqual(self.events("events_allow", d, base, "rev_share")[0], "ok")
        # The other currency must not count towards the earning.
        self.assertEqual(self.events("events_allow", with_(d, earning={**ALLOW["earning"], "amountMinor": 398}), base, "rev_share")[0], "bad")

    def test_baseline_must_be_zero(self):
        base = with_(ALLOW, reward=PER_EVENT)  # earning 50: something was earned before any event
        d = with_(base, earning={**ALLOW["earning"], "amountMinor": 60},
                  events={"count": 3, "byName": {"purchase": 2, "e2e_other": 1}, "revenue": []})
        self.assertEqual(self.events("events_allow", d, base, "per_event")[0], "fail")

    def test_deny_events_dropped(self):
        base = with_(DENY, reward=PER_EVENT, events=NO_EVENTS)
        self.assertEqual(self.events("events_deny", base, base, "per_event")[0], "ok")
        leaked = with_(base, events={"count": 1, "byName": {"purchase": 1}, "revenue": []})
        self.assertEqual(self.events("events_deny", leaked, base, "per_event")[0], "bad")

    def test_events_off_is_skipped(self):
        base = with_(DENY, reward=PER_EVENT)
        status, _, checks = run("check", "--mode", "events_deny", "--body", tmp(base), "--baseline", tmp(base),
                                "--model", "per_event", "--events", "off")
        self.assertEqual(status, "ok")
        self.assertEqual(checks[-1][:2], ["events", "skipped"])

    def test_reward_install_step(self):
        d = with_(ALLOW, linkType="partner", reward=REV_SHARE, earning={**ALLOW["earning"], "amountMinor": 0})
        args = ["check", "--mode", "allow", "--link-type", "partner", "--model", "rev_share"]
        self.assertEqual(run(*args, "--body", tmp(d))[0], "ok")
        self.assertEqual(run(*args, "--body", tmp(with_(d, reward=PER_EVENT)))[0], "fail")


if __name__ == "__main__":
    unittest.main()
