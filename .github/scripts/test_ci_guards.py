import datetime
import unittest

from cloud_window import validate_expiry
from tf_plan_summary import summarize


class CloudWindowTest(unittest.TestCase):
    def test_authorized_window_and_timezone(self):
        now = datetime.datetime(2026, 11, 9, 18, tzinfo=datetime.timezone.utc)
        for value in ("2026-11-12T18:00:00Z", "2026-11-09T15:01:00-03:00"):
            validate_expiry(value, now)

    def test_missing_expired_naive_and_overlong_rejected(self):
        now = datetime.datetime(2026, 11, 9, 18, tzinfo=datetime.timezone.utc)
        for value in ("", "invalid", "2026-11-09T18:00:00Z", "2026-11-08T18:00:00Z",
                      "2026-11-10T18:00:00", "2026-11-12T18:00:01Z"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_expiry(value, now)


class PlanSummaryTest(unittest.TestCase):
    def test_no_values_names_or_outputs_in_public_summary(self):
        private = "PRIVATE_SENTINEL_MUST_NOT_APPEAR"
        plan = {
            "resource_changes": [{
                "address": private, "name": private, "type": "aws_secretsmanager_secret_version",
                "change": {"actions": ["create"], "after": {"secret_string": private}},
            }],
            "output_changes": {private: {"after": private, "sensitive": True}},
        }
        result = summarize(plan)
        self.assertNotIn(private, result)
        self.assertIn("aws_secretsmanager_secret_version | create | 1", result)


if __name__ == "__main__":
    unittest.main()
