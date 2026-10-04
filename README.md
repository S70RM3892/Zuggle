# Zuggle

一人称3Dのパルクールゲーム。Godot 4.6（GDScript）。
仕様書は [`docs/SPEC.md`](docs/SPEC.md)。

## いまの到達点：P2 手触りの詰め（前半）

- **受け身**（B）：高いところ（約3.6m以上）から落ちたら、着地の直前にBで前へ転がって速さを保つ。押しっぱなしでもよく、着地の直後でも少しは間に合う。Bを押したままならスライディングへつながる
- **強い着地**：受け身を取らないと、水平の速さが3割に落ちて0.4秒よろける
- **マントルジャンプ・ボールトジャンプ**：縁掴み・ボールトの終わり際にAを押すと、乗った・越えた瞬間に速さを保ったまま跳ぶ
- **壁登り→縁掴みで速さを保つ**：登る前の速さ×0.85で上に乗る（前は3 m/sに落ちていた）
- **音と振動**：掴む・手をつく・着地・強い着地・受け身・スライディング・空振りに、その場で作った効果音とパッドの振動
- 直した不具合：ボールト（右手）の後に、押しっぱなしの左手で縁を掴めなかった

## P1 両手のパルクール

- **スライディング**（B / C）：走って押すと加速して滑る。跳べば速さを空中へ持ち出す。空中で押しておけば着地でまた滑る（スライドホップ）。低いバーの下をくぐれる
- **壁登り**：壁へ正面から跳び込み、壁へ向けてスティックを倒していると約2.4m駆け上がる
- **左手＝掴む**（LB / Q / 右クリック）：縁を掴んで登る（縁掴み）、縦のポールを掴んで回る（ポール回り）。押しっぱなしなら届いた瞬間に掴む
- **右手＝押す**（RB / E / 左クリック）：低い障害物に手をついて越える（ボールト、加速つき）、壁を突き放して横へ切り返す（壁押し）
- **勢いの持ち越し**：最高速度を超えて着地しても、走り続ければゆっくりしか減らない
- **両手と仮の脚**：手は実際に縁・ポール・壁へ伸びて掴む・つく。脚は箱の仮モデル（下を向くと見える。スライディングでは前の脚が伸びる）
- 練習場：東の列（x=22）にボールト箱→低いバー→2mの縁→4.5mの壁、西にポール2本
- ナイフ（M3ヒットラボ）は保管中。`scenes/knife_hand.tscn` と `scenes/dummy.tscn` に残し、テストも続けている

これまでの移動（M1）と壁走り（M2）はそのまま使える。数値は仕様書の5章。
受け身は東の列の4.5mの壁の上から跳び降りて練習できる。

### 手のモデル：Neon Cybernetic Hand（Meshy製、骨を自動で付けた）

- `models/hand.glb` には骨がないので、`tools/rig/` の手順で骨16本（手のひら＋指5本×3関節）と重みを付けて `models/hand_rigged.scn` にしている
- 左手は同じモデルを左右反転して使う（`scripts/hands_view.gd`）
- 指の曲げは `scripts/hands_view.gd` の `CURLS`（軽く握る / 開く / 平ら / 握る）で変える

骨を付け直すとき：

```sh
pip install numpy scipy
python3 tools/rig/analyze_hand.py                         # 関節の位置と頂点ごとの骨 → tools/rig/rig.json
godot --headless --path . res://tools/rig/build_hand.tscn # → models/hand_rigged.scn
```

クレジット：「Neon Talon」「Neon Cybernetic Hand」 made with Meshy（CC BY 4.0）

## 起動

Godot 4.6でこのフォルダを開き、F5で実行する。

## 操作

| 操作 | パッド（Xbox配置） | キーボード・マウス |
| --- | --- | --- |
| 移動 | 左スティック | WASD |
| 視点 | 右スティック | マウス / 矢印キー |
| ジャンプ / 壁ジャンプ | A | Space |
| しゃがみ / スライディング / 受け身 | B | C / 左Ctrl |
| 左手：掴む（縁掴み・ポール回り） | LB | Q / 右クリック |
| 右手：押す（ボールト・壁押し） | RB | E / 左クリック |
| 調整パネルの開閉 | Back（View） | F1 |
| マウスを解放 / 再捕捉 | ― | Esc / クリック |

