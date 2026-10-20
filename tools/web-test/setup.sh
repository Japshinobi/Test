#!/bin/sh
# Скачивает веб-сборку движка Godot 4.7.2 (wasm, без сетевого модуля) и emnapi в папку bin/.
set -e
cd "$(dirname "$0")"
mkdir -p bin tmp
cd tmp
npm pack --silent @ringozz/godot-web-wasm32@4.7.2-664 @emnapi/runtime@1 >/dev/null 2>&1
tar xzf ringozz-godot-web-wasm32-*.tgz && cp package/gen/*.js package/gen/*.wasm ../bin/ && rm -rf package
tar xzf emnapi-runtime-*.tgz && cp package/dist/emnapi.mjs ../bin/
cd .. && rm -rf tmp
ls bin
