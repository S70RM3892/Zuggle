# Zuggle

一人称3Dのパルクール斬撃アクション。Godot 4.6（GDScript）。

## いまの到達点：M3 ヒットラボ

### M3 ヒットラボ

- ダミー1体（スタート地点の左前）。HPはなく、当たった位置と斬った向きに応じて吹き飛び、よろけ、元の位置に戻る。当たると一瞬白く光る
- 通常攻撃（X / 左クリック / J）。振りかぶり→判定→戻りの3段。先行入力つき。1振りごとに右から・左からを入れ替える
- 威力 = 基本威力 × (1 + 現在の速度 / 最高速度)。止まっていれば1、最高速度なら2
- 当たった瞬間：ヒットストップ（威力1で50ms〜威力2で100ms）、画面揺れ（トラウマ値の2乗、ノイズで滑らかに、時間で減衰）、振動（弱いヒットは弱モーター、強いほど強モーター）、打撃音（毎回ピッチを少しずらす）、ダミーと手・武器の伸び縮み（体積を保って行き過ぎてから戻る）
- 当たり判定は見た目のメッシュを使わず、刃に沿わせた細長い箱（1.4m）で取る
- 目の前に壁があると武器を引っ込めてめり込みを防ぐ
- ダミーでは壁走りしない（壁走りは層1の地形だけ）
- 画面揺れと振動は調整パネルで0にすればオフ

### 手：Neon Cybernetic Hand（Meshy製、骨を自動で付けた）

- `models/hand.glb` には骨がないので、`tools/rig/` の手順で骨16本（手のひら＋指5本×3関節）と重みを付けて `models/hand_rigged.scn` にしている
- メカの手は部品が分かれているので、部品ごとに1本の骨へ固定した（関節で部品が曲がらない）
- 構えでは指を握り、カランビットを人差し指側の輪、刃を小指側から出して持つ。親指は付け根をひねって、握った指の上に乗せる（曲げるだけだと手の前へ突き出る）
- 振りは肘（拳の後ろ0.35m）を中心に回す。前腕が画面を横切らない
- **ナイフ回し**（Y / F）：中指・薬指・小指を開き、人差し指を軸にナイフを2回転させて握り直す（1.0秒）。途中で攻撃すると止めて振る
- 回る速さは一定ではない。はじいた勢いで回り出し、刃先が上るときは重さで遅く、下るときは速くなる。指の摩擦で少しずつ遅くなり、最後は指で受け止めて止まる（`SPIN_GRAVITY`・`SPIN_FRICTION`・`SPIN_CATCH` で調整）

骨を付け直すとき：

```sh
pip install numpy scipy
python3 tools/rig/analyze_hand.py                         # 関節の位置と頂点ごとの骨 → tools/rig/rig.json
godot --headless --path . res://tools/rig/build_hand.tscn # → models/hand_rigged.scn
```

指の曲げ角は `scripts/weapon.gd` の `CURL_GRIP`（握り）と `CURL_SPIN`（ナイフ回し）、親指の付け根のひねりは `THUMB_TURN_GRIP`・`THUMB_TURN_SPIN` で変える。

### 武器：Neon Talon（Meshy製のカランビットナイフ）

`models/weapon.glb` はMeshyで作ったカランビット「Neon Talon」。`Hand` の設定でナイフの大きさにしている。

| 設定 | 値 | 意味 |
| --- | --- | --- |
| `flip_model` | オン | このモデルは長い辺の小さい側が刃先なので反転する |
| `model_length` | 0.32 m | 輪から刃先まで |
| `grip_back` | 0.09 m | 握る位置から輪の端まで |
| `hit_length` | 1.0 m | 判定の箱の長さ（剣のときは1.4m） |

クレジット：「Neon Talon」「Neon Cybernetic Hand」 made with Meshy（CC BY 4.0）

### Meshyの武器に差し替える

