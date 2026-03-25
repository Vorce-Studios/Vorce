#!/bin/bash

VORCE_VERSION=$(cat VERSION.txt)

git archive --format=tar.gz -9 --prefix=vorce-${VORCE_VERSION}/ --output=vorce-${VORCE_VERSION}.tar.gz HEAD
