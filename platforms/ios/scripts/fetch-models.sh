#!/bin/sh
# Fetches the model weights RawLight bundles on iOS: RawNIND denoise (GPL-3.0, darktable-ai) and MobileSAM (Apache-2.0).
set -eu
cd "$(dirname "$0")/../RawLight/Models"
f=rawdenoise-nind.dtmodel
sum=d71b5f1e727c85a359e6f74dca9e2016c9d8fc3e2f7ac3e9b347d80ceca969af
curl -fL -o "$f" https://github.com/darktable-org/darktable-ai/releases/download/release-5.6.0/$f
echo "$sum  $f" | shasum -a 256 -c -

# MobileSAM Core ML (Apache-2.0, ChaoningZhang/MobileSAM converted by mlboydaisuke), used by the Object mask tool
SAM=../RawLight/Models/MobileSAM
BASE=https://huggingface.co/mlboydaisuke/MobileSAM-CoreML/resolve/main
mkdir -p "$SAM"
while read -r sum file; do
  file=${file#./}
  mkdir -p "$SAM/$(dirname "$file")"
  [ -f "$SAM/$file" ] || curl -fL -o "$SAM/$file" "$BASE/$file"
  echo "$sum  $SAM/$file" | shasum -a 256 -c -
done <<'LIST'
72b46adb6ac573f6de4d663bd11eb854ec0c2313fb5b84c25dce098dd78e06c0 ./mobile_sam_decoder.mlpackage/Data/com.apple.CoreML/model.mlmodel
743313ed88a3566f93fcf91491daf475aff2df6f4b2d99d2a7a39c66e9dd3b95 ./mobile_sam_decoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin
54bdceed0c002c10c6446d4bd07dcbd845ce2c146e07092e3fa296a3e682953c ./mobile_sam_decoder.mlpackage/Manifest.json
6982455427573907ee1f3dabc72ded4bbc39807245a5c5161ce9c6b785b0de25 ./mobile_sam_encoder.mlpackage/Data/com.apple.CoreML/model.mlmodel
7ed1fb66938eaa1830e0c255b8abe3b9d443ea6bc424135996b7d6688b146ee2 ./mobile_sam_encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin
8fb691f12d0a3e3dba5d4cf1c626ba85d29c770abd51958a5eead19739e8529b ./mobile_sam_encoder.mlpackage/Manifest.json
b1fe402293da64e7b94c34958d1288cff0857345e0b3f2f816f90b23c07834bb ./mobile_sam_prompt_encoder_weights.json
LIST
