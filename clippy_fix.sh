#!/bin/bash
cargo clippy --workspace -- -D clippy::unwrap_used -D clippy::expect_used | grep "error: used" -A 10 | grep -B 10 -A 10 "note: if this value is an \`Err\`, it will panic" > clippy_errors.txt
