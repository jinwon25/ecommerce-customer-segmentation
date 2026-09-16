import unittest
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
TABLEAU_DATA = ROOT / "tableau" / "data"


class TableauDataTest(unittest.TestCase):
    def test_expected_aggregate_sources_exist(self) -> None:
        expected = {
            "segment_revenue_share.csv",
            "cohort_retention_long.csv",
            "activity_ladder_summary.csv",
            "matched_effects.csv",
            "matched_balance.csv",
        }
        actual = {path.name for path in TABLEAU_DATA.glob("*.csv")}
        self.assertEqual(actual, expected)

    def test_cohort_long_contains_only_observed_months(self) -> None:
        cohort = pd.read_csv(TABLEAU_DATA / "cohort_retention_long.csv")
        self.assertEqual(len(cohort), 78)
        self.assertFalse(cohort["retention_pct"].isna().any())
        self.assertEqual(cohort["first_purchase_month"].nunique(), 12)
        self.assertTrue(
            cohort.loc[cohort["month_index"].eq(0), "is_baseline"].all()
        )


if __name__ == "__main__":
    unittest.main()
