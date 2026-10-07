#!/bin/bash
#
# OpenCVのヘッダ（core / imgproc）を公式ソースから取得して ios/Frameworks/opencv-headers/ に配置する。
#
# OpenCVの実体はMediaPipe（MediaPipeTasksCommon）に同梱されているものをそのまま使う。
# 別のOpenCVをリンクすると同名のシンボルが衝突してMediaPipe側が優先されるため、
# ライブラリは追加せず、同梱版と同じバージョンのヘッダだけを用意する。
#
# 使い方: scripts/fetch_opencv_headers.sh
# 必要なもの: git
#
set -euo pipefail

# MediaPipeTasksVision 0.10.21 が同梱しているOpenCVのバージョン。
# MediaPipeを更新したら、実行時のバージョン（起動時ログ、または単体テスト）を確認して合わせる
readonly OPENCV_VERSION="4.5.3"
# 上記タグが指すコミット。バージョンを変えるときはこの値も更新する
readonly OPENCV_COMMIT="ad6e82942b37be8ee2c71c1d9bc7fe79cd16f7ab"
readonly MODULES=(core imgproc)

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DESTINATION="${REPO_ROOT}/ios/Frameworks/opencv-headers"
readonly WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "エラー: git が見つかりません。インストールしてから再実行してください。" >&2
  exit 1
fi

echo "OpenCV ${OPENCV_VERSION} のヘッダを取得します..."
git clone --quiet --depth 1 --branch "${OPENCV_VERSION}" --filter=blob:none --sparse \
  https://github.com/opencv/opencv.git "${WORK_DIR}/src"

# タグが付け替えられていないことを確認してから使う
actual_commit="$(git -C "${WORK_DIR}/src" rev-parse HEAD)"
if [[ "${actual_commit}" != "${OPENCV_COMMIT}" ]]; then
  echo "エラー: 取得したソースのコミットが想定と異なります（想定: ${OPENCV_COMMIT} / 実際: ${actual_commit}）。" >&2
  exit 1
fi

sparse_paths=()
for module in "${MODULES[@]}"; do
  sparse_paths+=("modules/${module}/include")
done
git -C "${WORK_DIR}/src" sparse-checkout set "${sparse_paths[@]}"

staging="${WORK_DIR}/opencv-headers"
mkdir -p "${staging}/opencv2"
for module in "${MODULES[@]}"; do
  cp -R "${WORK_DIR}/src/modules/${module}/include/opencv2/." "${staging}/opencv2/"
done

# 通常はビルド時に生成されるモジュール一覧。使うモジュールだけを宣言する
{
  echo "// scripts/fetch_opencv_headers.sh が生成したファイル"
  for module in "${MODULES[@]}"; do
    echo "#define HAVE_OPENCV_$(echo "${module}" | tr '[:lower:]' '[:upper:]')"
  done
} > "${staging}/opencv2/opencv_modules.hpp"

cp "${WORK_DIR}/src/LICENSE" "${staging}/LICENSE"

if [[ ! -f "${staging}/opencv2/core.hpp" || ! -f "${staging}/opencv2/imgproc.hpp" ]]; then
  echo "エラー: 取得は終了しましたが必要なヘッダが見つかりません。" >&2
  exit 1
fi

rm -rf "${DESTINATION}"
mkdir -p "$(dirname "${DESTINATION}")"
cp -R "${staging}" "${DESTINATION}"
echo "完了: ${DESTINATION}"
