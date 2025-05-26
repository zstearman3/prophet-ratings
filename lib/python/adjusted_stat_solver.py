import sys
import json
import numpy as np

def log(msg):
    print(f"[Python Solver] {msg}", file=sys.stderr)

try:
    data = json.load(sys.stdin)

    A = np.array(data["a"])
    b = np.array(data["b"])
    w = np.array(data.get("w", [1.0] * len(b)))
    alpha = data.get("ridge_alpha", 0.0)

    log(f"Matrix A shape: {A.shape}")
    log(f"Vector b shape: {b.shape}")
    log(f"Weight vector length: {len(w)}")
    log(f"Ridge alpha: {alpha}")

    if A.shape[0] != len(b):
        raise ValueError("Number of rows in A must match length of b")

    if len(w) != len(b):
        raise ValueError("Length of weight vector must match b")

    W = np.diag(w)
    ATA = A.T @ W @ A
    ATb = A.T @ W @ b
    ridge_term = alpha * np.identity(ATA.shape[0])

    # Optional: log condition number to catch ill-conditioned matrices
    cond_number = np.linalg.cond(ATA + ridge_term)
    log(f"Condition number: {cond_number:.2e}")

    x = np.linalg.solve(ATA + ridge_term, ATb)

    print(json.dumps(x.tolist()))

except Exception as e:
    log(f"❌ Error: {str(e)}")
    sys.exit(1)
