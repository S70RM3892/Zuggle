#!/usr/bin/env bash
# 開発用のまとめコマンド。
#
#   tools/dev.sh setup            Godot 4.6.1（ヘッドレスで動く本体）を ~/godot に入れる。入っていれば何もしない
#   tools/dev.sh test [名前...]   インポートしてからテストを並列で回す。名前は movement / wallrun / hitlab / slash / parkour（省略で全部）
#   tools/dev.sh check            setup → スクリプトの読み込みエラー確認 → 全テスト。push前はこれ
#   tools/dev.sh shot [mode]      画面を撮って build/shots/ に置く（mode：views / swing / parkour / compass / all）。xvfb-runが要る
#   tools/dev.sh bump [名前]      export_presets.cfg の version/code を1つ上げる。名前を渡せば version/name も変える
#
# GODOT を指定すればその実行ファイルを使う。失敗があれば終了コード1。
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT_VERSION=4.6.1
GODOT="${GODOT:-$(command -v godot || echo "$HOME/godot/godot")}"
TESTS=(movement wallrun hitlab slash parkour)

setup() {
	if [ -x "$GODOT" ] && "$GODOT" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
		return
	fi
	GODOT="$HOME/godot/godot"
	echo "Godot ${GODOT_VERSION} を取得中…"
	mkdir -p "$HOME/godot"
	local zip
	zip=$(mktemp)
	curl -fsSL -o "$zip" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
	unzip -qo "$zip" -d "$HOME/godot"
	mv "$HOME/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT"
	rm -f "$zip"
	"$GODOT" --version
}

import() {
	"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
}

## すべての .gd を読み込み、文法・型のエラーを出す（tools/lint.tscn）。
lint() {
	local out
	if out=$(timeout 120 "$GODOT" --headless --path . res://tools/lint.tscn 2>&1) \
		&& ! echo "$out" | grep -qE "SCRIPT ERROR|Parse Error"; then
		echo "lint: ok"
		return 0
	fi
	echo "$out" | grep -E "LINT FAIL|SCRIPT ERROR|Parse Error|at: " | sed 's/^/      /' >&2
	echo "lint: FAILED" >&2
	return 1
}

run_tests() {
	local names=("$@")
	[ ${#names[@]} -eq 0 ] && names=("${TESTS[@]}")
	local logs failed=0 pids=() t
	logs=$(mktemp -d)
	for t in "${names[@]}"; do
		timeout 300 "$GODOT" --headless --path . "res://tests/test_$t.tscn" > "$logs/$t.log" 2>&1 &
		pids+=($!)
	done
	for i in "${!names[@]}"; do
		t=${names[$i]}
		if wait "${pids[$i]}"; then
			echo "PASS  test_$t"
		else
			echo "FAIL  test_$t"
			grep -E "FAIL|SCRIPT ERROR|ERROR:|at: " "$logs/$t.log" | head -40 | sed 's/^/      /'
			failed=1
		fi
	done
	rm -rf "$logs"
	return $failed
}

## 仮想ディスプレイ上で実際に描画してスクリーンショットを撮り、並べた一覧（sheet_*.png）も作る。
shot() {
	rm -rf build/shots
	xvfb-run -a -s "-screen 0 1280x720x24" timeout 300 "$GODOT" --path . --rendering-driver vulkan --rendering-method mobile \
		--resolution 960x540 res://tools/shot/shot.tscn -- "--mode=${1:-views}" > build/shot.log 2>&1 || true
	grep -E "SCRIPT ERROR|ERROR: .*res://" build/shot.log | head -20 || true
	python3 tools/shot/sheet.py build/shots
}

bump() {
	local code
	code=$(sed -n 's/^version\/code=\([0-9]*\)$/\1/p' export_presets.cfg)
	sed -i "s/^version\/code=.*/version\/code=$((code + 1))/" export_presets.cfg
	if [ $# -gt 0 ]; then
		sed -i "s/^version\/name=.*/version\/name=\"$1\"/" export_presets.cfg
	fi
	grep -E "^version/(code|name)=" export_presets.cfg
}

cmd="${1:-check}"
shift || true
case "$cmd" in
	setup) setup ;;
	test) setup; import; run_tests "$@" ;;
	lint) setup; import; lint ;;
	check) setup; import; lint; run_tests ;;
	shot) setup; import; shot "$@" ;;
	bump) bump "$@" ;;
	*) sed -n '2,11p' "$0"; exit 2 ;;
esac
