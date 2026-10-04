import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location("signing",Path(__file__).resolve().parents[1]/"verify_ios_signing.py")
signing=importlib.util.module_from_spec(spec);spec.loader.exec_module(signing)

class SigningTests(unittest.TestCase):
    def test_stripped_signature(self):
        report=signing.capability_report({"get-task-allow":True})
        self.assertFalse(report[signing.MEMORY_KEYS[0]]["signed"])
        self.assertIsNone(report[signing.MEMORY_KEYS[0]]["profile"])
        self.assertTrue(report["get-task-allow"]["signed"])

    def test_signature_does_not_grant_profile_permission(self):
        signed=dict.fromkeys(signing.MEMORY_KEYS,True)
        report=signing.capability_report(signed,{"Entitlements":{}})
        self.assertTrue(report[signing.MEMORY_KEYS[0]]["signed"])
        self.assertFalse(report[signing.MEMORY_KEYS[0]]["profile"])
        report=signing.capability_report(signed,{"Entitlements":signed})
        self.assertTrue(report[signing.MEMORY_KEYS[0]]["profile"])

    def test_only_boolean_true_is_authorized(self):
        report=signing.capability_report(dict.fromkeys(signing.MEMORY_KEYS,"true"))
        self.assertFalse(report[signing.MEMORY_KEYS[0]]["signed"])

if __name__=="__main__":unittest.main()
