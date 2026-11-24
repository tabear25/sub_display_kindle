# KoPlay 監査（ステップ1）と方針

- 対象：KoPlay v0.1.0（upstream `orkunseyman/koplay`、コミット `f6812f6`）
- 照合した KOReader：v2026.07.2（koreader-base `6e4bc81`）
- 監査日：2026-11-23

## 決定事項

| 日付 | 内容 | 根拠 |
|---|---|---|
| 2026-11-24 | KoPlay をフォークして拡張する | 下の「8. 採否」 |
| 2026-11-24 | `koplay.koplugin` はほぼ無改変で残し、新機能は `deskdeck.koplugin` に分ける | upstream の更新を取り込みやすくするため。依頼者の「進めて」を受け、推奨案で着手 |
| 2026-11-24 | 作業リポジトリは `tabear25/sub_display_kindle`。当面は公開（public）で進める | 依頼者の判断（非公開にできない事情のため）。この環境では新しいリポジトリを作れない |
| 2026-11-24 | 認可スクリプトに `authorized_at`（認可日時）の記録を前倒しで追加 | 認可日はスクリプトを実行した時点で決まり、後から正確には分からないため |
| 未決 | 追加提案 A（HTTPS の証明書検証＋ホスト名照合）、C（問い合わせのタイムアウト短縮） | ステップ3-5の前に判断する |

## 重要な発見

### A. HTTPS の証明書を検証していない

**事実**
- KoPlay は `socket.http` で HTTPS に接続している（`koplay.koplugin/koplayapi.lua:89`）。
- このとき LuaSocket は LuaSec の `ssl.https.tcp` を呼び、リクエストの表を TLS の設定として渡す。
- LuaSec 1.3.2 の既定は `verify = "none"`（証明書を検証しない）。
- KOReader v2026.07.2 は、この既定を上書きしていない。LuaSec へのパッチは、ビルド用の visibility.patch だけ。Lua 側にも verify や cafile の指定はない。
- KoPlay も指定していない。

**含意（推論）**
- 同じ LAN にいる攻撃者や、改ざんされた DNS があれば、リフレッシュトークンを盗まれる余地がある。
- 盗まれると、最長6か月、次のことをされうる。
  - 再生履歴、ライブラリ、非公開プレイリストの閲覧
  - 再生の操作

**対処案（追加提案 A）**
- KOReader 同梱の CA ファイル（`data/ca-bundle.crt`）で証明書を検証する。
- ホスト名も照合する。LuaSec 1.3.2 にはホスト名照合の機能がないため、接続後に証明書の SAN を自前で照合する。
- 代償：Kindle の時計が大きくずれると通信できなくなる（安全側に倒れる）。

### B. 「給電中」と「充電中」は別物（3-2 の前提）

**事実**
- Kindle の KOReader は、powerd の `charging` / `notCharging` を受け取り、Charging / NotCharging イベントを全体に流す（koreader-base `input/input-kindle.h`）。
- PW4 での判定は次のとおり。
  - `isCharging()`：lipc の `isCharging` を返す。
  - `isCharged()`：`/sys/class/power_supply/bd71827_bat/status` が `Full` かどうか。
- KOReader の自動スリープは、「充電中かつ満充電でない」間だけ止まる。満充電になると、スリープへ向かう（`plugins/autosuspend.koplugin/main.lua:68`、意図的な動作）。
- KOReader の基底クラスには、本来の意味が注記されている。
  - `isCharging`：挿している間は真であるのが望ましい。
  - `isCharged`：挿していて、かつ満充電のとき真。

**含意（推論）**
- 満充電になると、挿したまま NotCharging が届く可能性がある。

**設計**
- 「充電中または満充電」を給電ありとみなす。
- イベントで知らせを受けたあと、状態を定期的に確かめて確定させる。
- 実機での値は、チェックリスト 2-2 で確かめる。

### C. 通信中は画面全体が止まる

**事実**
- KoPlay の通信は UI と同じスレッドで、応答を待つ間は UI も止まる。
- タイムアウトは KOReader の LARGE 値を使っている。応答がないと最大10秒、全体で最大30秒（`frontend/socketutil.lua:29-30`）。名前解決の時間は、これとは別にかかる。

**含意**
- 止まっている間は、時計もポモドーロも描けない。

**対処案（追加提案 C）**
- 小さな JSON の問い合わせだけ、タイムアウトを短くする。

### D. その他

- **スクリーンセーバーの抑止が残る**：KoPlay の「起きたまま」は KeepAlive プラグインと同じ方式で、`preventScreenSaver` を使う。KOReader が終了やクラッシュをしても、これは元に戻らない。DeskDeck では、起動時と終了時に戻す。
- **USB 接続**：KOReader の起動中、Kindle の USB ドライブ化は止められる（`platform/kindle/koreader.sh:312`、volumd を一時停止）。ソースには「構成によっては、PC につなぐとフロントライトが消える」とある。