1. MeshyのWeb版で刀を作り、GLB（Draco圧縮なし）で書き出す
2. `models/weapon.glb` という名前で置く。あれば起動時に箱の剣と差し替わる
3. 一番長い辺を刃の向きにそろえ、柄頭から刃先までを `model_length` に自動で縮める。長い辺の小さい側（立てて作った剣なら下）を柄とみなす
4. 柄と刃先が逆なら、`Player/Head/Camera3D/Hand` の `flip_model` をオンにする。握る位置と向きは `Hand/Swing/Grip` の位置と回転で微調整する
5. 当たり判定は箱のままなので、モデルを替えても手触りは変わらない
6. Free版で作ったモデルはCC BY 4.0。公開するときはクレジットを表記する

### M2 壁走り

- 空中で壁の横にいると自動で壁走りに入る（ボタンは増やさない）。進入時の速さを、向きだけ壁沿いに変えて保つ
- 入る条件：空中、水平速度が最低速度以上、壁との角度が上限以内（正面衝突では入らない）
- 壁走り中は少し上向きに入り、弱い重力で弧を描く。カメラは壁と反対側へ少し傾く（0でオフ）
- 抜け方：壁の端で勢いを保ったまま抜ける / 壁と反対へスティックを倒す / 着地する / 上限時間（初期値1.75秒）で落下
- 方向転換：進む向きと逆へスティックを倒す（視点を振り返って前に倒してもよい）と、壁沿いに減速して折り返し、元の速さまで戻る（約0.4秒）
- 壁ジャンプ：壁走り中にA。壁から離れる向き（5 m/s）と上（6 m/s）へ跳び、壁沿いの勢いは保つ。スティックを倒していればその向きへ跳ぶ（壁へ向けて倒しても壁からは必ず離れる）。壁を離れた直後もコヨーテタイムの間は跳べる
- 壁に入る前に押したジャンプでは、入った瞬間に壁ジャンプしない
- 同じ壁には着地するまで入り直さない
- 部屋の奥の長い壁に練習コースを追加（足場2つの間が6m。壁を走らないと届かない）
- 長い壁の裏に、4m離して平行な壁（JumpWall）を追加。壁ジャンプで左右の壁を乗り継ぐ練習用

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
| ジャンプ / 壁ジャンプ | A | Space |
| 通常攻撃 | X | 左クリック / J |
| ナイフ回し | Y | F |
| 調整パネルの開閉 | Back（View） | F1 |
| マウスを解放 / 再捕捉 | ― | Esc / クリック |

調整パネルを開いている間はプレイヤーが止まる。十字キーの上下で項目を選び、左右で値を動かす。
「値をコピー」で今の値をクリップボードに入れられるので、仕様書の改善ログに貼る。
決めた値は `scripts/tuning.gd` の初期値に書き戻す。

## テスト

```sh
godot --headless --path . res://tests/test_movement.tscn
godot --headless --path . res://tests/test_wallrun.tscn
godot --headless --path . res://tests/test_hitlab.tscn
```

`test_movement` は走り・ジャンプ・先行入力・コヨーテタイム・空中の勢い・小ジャンプ、
`test_wallrun` は壁走りの開始・速度維持・弱い重力・上限時間・壁の端での抜け・正面衝突と低速では入らないこと・スティックで離れること・練習コースの踏破・方向転換・壁ジャンプ（向き・スティックでの向き・向かいの壁への乗り継ぎ・入る前の押しでは跳ばないこと・壁のコヨーテタイム）、
`test_hitlab` は通常攻撃が当たること・ナイフ回し（2回転して元に戻る・1回転ごとに速さが変わる・攻撃で止まる）・手の骨と重み・親指が人差し指の上に乗ること・1振り1回・ヒットストップの長さ・画面揺れの減衰・ダミーの吹き飛びと戻り・空振り・速度による威力・攻撃の先行入力・壁の前で武器を引っ込めること・ダミーで壁走りしないことを確かめる。
失敗があると終了コード1で終わる。

