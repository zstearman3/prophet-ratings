# python_lstsq_solver.py

import sys
import json
import numpy as np

# Read JSON from stdin
data = json.load(sys.stdin)
A = np.array(data["a"])
b = np.array(data["b"])
w = np.array(data.get("w", [1.0] * len(b)))
alpha = data.get("ridge_alpha", 0.0)

W = np.diag(w)
ATA = A.T @ W @ A
ATb = A.T @ W @ b
ridge_term = alpha * np.identity(ATA.shape[0])

# Solve using least squares (returns x)
x = np.linalg.solve(ATA + ridge_term, ATb)

# Output result as JSON list
print(json.dumps(x.tolist()))