## 8項目の結果

### 1. 通信先

| 場所 | 通信先 |
|---|---|
| 端末 | `accounts.spotify.com/api/token`、`api.spotify.com/v1`、ジャケット画像（API の応答に入っている URL。通常は i.scdn.co） |
| PC の `tools/koplay_auth.py` | `accounts.spotify.com`（認可画面とトークン取得）、`127.0.0.1:8888` での待ち受け |

- 上記以外への送信や、解析用の送信はない。
- 画像の取得時に、認証ヘッダーは付けない。ただし、画像のホストは制限していない。
- KoPlay が KOReader に「オンラインか」を尋ねると、KOReader 本体が `dns.msftncsi.com` を名前解決する（DNS の照会だけ。`frontend/ui/network/manager.lua:354`）。

### 2. 認証方式・scope・保存場所

- **方式**：PKCE（S256）。state も照合している。Client Secret は使わない。
- **scope**：7つ（`tools/koplay_auth.py:24-32`）。読み取りと再生操作だけで、計画中の機能（端末の転送を含む）はこの範囲で足りる。
  - user-read-playback-state
  - user-read-currently-playing
  - user-modify-playback-state
  - user-read-recently-played
  - user-library-read
  - playlist-read-private
  - playlist-read-collaborative
- **保存場所**：
  - 端末は `koreader/settings/koplay.json` に、平文の JSON で保存する。
  - アクセストークンはメモリにだけ置く。
  - KoPlay はファイルを書き直すとき、知らないキーも残す。そのため `authorized_at` は保たれる。

### 3. 新しい refresh_token の保存し直し

- 保存し直している（`koplayapi.lua:135`）。
- ただし書き込みが上書き一発で、書き込み結果の確認も fsync もない（`koplayapi.lua:71`）。
- 書き込み中に電源が落ちると、PC で再認可するしかなくなる。
- → 3-5 で、一時ファイルに書いてから入れ替える方式にする。KOReader の `ffiUtil.fsyncOpenedFile` / `fsyncDirectory` を使える。

### 4. invalid_grant と 429

**invalid_grant**
- トークン更新が 400/401 なら、一律に「認可切れ」として問い合わせを止める（`koplayapi.lua:122-127`、`main.lua:330`）。
- 自動の再試行はしない。ボタン操作のたびに、1回は試す。
- 不足：`error` の値を見ていない。認可日を記録していない。
- 公式の仕様（2026-06-18 発表、既存アプリには 2026-07-20 から適用）：
  - 最初の認可から6か月で失効し、更新しても延びない。
  - 失効すると 400 と `invalid_grant` が返る。再試行はしない。
  - 発行日時は返さないので、認可した時刻を自分で保存する。

**429**
- Retry-After の秒数（なければ30秒）の間、すべての API 呼び出しを止める（`koplayapi.lua:147-149, 163-166`）。
- 本文の `reason` は見ていない。
- 公式の仕様：2026年7月から、開発モードのアプリには rate limit とは別に「開発者アカウント単位のクォータ」がある。超えると、429 と `"reason": "QUOTA_EXCEEDED"` が返る（上限の数値は非公開）。
- トークン更新が 429 を返したときは、通信エラーとして扱い、20秒後に再試行する。

### 5. 問い合わせ間隔と画面の書き換え

**問い合わせ**
- 再生画面を開いている間だけ行う。

| 状態 | 間隔 |
|---|---|
| 再生中 | 設定値（5/10/15/30秒、既定10秒） |
| 停止中・何も再生していない | 30秒 |
| エラー時 | 20秒 |
| 曲の終わりが近いとき | 「残り＋1秒」に早める |
| ライブラリが上に重なっているとき | 問い合わせない |

- 1回の問い合わせは `GET /me/player` を1本。画像は URL が変わったときだけ取得する。

**書き換え**
- 毎回、全画面を `ui`（点滅しない更新）で書き換える。
- 曲かジャケットが変わったときだけ `full`（点滅する全面更新）。
- 領域を絞った更新や、1時間ごとの全面更新はない。

### 6. 画面の構造とタブの足し方

**現状**
- `main.lua`：状態、問い合わせの繰り返し、スリープ抑止、操作。問い合わせは、再生画面が開いている間だけ動く。
- `koplayview.lua`：全画面を自前で一度に描き、タップの位置も自分で判定する。
- `koplaylibrary.lua`：KOReader 標準の Menu を全画面で出す。

