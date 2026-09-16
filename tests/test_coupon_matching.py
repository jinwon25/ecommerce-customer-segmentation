import unittest

import numpy as np
import pandas as pd

from scripts.run_coupon_matching import (
    bootstrap_difference,
    match_controls_to_treated,
    standardized_mean_difference,
)


class CouponMatchingTest(unittest.TestCase):
    def test_paired_bootstrap_uses_within_pair_differences(self) -> None:
        treated = np.array([1.0, 2.0, 3.0, 4.0])
        control = np.array([0.0, 1.0, 2.0, 3.0])
        estimate, lower, upper = bootstrap_difference(
            treated, control, paired=True, repetitions=200, seed=7
        )
        self.assertEqual(estimate, 1.0)
        self.assertEqual(lower, 1.0)
        self.assertEqual(upper, 1.0)

    def test_smd_is_zero_for_equal_groups(self) -> None:
        values = pd.Series([1.0, 2.0, 3.0])
        self.assertEqual(standardized_mean_difference(values, values), 0.0)

    def test_matching_is_one_to_one_without_replacement(self) -> None:
        frame = pd.DataFrame(
            {
                "customer_id": ["t1", "t2", "t3", "t4", "c1", "c2"],
                "coupon_used": [1, 1, 1, 1, 0, 0],
                "propensity_score": [0.30, 0.40, 0.60, 0.70, 0.39, 0.61],
            }
        )
        pairs, _ = match_controls_to_treated(frame)
        self.assertEqual(len(pairs), 2)
        self.assertEqual(pairs["treated_index"].nunique(), 2)
        self.assertEqual(pairs["control_index"].nunique(), 2)

    def test_matching_breaks_equal_distance_ties_by_customer_id(self) -> None:
        frame = pd.DataFrame(
            {
                "customer_id": ["t2", "t1", "c1"],
                "coupon_used": [1, 1, 0],
                "propensity_score": [0.5, 0.5, 0.5],
            }
        )
        pairs, _ = match_controls_to_treated(frame)
        chosen = frame.loc[int(pairs.iloc[0]["treated_index"]), "customer_id"]
        self.assertEqual(chosen, "t1")


if __name__ == "__main__":
    unittest.main()