調整パネルを開いている間はプレイヤーが止まる。十字キーの上下で項目を選び、左右で値を動かす。
「値をコピー」で今の値をクリップボードに入れられるので、仕様書の改善ログに貼る。
決めた値は `scripts/tuning.gd` の初期値に書き戻す。

## テスト

```sh
godot --headless --path . res://tests/test_movement.tscn
godot --headless --path . res://tests/test_wallrun.tscn
godot --headless --path . res://tests/test_parkour.tscn
godot --headless --path . res://tests/test_hitlab.tscn
```

`test_movement` は走り・ジャンプ・先行入力・コヨーテタイム・空中の勢い・小ジャンプ、
`test_wallrun` は壁走りの開始・速度維持・弱い重力・上限時間・壁の端での抜け・正面衝突と低速では入らないこと・スティックで離れること・練習コースの踏破・方向転換・壁ジャンプ（向き・スティックでの向き・向かいの壁への乗り継ぎ・入る前の押しでは跳ばないこと・壁のコヨーテタイム）、
`test_parkour` はスライディング（加速・目線・脚・減速・加速の待ち時間・スライドジャンプ・スライドホップ・バーくぐり）・勢いの持ち越し・着地（2mでは普通・強い着地・受け身・押しっぱなしの受け身・遅れた受け身・段差を下りても転がる・受け身からスライディング・強い着地からは跳べない・宙に出たら強い着地は終わる）・壁登り・壁登り＋縁掴み（登る前の速さを持ち出す・頂点で掴んでも同じ）・跳んで縁掴み（左手が縁に届くこと）・マントルジャンプ（掴んですぐ・掴む前のジャンプは持ち越さない）・ボールト・ボールトジャンプ・ボールト後の左手の押しっぱなし・壁押し（壁走り中・地上・同じ壁は1回）・ポール回り（左手がポールを握ること・視点がついて回ること・離すと加速）・空振り・それぞれの手応えの音、
`test_hitlab`（保管中のナイフ）は通常攻撃が当たること・ナイフ回し（2回転して元に戻る・攻撃で止まる）・手の骨と重み・1振り1回・ヒットストップの長さ・画面揺れの減衰・ダミーの吹き飛びと戻り・空振り・速度による威力・攻撃の先行入力・壁の前で武器を引っ込めること・ダミーで壁走りしないことを確かめる。
失敗があると終了コード1で終わる。

## APKの書き出し

### GitHub Actionsでリリースする（ふだんはこちら）

`.github/workflows/release-apk.yml`。GitHubのActions画面で「Release APK」→「Run workflow」を押し、ブランチを選んで実行する。
自動テストを通してからAPKを書き出し、`export_presets.cfg` の `version/name` を名前にしたリリース（例：`v0.6.0-p2`）に載せる。
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
| `docs/SPEC.md` | 仕様書 |
| `scenes/main.tscn` | 部屋（段差・隙間・壁走りコース・パルクール練習場・ポール）、プレイヤー、両手、仮の脚、HUD |
| `scripts/player.gd` | 一人称プレイヤーの移動・スライディング・しゃがみ・壁走り・壁登り・着地（受け身・強い着地）とカメラ |
| `scripts/hand_actions.gd` | 左手（縁掴み・ポール回り）と右手（ボールト・壁押し）。動作中はプレイヤーの体を預かる |
| `scripts/hands_view.gd` | 両手の見た目（構え・腕の振り・掴む・つく・指の曲げ） |
| `scripts/legs_view.gd` | 箱の仮の脚 |
| `scripts/parkour_feel.gd` | 手のアクションと着地の効果音・振動（自動読み込みの `ParkourFeel`） |
| `scripts/synth.gd` | 効果音をその場で作る道具（`Synth`。`ParkourFeel` と `HitFeel` が使う） |
| `scenes/knife_hand.tscn` `scenes/dummy.tscn` | 保管中のナイフの手とダミー（`test_hitlab` が使う） |
| `scripts/weapon.gd` `scripts/dummy.gd` `scripts/hit_feel.gd` | 保管中のナイフ・ダミー・ヒットの演出 |
| `models/` | Meshyで作った手とナイフ |
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