**方針**
- deskdeck 側に全画面の外枠を作る。下にタブバー、上に内容領域を置く。
- KoPlayView は外枠に描かせ、内容領域のタップを渡す。
  - 高さは、生成後に `dimen` を変えて `computeLayout()` を呼べば縮められる。
  - `setDirty` は最上位のウィジェットにしか効かない。そのため `refresh` と「Close ×」はインスタンス側で差し替える。
- 問い合わせの繰り返しは deskdeck 側に新しく持つ。
- ライブラリ画面は、`startPlayback` と `errorText` を持つものを渡せば再利用できる。
- 上に全画面が重なっている間、下のウィジェットは描かれない（`frontend/ui/uimanager.lua:1231`）。そのため、ポモドーロ終了の点滅は、最上位に一時的な全画面を出して行う。
- KOReader は読み込み後に、全プラグインのフォルダを package.path に足す（`frontend/pluginloader.lua:285`）。deskdeck からは、init 以降に `require("koplayapi")` などで KoPlay の部品を使う。

### 7. 前提とする KOReader の版

- README には「Paperwhite 3 + KOReader v2026.07 で確認」とある。PW3 と PW4 は同じ 1072×1448 なので、配置はこの画面で確かめられている。
- 現在の安定版は v2026.07.2。KoPlay が使う KOReader の API が v2026.07.2 にあることは、ソースで確かめた。
  - 確かめた API：Menu.paths / switchItemTable、Notification.SOURCE_ALWAYS_SHOW、Dispatcher、RenderImage、NetworkMgr、Blitbuffer:paintCircle、socketutil.table_sink ほか
- 開発も v2026.07.2 に固定する。

### 8. 採否

**推奨：フォークして拡張する**
- KoPlay の通信部分は、PKCE、新しい refresh_token の保存、429 での待機を備えている。
- 2026年2月の変更（`/playlists/{id}/items`、検索 `limit=10`、他人のプレイリストの 403）にも合わせてある。
- 再生画面は、ファイルを変えずにタブへ組み込める。

**最も強い反論**
- 問い合わせ、スリープ抑止、端末まわりの処理は、ほぼ作り直しになる。
- そのうえ、v0.1.0（コミット3つ）の内部構造に依存するのは脆い。

**それでもフォークを選ぶ理由**
- 依存するのは、KoPlayView、ライブラリ、API の決まった少数の関数だけ。
- upstream の更新は、決まったコミットを狙って取り込める。
- 自作しても、通信部分は写すか書き直すことになる（写せばライセンスは同じ AGPL）。

**判断が変わる条件**
- KOReader や KoPlay が、実機で通信できない場合（そのときは予備案を検討する）。

**参照リポジトリの扱い**
- pomodoro.koplugin：1回点滅するだけで、画面を閉じると止まる作り。状態管理は自作し、コードは写さない。
- inkdeck：領域を絞った更新、分の切り替わりの扱い、起動時に開く設定。考え方だけ借りる。

## 依頼の前提への補足

- **挿し直したときの復帰**：挿しただけで KOReader の画面に戻るかは、まだ分かっていない（チェックリスト 2-5）。電源ボタンが必要な可能性が高いと見ている（推論）。
- **Spotify の仕様**：次は、公式の変更履歴とリファレンスで確かめた。
  - 検索の上限は10件（既定は5件）。
  - プレイリストの中身は `/items` で取る。他人のプレイリストの中身は取れない。
  - Transfer Playback（`PUT /me/player`）は今も提供されている。
  - 端末の type は、公式の例では小文字（`computer`）。大文字・小文字を区別せずに比べる。
  - KoPlay が使っている API は、すべて今も提供されている。
- **10秒間隔の問い合わせ**：1時間に360回になる。開発モードのクォータは上限の数値が非公開なので、QUOTA_EXCEEDED を記録して判断する。

## 出典

- Spotify: [Introducing refresh token expiration](https://developer.spotify.com/blog/2026-06-18-refresh-token-expiration)
- Spotify: [Refreshing tokens](https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens)
- Spotify: [Web API Changelog - February 2026](https://developer.spotify.com/documentation/web-api/references/changes/february-2026)
- Spotify: [Web API Changelog - March 2026](https://developer.spotify.com/documentation/web-api/references/changes/march-2026)
- Spotify: [Web API Changelog - July 2026](https://developer.spotify.com/documentation/web-api/references/changes/july-2026)
- Spotify: [Quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)
- Spotify: [Rate limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits)
- Spotify: [API calls](https://developer.spotify.com/documentation/web-api/concepts/api-calls)
- Spotify: [Transfer Playback](https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback)
- Spotify: [Get Available Devices](https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices)
- Spotify: [Redirect URIs](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)
- LuaSec 1.3.2: [src/https.lua](https://github.com/brunoos/luasec/blob/v1.3.2/src/https.lua)
- KOReader v2026.07.2 と koreader-base `6e4bc81` のソース
