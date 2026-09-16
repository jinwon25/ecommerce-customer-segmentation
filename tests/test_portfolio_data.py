import csv
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "derived"


def read_csv(name: str) -> list[dict[str, str]]:
    with (DATA / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


class PortfolioDataTest(unittest.TestCase):
    def test_segment_snapshot_is_complete_and_reconciled(self) -> None:
        rows = read_csv("segment_revenue_share.csv")
        self.assertEqual(len(rows), 6)
        self.assertEqual(len({row["segment"] for row in rows}), len(rows))
        self.assertEqual(sum(int(row["customers"]) for row in rows), 1_468)
        self.assertTrue(all(float(row["revenue"]) > 0 for row in rows))
        self.assertTrue(
            math.isclose(
                sum(float(row["revenue_share_pct"]) for row in rows),
                100.0,
                abs_tol=0.11,
            )
        )
        top_two = sum(float(row["revenue_share_pct"]) for row in rows[:2])
        self.assertTrue(math.isclose(top_two, 68.3, abs_tol=0.01))

    def test_activity_ladder_is_nested_and_rate_reconciles(self) -> None:
        rows = read_csv("activity_ladder_summary.csv")
        counts = [int(row["reached"]) for row in rows]
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows[0]["stage_name"], "거래 고객")
        self.assertNotIn("첫 구매", {row["stage_name"] for row in rows})
        self.assertEqual(counts, sorted(counts, reverse=True))
        self.assertEqual(counts[0], 1_468)
        for previous, row in zip(counts, rows[1:]):
            expected = int(row["reached"]) / previous * 100
            self.assertTrue(
                math.isclose(
                    float(row["previous_stage_conversion_pct"]),
                    expected,
                    abs_tol=0.01,
                )
            )

    def test_cohort_snapshot_has_observed_triangle_and_m1_average(self) -> None:
        rows = read_csv("cohort_retention_snapshot.csv")
        self.assertEqual(len(rows), 12)
        self.assertEqual(sum(int(row["cohort_size"]) for row in rows), 1_468)
        for cohort_index, row in enumerate(rows):
            observed = [row[f"m{i}"] for i in range(12) if row[f"m{i}"] != ""]
            self.assertEqual(len(observed), 12 - cohort_index)
            self.assertEqual(float(row["m0"]), 100.0)
        m1 = [float(row["m1"]) for row in rows[:-1]]
        self.assertTrue(math.isclose(sum(m1) / len(m1), 9.68, abs_tol=0.01))

    def test_matched_estimates_are_inside_intervals(self) -> None:
        rows = read_csv("matched_effects.csv")
        self.assertEqual(len(rows), 4)
        for row in rows:
            estimate = float(row["estimate"])
            lower = float(row["ci_lower"])
            upper = float(row["ci_upper"])
            self.assertLessEqual(lower, estimate)
            self.assertLessEqual(estimate, upper)
            self.assertGreater(int(row["n_treat"]), 0)
            self.assertGreater(int(row["n_control"]), 0)

        matched = {
            row["outcome"]: float(row["estimate"])
            for row in rows
            if row["method"] == "72쌍 매칭 차이"
        }
        self.assertTrue(math.isclose(matched["60일 재구매율"], 34.72, abs_tol=0.01))
        self.assertTrue(math.isclose(matched["60일 상품매출"], 964.75, abs_tol=0.01))

    def test_matched_balance_records_residual_imbalance(self) -> None:
        rows = read_csv("matched_balance.csv")
        self.assertEqual(len(rows), 16)
        failed = sum(abs(float(row["smd_after"])) >= 0.1 for row in rows)
        self.assertEqual(failed, 6)


if __name__ == "__main__":
    unittest.main()
