# python_lstsq_solver.py

import sys
import json
import numpy as np

# Read JSON from stdin
data = json.load(sys.stdin)
A = np.array(data["a"])
b = np.array(data["b"])
w = np.array(data.get("w", [1.0] * len(b)))
W = np.diag(w)

# Solve using least squares (returns x)
x = np.linalg.inv(A.T @ W @ A) @ (A.T @ W @ b)

# Output result as JSON list
print(json.dumps(x.tolist()))