## APKの書き出し

### GitHub Actionsでリリースする（ふだんはこちら）

`.github/workflows/release-apk.yml`。GitHubのActions画面で「Release APK」→「Run workflow」を押し、ブランチを選んで実行する。
自動テストを通してからAPKを書き出し、`export_presets.cfg` の `version/name` を名前にしたリリース（例：`v0.3.2-m3`）に載せる。
同じ名前のリリースがあればAPKを差し替える。main以外から出したものはプレリリースになる。

署名鍵はリポジトリに入れず、Settings → Secrets and variables → Actions に登録する。

| Secret | 中身 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | キーストアをbase64にしたもの（`base64 -w0 zuggle-release.keystore`） |
| `ANDROID_KEYSTORE_PASSWORD` | キーストアと鍵のパスワード（同じものにする） |
| `ANDROID_KEY_ALIAS` | 鍵の別名 |

鍵は一度だけ手元で作る：

```sh
keytool -genkeypair -keystore zuggle-release.keystore -alias zuggle -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Zuggle"
```

Secretsがなければ、リポジトリに入れた固定のデバッグ鍵 `tools/debug.keystore`（別名androiddebugkey、パスワードandroid）で署名する。
デバッグ鍵は公開して構わない種類の鍵で、毎回同じ鍵なので上書きインストールできる。いまはこちらを使っている。

### 手元で書き出す

Android SDK・JDK 17以上・Godot 4.6.1のエクスポートテンプレートを用意し、`tools/build_apk.sh` を実行する（ワークフローと同じ処理）。

```sh
export GODOT=/path/to/godot ANDROID_HOME=/path/to/Android/Sdk JAVA_HOME=/path/to/jdk
export ANDROID_KEYSTORE_BASE64=$(base64 -w0 zuggle-release.keystore) ANDROID_KEYSTORE_PASSWORD=... ANDROID_KEY_ALIAS=zuggle
tools/build_apk.sh   # build/zuggle-<version>.apk ができる
```

更新版を上書きインストールするには同じ鍵で署名し、`export_presets.cfg` の `version/code` を1つ上げる。
鍵をなくすと上書きできなくなり、一度アンインストールが必要になる。

## 構成

| パス | 役割 |
| --- | --- |
| `scenes/main.tscn` | 部屋（段差・隙間・壁走り用の長い壁と練習コース）、プレイヤー、手と武器、ダミー、HUD |
| `scripts/player.gd` | 一人称プレイヤーの移動・壁走りとカメラ（画面揺れを含む） |
| `scripts/weapon.gd` | 手と武器。通常攻撃の振り・当たり判定・伸び縮み・壁へのめり込み防止・Meshyモデルの読み込み |
| `scripts/dummy.gd` | ダミー。ばねで吹き飛び・よろけ・伸び縮みして戻る |
| `scripts/hit_feel.gd` | 自動読み込みの `HitFeel`。威力の計算・ヒットストップ・振動・効果音 |
| `models/` | Meshyで作った `weapon.glb` を置く場所 |
| `tools/build_apk.sh` | APKの書き出し（署名鍵の有無で署名を切り替える） |
| `tools/rig/` | 手のモデルに骨と重みを付ける（`analyze_hand.py` → `build_hand.tscn`） |
| `models/hand_rigged.scn` | 骨入りの手（`tools/rig/` で作る） |
| `.github/workflows/release-apk.yml` | テスト→APK書き出し→GitHubのリリース |
| `scripts/tuning.gd` | 調整値（自動読み込みの `Tuning`）。`SPECS` に足すとスライダーも増える |
| `scripts/debug_ui.gd` | 調整パネル |
| `tests/` | 自動テスト |

## Claude CodeとGodot MCP

```sh
claude mcp add godot -- npx @coding-solo/godot-mcp
```
