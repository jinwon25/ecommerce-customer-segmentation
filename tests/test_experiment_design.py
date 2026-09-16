import math
import unittest

from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize


class ExperimentDesignTest(unittest.TestCase):
    def test_sample_size_sensitivity_table(self) -> None:
        scenarios = {
            (0.05, 0.03): 1_268,
            (0.05, 0.05): 514,
            (0.05, 0.10): 161,
            (0.10, 0.03): 2_142,
            (0.10, 0.05): 824,
            (0.10, 0.10): 237,
        }

        for (baseline, absolute_mde), expected in scenarios.items():
            with self.subTest(baseline=baseline, absolute_mde=absolute_mde):
                effect = abs(
                    proportion_effectsize(baseline + absolute_mde, baseline)
                )
                calculated = math.ceil(
                    NormalIndPower().solve_power(
                        effect_size=effect,
                        power=0.80,
                        alpha=0.025,
                        ratio=1,
                        alternative="two-sided",
                    )
                )
                self.assertEqual(calculated, expected)


if __name__ == "__main__":
    unittest.main()
