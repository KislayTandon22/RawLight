#!/bin/sh
# Fetches the RawNIND denoise weights (GPL-3.0, published by darktable-ai) that RawLight bundles on iOS.
set -eu
cd "$(dirname "$0")/../RawLight/Models"
f=rawdenoise-nind.dtmodel
sum=d71b5f1e727c85a359e6f74dca9e2016c9d8fc3e2f7ac3e9b347d80ceca969af
curl -fL -o "$f" https://github.com/darktable-org/darktable-ai/releases/download/release-5.6.0/$f
echo "$sum  $f" | shasum -a 256 -c -
