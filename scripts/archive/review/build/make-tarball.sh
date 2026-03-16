#!/bin/bash

SUBI_VERSION=$(cat VERSION.txt)

git archive --format=tar.gz -9 --prefix=subi-${SUBI_VERSION}/ --output=subi-${SUBI_VERSION}.tar.gz HEAD
