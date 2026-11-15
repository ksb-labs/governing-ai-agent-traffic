#!/usr/bin/env bash
# Run every chapter's check.sh except Chapter 13, which needs a Kubernetes cluster.
cd "$(dirname "$0")"
failed=()
for ch in ch01 ch02 ch03 ch04 ch05 ch06 ch07 ch08 ch09 ch10 ch11 ch12 ch14; do
  echo "################ $ch"
  if ! "./$ch/check.sh"; then failed+=("$ch"); fi
  echo
done
if [ ${#failed[@]} -eq 0 ]; then
  echo "All chapters pass. (Chapter 13 needs a cluster: ./ch13/check.sh)"
else
  echo "Chapters with failures: ${failed[*]}"
  exit 1
fi
