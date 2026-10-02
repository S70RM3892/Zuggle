# Zuggle

一人称3Dのパルクール斬撃アクション。Godot 4.6（GDScript）。

## いまの到達点：M2 壁走り

### M2 壁走り

- 空中で壁の横にいると自動で壁走りに入る（ボタンは増やさない）。進入時の速さを、向きだけ壁沿いに変えて保つ
- 入る条件：空中、水平速度が最低速度以上、壁との角度が上限以内（正面衝突では入らない）
- 壁走り中は少し上向きに入り、弱い重力で弧を描く。カメラは壁と反対側へ少し傾く（0でオフ）
- 抜け方：壁の端で勢いを保ったまま抜ける / 壁と反対へスティックを倒す / 着地する / 上限時間（初期値1.75秒）で落下
- 同じ壁には着地するまで入り直さない
- 部屋の奥の長い壁に練習コースを追加（足場2つの間が6m。壁を走らないと届かない）

### M1 移動

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
godot --headless --path . res://tests/test_wallrun.tscn
```

`test_movement` は走り・ジャンプ・先行入力・コヨーテタイム・空中の勢い・小ジャンプ、
`test_wallrun` は壁走りの開始・速度維持・弱い重力・上限時間・壁の端での抜け・正面衝突と低速では入らないこと・スティックで離れること・練習コースの踏破を確かめる。
失敗があると終了コード1で終わる。

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
| `scenes/main.tscn` | 部屋（段差・隙間・壁走り用の長い壁と練習コース）、プレイヤー、HUD |
| `scripts/player.gd` | 一人称プレイヤーの移動・壁走りとカメラ |
| `scripts/tuning.gd` | 調整値（自動読み込みの `Tuning`）。`SPECS` に足すとスライダーも増える |
| `scripts/debug_ui.gd` | 調整パネル |
| `tests/` | 自動テスト |

## Claude CodeとGodot MCP

```sh
claude mcp add godot -- npx @coding-solo/godot-mcp
```
