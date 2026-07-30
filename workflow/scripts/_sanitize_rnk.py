#!/usr/bin/env python3
import argparse
import math
import sys

def main():
    parser = argparse.ArgumentParser(
        description="Replace +Inf/-Inf ranking scores in a GSEA .rnk file with "
                    "2x the largest/smallest finite value, so fgsea can run."
    )
    parser.add_argument("--input", required=True, help="Path to input .rnk file")
    parser.add_argument("--output", required=True, help="Path to sanitized output .rnk file")
    args = parser.parse_args()

    rows = []
    finite_values = []
    with open(args.input) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            gene, value = line.split("\t")
            score = float(value)
            rows.append([gene, score])
            if math.isfinite(score):
                finite_values.append(score)

    if not finite_values:
        sys.exit(f"❌ {args.input} has no finite ranking scores to infer replacement values from.")

    max_finite = max(finite_values)
    min_finite = min(finite_values)
    pos_replacement = 2 * max_finite
    neg_replacement = 2 * min_finite

    n_pos_inf = 0
    n_neg_inf = 0
    for row in rows:
        if row[1] == math.inf:
            row[1] = pos_replacement
            n_pos_inf += 1
        elif row[1] == -math.inf:
            row[1] = neg_replacement
            n_neg_inf += 1

    with open(args.output, "w") as fh:
        for gene, score in rows:
            fh.write(f"{gene}\t{score}\n")

    if n_pos_inf or n_neg_inf:
        print(
            f"Sanitized {args.input}: replaced {n_pos_inf} Inf -> {pos_replacement}, "
            f"{n_neg_inf} -Inf -> {neg_replacement}"
        )

if __name__ == "__main__":
    main()
