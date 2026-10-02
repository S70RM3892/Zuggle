# Zuggle

一人称3Dのパルクール斬撃アクション。Godot 4.6（GDScript）。

## いまの到達点：M1 移動

- 走り（加速・減速を別の値で設定）、ジャンプ、コヨーテタイム、先行入力、小ジャンプ
- 空中で入力を離しても水平速度が落ちない（大原則）
- 酔い対策：画面中央の点、視野角90度、目の高さのカメラ、控えめな頭の揺れ
- 調整パネル：手触りの値をすべてゲーム中のスライダーで変えられる

## 起動

Godot 4.6でこのフォルダを開き、F5で実行する。

## 操作

| 操作 | パッド（Xbox配置） | キーボード・マウス |
| --- | --- | --- |
| 移動 | 左スティック | WASD |
| 視点 | 右スティック | マウス / 矢印キー |
| ジャンプ | A | Space |
| 調整パネルの開閉 | Back（View） | F1 |
| マウスを解放 / 再捕捉 | ― | Esc / クリック |

調整パネルを開いている間はプレイヤーが止まる。十字キーの上下で項目を選び、左右で値を動かす。
「値をコピー」で今の値をクリップボードに入れられるので、仕様書の改善ログに貼る。
決めた値は `scripts/tuning.gd` の初期値に書き戻す。

## テスト

```sh
godot --headless --path . res://tests/test_movement.tscn
```

走り・ジャンプ・先行入力・コヨーテタイム・空中の勢い・小ジャンプを確かめる。失敗があると終了コード1で終わる。

## APKの書き出し

Android SDK・JDK 17以上・Godot 4.6.1のエクスポートテンプレートを用意し、エディタ設定にSDKとJDKの場所を入れておく。
署名鍵はリポジトリに入れない。環境変数で渡す。

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/zuggle-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=zuggle
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
godot --headless --path . --export-release "Android" build/zuggle.apk
```

更新版を上書きインストールするには同じ鍵で署名し、`export_presets.cfg` の `version/code` を1つ上げる。
鍵をなくすと上書きできなくなり、一度アンインストールが必要になる。

## 構成

| パス | 役割 |
| --- | --- |
| `scenes/main.tscn` | 部屋（段差・隙間・壁走り用の長い壁）、プレイヤー、HUD |
| `scripts/player.gd` | 一人称プレイヤーの移動とカメラ |
| `scripts/tuning.gd` | 調整値（自動読み込みの `Tuning`）。`SPECS` に足すとスライダーも増える |
| `scripts/debug_ui.gd` | 調整パネル |
| `tests/` | 自動テスト |

## Claude CodeとGodot MCP

```sh
claude mcp add godot -- npx @coding-solo/godot-mcp
```
