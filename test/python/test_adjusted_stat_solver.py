"""Synthetic checks: run from the repository root in the development Docker image."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


class SolverTest(unittest.TestCase):
    def run_solver(self, payload):
        return subprocess.run(
            [sys.executable, 'lib/python/adjusted_stat_solver.py'], cwd=ROOT,
            input=json.dumps(payload), capture_output=True, text=True, timeout=30,
        )

    def test_known_weighted_ridge_solution(self):
        # Minimize (x-2)^2 + 3(x-4)^2 + 2x^2: x = 14/6.
        result = self.run_solver(dict(a=[[1], [1]], b=[2, 4], w=[1, 3], ridge_alpha=2))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertAlmostEqual(json.loads(result.stdout)[0], 14 / 6)
        self.assertNotIn('Condition number', result.stderr)

    def test_dense_reference_equivalence(self):
        rng = np.random.default_rng(42)
        matrix = rng.normal(size=(25, 6))
        weights = rng.uniform(0, 1, 25)
        weights[0] = 0
        targets = rng.normal(size=25)
        expected = np.linalg.solve(matrix.T @ np.diag(weights) @ matrix + .01 * np.eye(6),
                                   matrix.T @ np.diag(weights) @ targets)
        result = self.run_solver(dict(a=matrix.tolist(), b=targets.tolist(), w=weights.tolist(),
                                      ridge_alpha=.01, diagnostics=True))
        self.assertEqual(result.returncode, 0, result.stderr)
        np.testing.assert_allclose(json.loads(result.stdout), expected, atol=1e-10, rtol=1e-10)
        self.assertIn('Condition number', result.stderr)

    def test_invalid_inputs_fail_without_coefficients(self):
        invalid = [dict(a=[], b=[]), dict(a=[[1, 2], [1]], b=[1, 2]),
                   dict(a=[[1]], b=[1], w=[-1]), dict(a=[[1]], b=[1], ridge_alpha=-1),
                   dict(a=[[1]], b=[1, 2]), dict(a=[[1]], b=[float('nan')]),
                   dict(a=[[1, 1]], b=[2], ridge_alpha=0)]
        for payload in invalid:
            with self.subTest(payload=payload):
                result = self.run_solver(payload)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')

    def test_real_ruby_boundary(self):
        ruby = '''
require 'logger'
require 'open3'
require 'json'
require_relative 'app/services/statistics_utils'
module Rails
  def self.logger; @logger ||= Logger.new($stderr); end
end
result = StatisticsUtils.solve_least_squares_with_python([[1], [1]], [2, 4], weights: [1, 3], ridge_alpha: 2)
raise 'Wrong weighted ridge result' unless (result.first - 14.0 / 6).abs < 1e-10
begin
  StatisticsUtils.solve_least_squares_with_python([[1, 1]], [2], ridge_alpha: 0)
  raise 'Singular solve incorrectly succeeded'
rescue RuntimeError => error
  raise unless error.message.include?('Python solver failed')
end
'''
        result = subprocess.run(['ruby', '-e', ruby], cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
