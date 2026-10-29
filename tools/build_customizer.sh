#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export CADOVA_BUILD_FROM_SOURCE=1
swift package --disable-sandbox --cache-path .build/swiftpm-cache resolve

wasm_work="$PWD/.build/plugins/GenerateCustomizer/outputs"
# The plugin uses an independent SwiftPM checkout for its WebAssembly build.
swift package --disable-sandbox --scratch-path "$wasm_work/build" \
    --cache-path "$wasm_work/swiftpm/cache" \
    --config-path "$wasm_work/swiftpm/configuration" \
    --security-path "$wasm_work/swiftpm/security" resolve

cadova_dirs=("$PWD/.build/checkouts/Cadova" "$wasm_work/build/checkouts/Cadova")
precision_patch="$PWD/patches/cadova-1.2.0-customizer-precision.patch"
for cadova_dir in "${cadova_dirs[@]}"; do
    git -C "$cadova_dir" apply --check "$precision_patch"
done
patched_dirs=()
restore_dependency() {
    for cadova_dir in "${patched_dirs[@]}"; do
        git -C "$cadova_dir" apply --reverse "$precision_patch"
    done
}
trap restore_dependency EXIT
for cadova_dir in "${cadova_dirs[@]}"; do
    git -C "$cadova_dir" apply "$precision_patch"
    patched_dirs+=("$cadova_dir")
done

swift package --disable-sandbox --cache-path .build/swiftpm-cache \
    --allow-network-connections all:443 --allow-writing-to-package-directory \
    generate-customizer "$@"
