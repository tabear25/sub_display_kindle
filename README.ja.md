# DeskDeck（日本語の説明）

Jailbreak 済みの Kindle Paperwhite（第10世代）を、机の脇に置く「Spotify のコントローラー兼 時計兼 ポモドーロタイマー」にするための KOReader プラグインです。土台は [KoPlay](https://github.com/orkunseyman/koplay)（AGPL-3.0）です。

> **開発中です。** いまはステップ2（実機確認）の段階です。
> - KoPlay は無改造です（ログイン用スクリプトに、認可した日時を記録する1行を足しただけ）。
> - DeskDeck は、まだ実機確認用の「診断」画面しかありません。

## 必要なもの

- Jailbreak 済みの Kindle（KOReader が起動すること）
- Spotify Premium
- Spotify の開発者アプリ（ダッシュボードで作成済みのもの）
  - Redirect URI に `http://127.0.0.1:8888/callback` が登録されていること
- PC（Windows か Mac）と Python 3
- USB ケーブル

## 1. ファイルを PC にダウンロードする

1. 次のリンクから ZIP をダウンロードします。
   https://github.com/tabear25/sub_display_kindle/archive/refs/heads/ccr-82b7b158-86aysk.zip
2. ZIP を展開します（Windows：右クリック →「すべて展開」）。
   - `sub_display_kindle-ccr-82b7b158-86aysk` というフォルダができます。以下ではこれを「作業フォルダ」と呼びます。

## 2. Spotify へのログインを許可する（PC で1回）

### なぜ PC で行うのか

Spotify は、アプリにアカウントの操作を許すとき、ブラウザで「同意する」を押すことを求めます。Kindle の KOReader ではこの画面を扱いにくいため、PC で1回だけ同意します。その結果を `koplay.json` というファイルにして、Kindle に渡します。

### 中で起きていること

1. スクリプト（`tools/koplay_auth.py`）が、あなたの開発者アプリ用の同意画面をブラウザで開きます。
2. 「同意する」を押すと、Spotify がブラウザを `http://127.0.0.1:8888/callback` へ戻します。
   - これは、あなたの PC の中でスクリプトが待ち受けている場所です。外のサーバーではありません。
3. スクリプトは、受け取った一時的な番号を Spotify に渡し、「リフレッシュトークン」を受け取ります。
   - Kindle が Spotify を操作し続けるための鍵です。
4. Client ID、リフレッシュトークン、認可した日時を、作業フォルダの `tools/koplay.json` に保存します。

通信先は Spotify（accounts.spotify.com）だけです。Client Secret は使いません。

### 手順（Windows）

1. **Python 3 を入れる**（入っていれば不要）
   - https://www.python.org/downloads/ から Windows 用をダウンロードしてインストールします。
   - インストーラーに「Add python.exe to PATH」の項目があれば、チェックを入れてください。
   - 入ったかどうかは、PowerShell で `py --version` を実行して確かめます。`Python 3.…` と出れば OK です。
   - `py` が見つからないと言われたら `python --version` を試してください。その場合、以下のコマンドの `py` は `python` に読み替えます。
2. **Client ID を確認する**
   - https://developer.spotify.com/dashboard を開き、あなたのアプリ → Settings を開きます。
   - **Client ID** をコピーします。
   - 同じ画面の Redirect URIs に `http://127.0.0.1:8888/callback` があることも確かめてください。
     - 末尾にスラッシュを付けない、`localhost` ではなく `127.0.0.1`、の2点に注意してください。
3. **作業フォルダで PowerShell を開く**
   - エクスプローラーで作業フォルダを開きます。
   - 上のアドレス欄をクリックして `powershell` と入力し、Enter を押します。
4. **スクリプトを実行する**（`あなたのClientID` の部分は、コピーした Client ID に置き換えます）
   ```
   py tools\koplay_auth.py あなたのClientID
   ```
5. **ブラウザで同意する**
   - Spotify の同意画面が開きます（ログインしていなければ、先にログイン画面が出ます）。
   - 内容を確認して「同意する」を押します。
   - ブラウザが自動で開かないときは、PowerShell に表示された `https://accounts.spotify.com/authorize?...` をコピーして、ブラウザに貼り付けます。
6. **成功を確かめる**
   - ブラウザに「Done! You can close this tab and go back to the terminal.」と出ます。
   - PowerShell には `Saved: ...\tools\koplay.json` と出ます。
   - これで `tools\koplay.json` ができました。

### 手順（Mac）

ターミナルで作業フォルダに移動し、次を実行します。あとは Windows の 5〜6 と同じです。

```
python3 tools/koplay_auth.py あなたのClientID
```

### うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| ブラウザに `INVALID_CLIENT: Invalid redirect URI` | ダッシュボードの Redirect URI が `http://127.0.0.1:8888/callback` と一字一句同じか確かめる |
| ブラウザに `INVALID_CLIENT: Invalid client` | Client ID の貼り間違い。コピーし直す |
| 同意したあと、ブラウザが「このサイトにアクセスできません」 | スクリプトが止まっている。PowerShell を閉じていないか確かめ、手順4からやり直す |
| PowerShell に `WinError 10048` や `Address already in use` | 8888番ポートを別のソフトが使っている。PC を再起動してやり直す |
| PowerShell に `Login failed: access_denied` | 同意画面でキャンセルした。やり直して「同意する」を押す |
| 同意画面でエラー（ユーザーが登録されていない等） | アプリの持ち主と別の Spotify アカウントでログインしている。持ち主のアカウントで行うか、ダッシュボードの User Management にそのアカウントを追加する |

## 3. Kindle にコピーする

1. **Kindle に送るファイルをまとめる**：作業フォルダの PowerShell（Mac はターミナル）で次を実行します。
   ```
   py tools\make_dist.py --with-auth
   ```
   - Mac では `python3 tools/make_dist.py --with-auth` です。
   - 作業フォルダに `dist\koreader` ができ、中に次が入ります。
     - `plugins\koplay.koplugin`
     - `plugins\deskdeck.koplugin`
     - `settings\koplay.json`
2. **KOReader を終了する**
   - KOReader の起動中は、Kindle を USB ドライブとして使えません。KOReader が USB ドライブ化を止めているためです。
   - 画面の上端をタップしてメニューを出し、いちばん右のタブ → 一番下の **Exit**（終了）→ **Exit** の順に選びます。表示名は言語設定により「終了」などになります。
3. **USB で PC につなぐ**
   - Kindle が USB ドライブとして表示されます（Windows のエクスプローラーでは「Kindle」）。
4. **コピーする**（**koreader フォルダごと上書きはしないでください**。Mac では中身が置き換わり、KOReader が消えます）
   - `dist\koreader\plugins` の中の2つのフォルダ → Kindle の `koreader\plugins` の中へ
   - `dist\koreader\settings\koplay.json` → Kindle の `koreader\settings` の中へ
5. **取り外す**
   - エクスプローラーで Kindle を右クリック →「取り出し」を選び、ケーブルを抜きます。
6. **KOReader を起動する**：いつもの方法（KUAL など）で起動します。
7. **PC 側の鍵を消す**
   - 作業フォルダの `tools\koplay.json` と `dist` フォルダを削除します。
   - このファイルがあれば、誰でもあなたの Spotify を操作できるためです。もう一度必要になったら、手順2から作り直せます。

## 4. 動作を確かめる

[docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md) の手順で確認し、結果を返信してください。

## 半年ごとの再認可

Spotify のリフレッシュトークンは、**最初に同意した日から6か月で使えなくなります**。Kindle が使っている間に更新されても延びません（Spotify の公式の仕様です）。

- 期限が来ると、KoPlay の画面に「Spotify login is no longer valid」と出て、操作できなくなります。
- 期限の目安は、DeskDeck 診断の「koplay.json」の行で確かめられます（認可日と、その約6か月後の日付）。
  - 完成版では、5か月半を過ぎたら予告を出し、期限切れのときは「PC で再認可してください」と表示する予定です。

**手順**：「2. Spotify へのログインを許可する」と「3. Kindle にコピーする」をもう一度行います。

- 新しい `koplay.json` で、Kindle の `koreader\settings\koplay.json` を上書きしてください。
- コピー後は、KOReader をいったん終了してから起動し直してください。起動中は古いファイルの内容を覚えているためです。
- 同意し直した日から、新しい6か月が始まります。同意した権限（scope）は前と同じです。

**Kindle をなくしたときなど**は、Spotify のアカウントページの「アプリを管理」（https://www.spotify.com/account/apps/ ）で、このアプリのアクセスを取り消せます。

## 困ったとき

- 不具合を報告するときは、Kindle の `koreader/crash.log` を送ってください（KOReader を終了し、USB で PC につなぐと取り出せます）。
  - KoPlay はトークンをログに書きません。
- 給電やスリープまわりは、DeskDeck 診断の「レポート保存」で作られる次の2つのファイルが役に立ちます。
  - `koreader/settings/deskdeck_diag_report.txt`
  - `koreader/settings/deskdeck_diag.log`
- **`koplay.json` は誰にも送らないでください。** このリポジトリにも入れません（`.gitignore` で除外しています）。

## 開発者向け

- 監査の結果と方針：[docs/AUDIT.md](docs/AUDIT.md)
- エミュレーター（Linux / Windows の WSL2）：[docs/EMULATOR.md](docs/EMULATOR.md)
- テスト：`luajit tests/diag_smoke_test.lua`

## ライセンス

[AGPL-3.0](LICENSE)。KoPlay と同じです。
