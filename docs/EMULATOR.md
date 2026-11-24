# エミュレーター（PC 上の KOReader）で確かめる

KOReader の PC 版を Kindle Paperwhite 4 と同じ 1072×1448（300 dpi）で動かし、KoPlay と DeskDeck をそこに読み込ませます。実機にコピーする前に、画面の配置や動きを PC で見るためのものです。

**必須ではありません。** 確認の本番は実機（[DEVICE_CHECKLIST.md](DEVICE_CHECKLIST.md)）です。

> **注意（未確認）**：このスクリプトは、開発環境（クラウド）からは KOReader の配布ファイルを取得できなかったため、まだ動かして確かめていません。うまくいかなければ、出たメッセージを送ってください。

## Windows（WSL2）の場合

Windows 11 を推奨します。WSL2 の画面表示機能（WSLg）が標準で入っているためです。Windows 10 でも、新しい WSL なら動く場合があります。

1. **WSL2 と Ubuntu を入れる**（入っていれば不要）
   - PowerShell を「管理者として実行」で開き、`wsl --install` を実行して、PC を再起動します。
   - 再起動後に Ubuntu が開くので、ユーザー名とパスワードを決めます。
2. **Ubuntu で準備する**
   ```
   sudo apt update && sudo apt install -y git
   git clone -b ccr-82b7b158-86aysk https://github.com/tabear25/sub_display_kindle.git
   cd sub_display_kindle
   ```
   - リポジトリは、Ubuntu 側のホーム（`~`）に置いてください。`/mnt/c/...` に置くと遅く、実行の許可でもつまずきます。
3. **KOReader の Linux 版（AppImage）を手に入れる**
   - https://github.com/koreader/koreader/releases から、Kindle と同じ版の「Linux x86_64 用の `.AppImage`」を Windows のブラウザでダウンロードします。
   - Ubuntu 側にコピーします（`<名前>` は Windows のユーザー名）。
     ```
     cp /mnt/c/Users/<名前>/Downloads/koreader-*.AppImage ~/
     ```
4. **起動する**
   ```
   tools/emulator_linux.sh ~/koreader-*.AppImage
   ```
   - 画面の縦が 1448 ピクセルに足りず、ウィンドウがはみ出す場合は `--half` を付けます。半分の大きさ（536×724）で開きます。
   - 縦横の比率は同じですが、文字の大きさなども半分になります。最終確認は等倍で行ってください。
     ```
     tools/emulator_linux.sh --half ~/koreader-*.AppImage
     ```
5. **操作**：マウスのクリックがタップ、ドラッグがスワイプです。

## Linux の場合

上の 2〜5 と同じです。AppImage を任意の場所に置いて、スクリプトに渡してください。

## Spotify のログイン

- エミュレーターは、作業フォルダの `tools/koplay.json` があれば、それを使います。
- **Kindle とは別に、もう一度 `tools/koplay_auth.py` を実行して作ってください。**
  - 同じファイルを Kindle と共有すると、一方がトークンを更新したときに、もう一方が使えなくなるおそれがあります。
  - 同意するたびに、別のトークンが発行されます。
- WSL2 でスクリプトを実行すると、ブラウザが自動で開かないことがあります。その場合は、表示された URL を Windows のブラウザに貼り付けてください。

## 仕組み

- 設定とログは、作業フォルダの `.emulator/home` に置きます（Git には入りません）。
- 実行時に `KO_HOME` で、この置き場所を KOReader に指定しています。
- プラグインは、作業フォルダからのリンク（シンボリックリンク）です。コードを直したら、エミュレーターを再起動するだけで反映されます。
- 画面の大きさは `EMULATE_READER_W/H/DPI` で指定しています。KOReader のソース（koreader-base `ffi/SDL3.lua`、`ffi/framebuffer.lua`）で確認した仕組みです。
