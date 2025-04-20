# python_lstsq_solver.py

import sys
import json
import numpy as np

# Read JSON from stdin
data = json.load(sys.stdin)
A = np.array(data["a"])
b = np.array(data["b"])

# Solve using least squares (returns x)
x = np.linalg.lstsq(A, b, rcond=None)[0]

# Output result as JSON list
print(json.dumps(x.tolist()))
