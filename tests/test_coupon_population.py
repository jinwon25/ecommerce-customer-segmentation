import unittest

import pandas as pd

from scripts.build_coupon_population import build_coupon_population


class CouponPopulationTest(unittest.TestCase):
    def test_population_uses_pre_index_covariates_and_fixed_outcome_window(self) -> None:
        sales = pd.DataFrame(
            {
                "customer_id": [1, 1, 1, 2, 2, 2, 3],
                "transaction_id": [11, 12, 13, 21, 22, 23, 31],
                "transaction_date": pd.to_datetime(
                    [
                        "2019-01-01",
                        "2019-02-01",
                        "2019-02-15",
                        "2019-01-05",
                        "2019-02-01",
                        "2019-02-20",
                        "2019-12-31",
                    ]
                ),
                "product_category": ["A"] * 7,
                "quantity": [1] * 7,
                "unit_price": [10, 20, 30, 10, 20, 40, 1],
                "coupon_status": [
                    "Not Used",
                    "Used",
                    "Not Used",
                    "Not Used",
                    "Clicked",
                    "Not Used",
                    "Not Used",
                ],
            }
        )
        customers = pd.DataFrame(
            {
                "customer_id": [1, 2, 3],
                "gender": ["F", "M", "F"],
                "region": ["X", "Y", "Z"],
                "tenure_months": [2, 3, 4],
            }
        )

        result = build_coupon_population(sales, customers).set_index("customer_id")

        self.assertEqual(set(result.index), {1, 2})
        self.assertEqual(result.loc[1, "coupon_used"], 1)
        self.assertEqual(result.loc[2, "coupon_used"], 0)
        self.assertEqual(result.loc[1, "pre_frequency"], 1)
        self.assertEqual(result.loc[2, "pre_frequency"], 1)
        self.assertEqual(result.loc[1, "product_revenue_60d"], 30)
        self.assertEqual(result.loc[2, "product_revenue_60d"], 40)
        self.assertEqual(result.loc[1, "repurchase_60d"], 1)
        self.assertEqual(result.loc[2, "repurchase_60d"], 1)


if __name__ == "__main__":
    unittest.main()
