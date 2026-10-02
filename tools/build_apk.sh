#!/usr/bin/env bash
# Android APKを書き出す。GitHub Actionsのリリース用ワークフローから呼ぶが、手元でも動く。
#
# 必要なもの：GODOT（Godot 4.6.1の実行ファイルのパス）、ANDROID_HOME（build-tools入り）、JAVA_HOME（JDK 17以上）、
# エクスポートテンプレート（~/.local/share/godot/export_templates/4.6.1.stable/）
#
# 署名：ANDROID_KEYSTORE_BASE64・ANDROID_KEYSTORE_PASSWORD・ANDROID_KEY_ALIAS がそろっていればリリース署名。
# なければその場で作ったデバッグ鍵で署名する（毎回鍵が変わるので上書きインストールできない）。
#
# 出力：build/zuggle-<version/name>.apk。GITHUB_OUTPUT があれば apk・version・signed を書き込む。
set -euo pipefail

cd "$(dirname "$0")/.."
: "${GODOT:?GODOTにGodotの実行ファイルのパスを入れる}"
: "${ANDROID_HOME:?ANDROID_HOMEにAndroid SDKの場所を入れる}"
: "${JAVA_HOME:?JAVA_HOMEにJDKの場所を入れる}"

version=$(sed -n 's/^version\/name="\(.*\)"$/\1/p' export_presets.cfg)
apk="build/zuggle-${version}.apk"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# エディタ設定にSDKとJDKの場所を書く（Godotはここから読む）
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$config_dir"
settings="$config_dir/editor_settings-4.6.tres"
if [ ! -f "$settings" ]; then
	printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' > "$settings"
fi
sed -i '/^export\/android\/\(android_sdk_path\|java_sdk_path\) = /d' "$settings"
printf 'export/android/android_sdk_path = "%s"\nexport/android/java_sdk_path = "%s"\n' "$ANDROID_HOME" "$JAVA_HOME" >> "$settings"

mkdir -p build
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true

if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ] && [ -n "${ANDROID_KEYSTORE_PASSWORD:-}" ] && [ -n "${ANDROID_KEY_ALIAS:-}" ]; then
	echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$work/release.keystore"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$work/release.keystore"
	export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ANDROID_KEY_ALIAS"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ANDROID_KEYSTORE_PASSWORD"
	mode=--export-release
	signed=release
else
	echo "::warning::署名鍵のSecretsがないので、使い捨てのデバッグ鍵で署名する（上書きインストールできない）"
	keytool -genkeypair -keystore "$work/debug.keystore" -alias androiddebugkey -keyalg RSA -keysize 2048 \
		-validity 10000 -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" > /dev/null 2>&1
	export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$work/debug.keystore"
	export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
	export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
	mode=--export-debug
	signed=debug
fi

rm -f "$apk"
"$GODOT" --headless --path . "$mode" "Android" "$apk"
test -s "$apk" || { echo "APKが書き出されなかった" >&2; exit 1; }
rm -f "$apk.idsig"
echo "書き出し：$apk（$signed 署名）"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "apk=$apk"
		echo "version=$version"
		echo "signed=$signed"
	} >> "$GITHUB_OUTPUT"
fi
