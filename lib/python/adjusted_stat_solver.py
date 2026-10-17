import sys
import json
import numpy as np


def log(message):
    print(f"[Python Solver] {message}", file=sys.stderr)


try:
    data = json.load(sys.stdin)
    A = np.asarray(data["a"], dtype=float)
    b = np.asarray(data["b"], dtype=float)
    w = np.asarray(data.get("w", np.ones(b.size)), dtype=float)
    alpha = float(data.get("ridge_alpha", 0.0))

    if A.ndim != 2 or min(A.shape) == 0:
        raise ValueError("Matrix A must be nonempty and two-dimensional")
    if b.shape != (A.shape[0],) or w.shape != b.shape:
        raise ValueError("Targets and weights must be vectors matching matrix rows")
    if not all(np.isfinite(values).all() for values in (A, b, w)):
        raise ValueError("Matrix, targets and weights must be finite")
    if (w < 0).any() or not np.isfinite(alpha) or alpha < 0:
        raise ValueError("Weights and ridge alpha must be nonnegative and finite")

    log(f"Matrix A shape: {A.shape}; ridge alpha: {alpha}")
    # Identical weighted normal equations without an observations-squared array.
    normal = A.T @ (w[:, None] * A)
    target = A.T @ (w * b)
    normal.flat[::normal.shape[0] + 1] += alpha

    if data.get("diagnostics", False):
        log(f"Condition number: {np.linalg.cond(normal):.2e}")

    solution = np.linalg.solve(normal, target)
    if not np.isfinite(solution).all():
        raise ValueError("Solver returned nonfinite coefficients")
    print(json.dumps(solution.tolist(), allow_nan=False))
except Exception as error:
    log(f"Error: {error}")
    sys.exit(1)
