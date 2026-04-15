#!/bin/bash
cargo test -p vorce-control > test_out.log 2>&1
cat test_out.log | tail -n 20
