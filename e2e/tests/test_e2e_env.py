"""Tests for e2e/e2e-env.py: the env table, link validation and the row plan. Stdlib only:
python3 -m unittest discover -s e2e/tests"""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("e2e_env", HERE.parent / "e2e-env.py")
env = importlib.util.module_from_spec(spec)
spec.loader.exec_module(env)

CFG = json.loads(env.CONFIG.read_text())


def write(cfg) -> Path:
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(cfg, f)
    f.close()
    return Path(f.name)


class ConfigTests(unittest.TestCase):
    def test_shipped_files_load(self):
        env.load_config()
        rows = env.load_flows()
        self.assertGreater(len(rows), 10)

    def test_prod_has_no_per_event_link(self):
        # e2e-event is not on prod yet: it must stay unlisted so its rows are skipped.
        self.assertNotIn("prod", CFG["reward_links"]["per_event"])
        self.assertIn("dev", CFG["reward_links"]["per_event"])

    def test_dev_matches_the_native_dev_config(self):
        dev = CFG["environments"]["dev"]
        self.assertEqual(dev["backend_url"], "https://linktrail-backend-k9zl.onrender.com")
        self.assertEqual(dev["key_secret"], "LINKTRAIL_TEST_KEY")
        self.assertEqual((dev["subdomain_host"], dev["custom_host"]), ("kick.test.linktrail.io", "dev-test.kynxlabs.com"))
        self.assertTrue(dev["override_backend"])
        self.assertEqual(CFG["aliases"], {"test": "dev"})

    def test_bad_backend_checks_rejected(self):
        cfg = copy.deepcopy(CFG)
        cfg["environments"]["prod"]["backend_checks"]["extra"] = True
        with self.assertRaises(env.TargetError):
            env.load_config(write(cfg))

    def test_reward_link_needs_known_link_type(self):
        cfg = copy.deepcopy(CFG)
        cfg["reward_links"]["rev_share"]["prod"]["link_type"] = "nope"
        with self.assertRaises(env.TargetError):
            env.load_config(write(cfg))


class ResolveTests(unittest.TestCase):
    def test_defaults_are_prod(self):
        v = env.resolve({})
        self.assertEqual(v["LINKTRAIL_ENV"], "prod")
        self.assertEqual(v["BASE_OVERRIDE"], "")
        self.assertEqual(v["E2E_CUSTOM_LINK"], "https://link.kynxlabs.com/summer-sale")
        self.assertEqual(v["E2E_SUBDOMAIN_PROBLISTIC_LINK"], "https://kick.linktrail.io/ios-problistic")
        self.assertEqual(v["E2E_LINK_DOMAINS"], "link.kynxlabs.com")

    def test_alias_and_override(self):
        v = env.resolve({"LINKTRAIL_ENV": "test"})
        self.assertEqual(v["LINKTRAIL_ENV"], "dev")
        self.assertEqual(v["BASE_OVERRIDE"], "https://linktrail-backend-k9zl.onrender.com")

    def test_slug_and_url_overrides(self):
        v = env.resolve({"E2E_CUSTOM_LINK": "other", "E2E_SUBDOMAIN_LINK": "https://kick.linktrail.io/x"})
        self.assertEqual(v["E2E_CUSTOM_LINK"], "https://link.kynxlabs.com/other")
        self.assertEqual(v["E2E_SUBDOMAIN_LINK"], "https://kick.linktrail.io/x")

    def test_wrong_host_fails(self):
        for bad in ("https://kick.test.linktrail.io/x", "http://kick.linktrail.io/x", "https://kick.linktrail.io/a/b",
                    "https://kick.linktrail.io/x?y=1", "a/b"):
            with self.subTest(bad=bad), self.assertRaises(env.TargetError):
                env.resolve({"E2E_SUBDOMAIN_LINK": bad})

    def test_unknown_env_and_type_fail(self):
        with self.assertRaises(env.TargetError):
            env.resolve({"LINKTRAIL_ENV": "staging"})
        with self.assertRaises(env.TargetError):
            env.resolve({"E2E_LINK_TYPES": "general,nope"})

    def test_bad_voucher_fails(self):
        with self.assertRaises(env.TargetError):
            env.resolve({"E2E_EXPECT_VOUCHER": "a b"})

    def test_values_are_idempotent(self):
        v = env.resolve({})
        self.assertEqual(env.resolve(v), v)


class PlanTests(unittest.TestCase):
    def rows(self, args=(), **environ):
        return {r["row"]: r for r in env.plan(list(args), environ)}

    def test_full_plan_covers_the_native_rows(self):
        rows = self.rows()
        for name in ("consent_allow", "consent_deny", "deferred_subdomain_allow", "deferred_subdomain_deny",
                     "deferred_custom_allow", "deferred_custom_deny", "deferred_custom_allow_problistic",
                     "deferred_custom_deny_problistic", "deferred_subdomain_allow_problistic",
                     "deferred_subdomain_deny_problistic", "reengagement_subdomain_allow", "reengagement_subdomain_deny",
                     "reward_event_allow", "reward_event_deny", "reward_revshare_allow", "reward_revshare_deny",
                     "track_event"):
            self.assertIn(name, rows)
        for t in ("general", "campaign", "influencer", "partner"):
            for f in ("deferred_custom_allow", "deferred_custom_deny", "reengagement_type_allow", "reengagement_type_deny"):
                self.assertIn(f"{f}__{t}", rows)
        # link_type_only: no plain reopen row.
        self.assertNotIn("reengagement_type_allow", rows)

    def test_per_event_skipped_on_prod_not_dev(self):
        prod = self.rows()
        self.assertIn("no prod per_event link", prod["reward_event_allow"]["skip"])
        self.assertEqual(prod["reward_revshare_allow"]["skip"], "")
        self.assertEqual(prod["reward_revshare_allow"]["url"], "https://link.kynxlabs.com/e2e-revshare")
        self.assertEqual(prod["reward_revshare_allow"]["link_type"], "partner")
        dev = self.rows(LINKTRAIL_ENV="dev")
        self.assertEqual(dev["reward_event_allow"]["skip"], "")
        self.assertEqual(dev["reward_event_allow"]["url"], "https://dev-test.kynxlabs.com/e2e-event")

    def test_missing_link_type_is_skipped_not_failed(self):
        cfg = copy.deepcopy(CFG)
        del cfg["link_types"]["partner"]["prod"]
        rows = {r["row"]: r for r in env.plan([], {}, config=write(cfg))}
        self.assertIn("no prod link for link type partner", rows["deferred_custom_allow__partner"]["skip"])
        self.assertEqual(rows["deferred_custom_allow__general"]["skip"], "")

    def test_link_type_rows_assert_meta_on_allow_only(self):
        rows = self.rows()
        allow = rows["deferred_custom_allow__influencer"]
        self.assertEqual(allow["url"], "https://link.kynxlabs.com/e2e-influencer")
        self.assertIn("linkType=influencer", allow["custom_data_re"])
        self.assertIn("source=e2e", allow["custom_data_re"])
        self.assertEqual(allow["path_re"], "/products/aj1")
        self.assertNotIn("linkType", rows["deferred_custom_deny__influencer"]["custom_data_re"])

    def test_selection(self):
        rows = self.rows(["deferred_custom_allow"], E2E_LINK_TYPES="general")
        self.assertEqual(list(rows), ["deferred_custom_allow", "deferred_custom_allow__general"])
        rows = self.rows(["reengagement_type_deny__partner"])
        self.assertEqual(list(rows), ["reengagement_type_deny__partner"])
        self.assertEqual(self.rows(["deferred_custom_allow"], E2E_LINK_TYPES="none").keys(), {"deferred_custom_allow"})
        for bad in (["nope"], ["track_event__general"], ["deferred_custom_allow__nope"]):
            with self.subTest(bad=bad), self.assertRaises(env.TargetError):
                env.plan(bad, {})

    def test_plain_rows_use_their_slot(self):
        rows = self.rows()
        self.assertEqual(rows["deferred_subdomain_allow"]["url"], "https://kick.linktrail.io/discounted-product")
        self.assertEqual(rows["deferred_subdomain_allow"]["path_re"], "/products/aj1")
        self.assertEqual(rows["deferred_custom_allow"]["path_re"], "/.+")
        self.assertEqual(rows["deferred_custom_deny_problistic"]["url"], "https://link.kynxlabs.com/custom-problistic")

    def test_every_flow_file_is_used(self):
        used = {r["yaml"] for r in env.load_flows()} | {"open_link.yaml", "send_events.yaml", "reopen.yaml",
                                                        "deferred_allow.yaml", "deferred_deny.yaml"}
        on_disk = {p.name for p in (HERE.parent / "flows").glob("*.yaml")}
        self.assertEqual(on_disk - used, set())


if __name__ == "__main__":
    unittest.main()
