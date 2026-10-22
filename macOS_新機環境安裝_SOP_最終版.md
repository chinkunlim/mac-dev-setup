# macOS 新機開發與本地 AI 環境安裝 SOP（Apple Silicon 最終版）

本手冊適用於全新 Apple Silicon (`arm64`) Mac，涵蓋 Homebrew、GitHub CLI、Python (`uv`)、Node.js (`nvm` + `pnpm`)、Antigravity CLI (`agy`)、Ollama、Open WebUI（含 `launchd` 開機常駐）、OpenCode 與 Open Design 桌面版的標準安裝與安全設定。

---

## 0. 安裝前須知

1. **一次貼上一個指令區塊**：互動步驟（輸入密碼、按 Enter、瀏覽器登入）請依終端機提示完成。
2. **程式碼區塊內不放 `#` 註解**：macOS 預設的 zsh 互動模式不會把 `#` 當作註解，直接貼上會導致指令錯誤。
3. **本機服務一律使用 `127.0.0.1`**：
   - 啟動服務時綁定 `127.0.0.1`（避免預設 `0.0.0.0` 對區網開放）。
   - 介面設定連線時填寫 `http://127.0.0.1:埠號`，**不要填 `localhost`**（避免 macOS 偶發名稱解析失敗導致連線中斷）。
4. **不要在家目錄 (`~`) 初始化專案**：切勿在 `~` 執行 `npm init`、`pnpm init` 或 `pnpm install`，以免家目錄產生 `package.json` 或 `node_modules` 影響全域工具判斷。

> [!TIP]
> 本目錄另附三個腳本（請先 `cd` 到腳本所在目錄再執行，無須寫死路徑）：
> - 分階段安裝：`zsh install.zsh`（所有遠端下載腳本皆會先顯示網址與 `sha256`，確認後才執行）
> - 環境稽核：`zsh audit-install.zsh 2>&1 | tee ~/install-audit.txt`
> - 版本快照：`zsh snapshot-versions.zsh`
>
> **macOS 權限小提醒**：若腳本放在 `~/Desktop`（桌面）或 `~/Documents`（文件），在 `Terminal.app` 執行時若出現 `can't open input file`，是因為 macOS 隱私權預設未授權終端機讀取桌面。請至 **「系統設定 → 隱私權與安全性 → 檔案和資料夾 → 終端機」將「桌面檔案夾」打勾**（或在「完全取用磁碟」開啟終端機），即可在原位置直接執行，不需搬移到 `~/Downloads`。

---

## 1. Xcode 授權與 Homebrew

若機器已預載 `Xcode.app`，需先同意授權條款；若無 `Xcode.app`，Homebrew 安裝程式會自動下載並安裝 Command Line Tools：

```bash
xcode-select -p
sudo xcodebuild -license accept
```

安裝 Homebrew：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

> [!IMPORTANT]
> **設定 `~/.zprofile`（請直接照終端機畫面提示操作）**：
> Homebrew 安裝結束時，會在畫面最後印出 `==> Next steps:` 與三行指令。請**直接複製畫面上印出的那三行貼上執行**（下方為標準格式範例，請以你畫面上實際顯示的為準）：

```bash
echo >> $HOME/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> $HOME/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
```

**驗證**（應顯示版本號，且設定檔內只有 `1` 行 `brew shellenv`）：

```bash
brew --version
grep -c 'brew shellenv' ~/.zprofile
```

---

## 2. 基礎套件、GitHub 登入與 Git 設定

### 2.1 安裝基礎套件與啟動 Ollama

```bash
brew install --cask ollama
brew install gh uv ffmpeg
open -a Ollama
```

**驗證 Ollama**（應回傳 `Ollama is running`）：

```bash
curl http://127.0.0.1:11434
```

### 2.2 GitHub CLI 登入

```bash
gh auth login
```

依序選擇：`GitHub.com` → `HTTPS` → `Yes`（使用 GitHub 憑證操作 Git）→ `Login with a web browser`，於瀏覽器完成授權。

檢查登入狀態與憑證儲存方式：

```bash
gh auth status
grep -c oauth_token ~/.config/gh/hosts.yml
```

- `grep` 輸出 `0` 代表 Token 由 macOS 系統鑰匙圈安全保管，未以明文寫入檔案。
- **關於 `workflow` 權限**：若日常需要推送或操作 GitHub Actions，請保留預設的 `workflow` scope；若確定不需要，才執行 `gh auth refresh --remove-scopes workflow` 移除。

### 2.3 Git 基本設定與全域忽略清單

將名稱與信箱換成自己的資訊（若不想公開信箱，可使用 GitHub 提供的 `ID+帳號@users.noreply.github.com`）：

```bash
git config --global user.name "你的名稱"
git config --global user.email "你的信箱"
git config --global init.defaultBranch main
gh auth setup-git
```

設定全域 `.gitignore_global`，防止誤將 `.env` 或私鑰提交至版本庫：

```bash
printf '%s\n' '.env' '.env.*' '!.env.example' '.DS_Store' '*.pem' '*.key' 'node_modules' > ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

**驗證**：

```bash
git config --global --get-regexp 'user\.|credential|excludesfile|defaultBranch'
```

---

## 3. Python (`uv`)、PATH 與 Antigravity CLI (`agy`)

### 3.1 安裝 Python 3.11 與設定 PATH

Open WebUI 需要 Python 3.11 環境：

```bash
uv python install 3.11
uv python update-shell
```

將 `$HOME/.local/bin` 加入 `~/.zshrc` 最前面並啟用 PATH 自動去重（先 `touch ~/.zshrc` 確保檔案存在）：

```bash
mkdir -p ~/.local/bin
touch ~/.zshrc
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
grep -qxF 'typeset -U path PATH' ~/.zshrc || echo 'typeset -U path PATH' >> ~/.zshrc
source ~/.zshrc
```

**驗證**（輸出應為 `1`）：

```bash
grep -c 'typeset -U' ~/.zshrc
```

### 3.2 安裝 Antigravity CLI (`agy`)

在 PATH 設定完成後，使用官方安裝腳本安裝 `agy`（不使用 Homebrew cask，避免雙重來源衝突）：

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

安裝腳本會在 `~/.zprofile` 自動寫入寫死使用者名稱的 `/Users/<帳號>/.local/bin`，請執行以下指令將其改為標準的 `$HOME` 變數（保留該行可防止日後 `agy` 更新時再次寫入寫死路徑）：

```bash
sed -i '' "s|/Users/$(id -un)|\$HOME|g" ~/.zprofile
```

**驗證**（`which -a agy` 應只顯示 `~/.local/bin/agy`，且 `~/.zprofile` 內為 `$HOME/.local/bin`）：

```bash
which -a agy
cat -n ~/.zprofile
```

---

## 4. Node.js (`nvm` + `pnpm`)

安裝 `nvm`、最新 LTS 版 Node.js，並透過內建的 `corepack` 啟用 `pnpm`：

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.zshrc
nvm install --lts
corepack enable
corepack prepare pnpm@latest --activate
```

> [!WARNING]
> **切勿執行 `pnpm setup`**：`corepack` 已管理好 `pnpm`，執行 `pnpm setup` 會在設定檔多寫入 `PNPM_HOME` 並產生第二份 `pnpm`。

**驗證**（`which -a pnpm` 應只有 `~/.nvm/versions/node/.../bin/pnpm` 一筆）：

```bash
node -v
pnpm -v
which -a pnpm
```

---

## 5. Ollama 模型

拉取主力對話模型 `qwen2.5`（約 4.7 GB）與中文文件檢索 Embedding 模型 `bge-m3`（約 1.2 GB）：

```bash
ollama pull qwen2.5
ollama pull bge-m3
```

- 下載中途若按 `Ctrl+C` 中斷，再次執行同一行指令即可續傳。
- `bge-m3` 專供知識庫文件檢索（RAG）使用，無法直接用於對話聊天。
- 其他較大模型（如 `llama3.1` 約 4.9 GB、`gemma4` 約 9.5 GB）可依需求日後再拉取。

**驗證 Embedding API**（應回傳包含 `"embeddings":[[...` 的向量數值）：

```bash
curl -s http://127.0.0.1:11434/api/embed -d '{"model":"bge-m3","input":"你好"}' | head -c 200
```

---

## 6. Open WebUI 與開機常駐 (`launchd`)

### 6.1 安裝 Open WebUI

設定資料目錄環境變數並使用 `uv tool` 安裝：

```bash
touch ~/.zshrc
grep -qxF 'export DATA_DIR="$HOME/open-webui-data"' ~/.zshrc || echo 'export DATA_DIR="$HOME/open-webui-data"' >> ~/.zshrc
source ~/.zshrc
mkdir -p "$DATA_DIR"
uv tool install --python 3.11 open-webui
```

### 6.2 首次手動啟動（完成初始化與模型下載）

先切換至家目錄再啟動，確保金鑰檔 `~/.webui_secret_key` 產生在家目錄，與後續 `launchd` 的工作目錄一致：

```bash
cd ~
open-webui serve --host 127.0.0.1 --port 8080
```

首次啟動會下載約 900 MB 的內建模型，畫面暫時無輸出屬正常現象。請另開一個終端機視窗檢查：

```bash
curl -I http://127.0.0.1:8080
```

看到 `HTTP/1.1 200 OK` 後，回到原本的終端機按 `Ctrl+C` 停止服務，並確認沒有殘留程序佔用 8080 埠：

```bash
pgrep -f "open-webui serve"
```

（應無輸出；若有輸出請執行 `pkill -f "open-webui serve"`。）

### 6.3 收緊密鑰與資料庫權限

設定密鑰與資料庫僅限本人讀寫：

```bash
chmod 600 ~/.webui_secret_key
chmod 700 "$DATA_DIR"
chmod 600 "$DATA_DIR/webui.db"
```

**驗證**（應依序顯示 `600`、`700`、`600`）：

```bash
stat -f '%Lp %N' ~/.webui_secret_key "$DATA_DIR" "$DATA_DIR/webui.db"
```

### 6.4 設定 `launchd` 開機自動啟動

建立 `LaunchAgents` 設定檔（明確指定 `WorkingDirectory`、`DATA_DIR`、`OLLAMA_BASE_URL`、`CORS_ALLOW_ORIGIN` 並只綁定 `127.0.0.1`）：

```bash
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$HOME/Library/LaunchAgents/com.openwebui.service.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.openwebui.service</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/.local/bin/open-webui</string>
    <string>serve</string>
    <string>--host</string>
    <string>127.0.0.1</string>
    <string>--port</string>
    <string>8080</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin</string>
    <key>DATA_DIR</key><string>$HOME/open-webui-data</string>
    <key>OLLAMA_BASE_URL</key><string>http://127.0.0.1:11434</string>
    <key>CORS_ALLOW_ORIGIN</key><string>http://127.0.0.1:8080;http://localhost:8080</string>
  </dict>
  <key>WorkingDirectory</key><string>$HOME</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/open-webui-data/service.log</string>
  <key>StandardErrorPath</key><string>$HOME/open-webui-data/service.err</string>
</dict>
</plist>
EOF
```

檢查權限與語法並載入服務：

```bash
chmod 644 "$HOME/Library/LaunchAgents/com.openwebui.service.plist"
plutil -lint "$HOME/Library/LaunchAgents/com.openwebui.service.plist"
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.openwebui.service.plist"
```

等待約 30 秒後**驗證**（`curl` 回 `200 OK`，`lsof` 顯示 `127.0.0.1:8080`）：

```bash
curl -I http://127.0.0.1:8080
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

- 日後若需重啟常駐服務，`bootout` 與 `bootstrap` 之間**必須間隔 5 秒**，否則 `launchd` 會報 I/O 錯誤：
  ```bash
  launchctl bootout gui/$(id -u)/com.openwebui.service
  sleep 5
  launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.openwebui.service.plist"
  ```
- 錯誤日誌位置：`tail -n 30 ~/open-webui-data/service.err`。

### 6.5 網頁介面設定（上傳任何文件前先完成）

以瀏覽器開啟 `http://127.0.0.1:8080` 並建立管理員帳號：

1. **頭像 → 管理設定 → Connections**：確認 Ollama API 啟用，網址設為 `http://127.0.0.1:11434`（勿填 `localhost`）。
2. **管理設定 → Documents**：
   - Embedding Model Engine 選 `Ollama`
   - API Base URL 填 `http://127.0.0.1:11434`
   - Embedding Model 填 `bge-m3`
   - 按 **Save** 儲存。
3. 選擇 `qwen2.5` 測試對話，並上傳一份中文文件測試檢索（上傳時執行 `ollama ps` 應可看到 `bge-m3` 運作）。
   - 若某個檔案顯示處理錯誤，錯誤狀態會留在該檔案紀錄中，需先刪除該檔案再重新上傳。
   - 上傳的文件與模型輸出一律視為不可信任內容；含 API Key、個人資料或私有原始碼的內容，請勿任意傳送至外部模型服務。

### 6.6 將 Open WebUI 加到 Dock（選用）

Open WebUI 為網頁服務，若希望從 Dock 一鍵以獨立視窗開啟（不顯示瀏覽器網址列）：
- **Safari**：開啟 `http://127.0.0.1:8080`，選單點選「檔案 → 加入 Dock」（macOS Sonoma 14 以上）。
- **Chrome**：點選網址列右側的安裝圖示，或選單中「將頁面安裝為應用程式」。

---

## 7. OpenCode 與 Open Design

### 7.1 OpenCode（終端機版 + 桌面版）

終端機版只安裝 `opencode-v2`（勿同時安裝 `opencode` 以免指令衝突）；桌面版安裝 `opencode-desktop`（勿誤裝同名搜尋結果中的 `opcode`）：

```bash
brew install anomalyco/tap/opencode-v2
brew install --cask opencode-desktop
```

- 若機器上已有舊版 `opencode-desktop`，先執行 `brew uninstall --cask opencode-desktop` 再重裝；**切勿加上 `--zap`**，以免連同使用者資料與設定一併刪除。

**驗證**：

```bash
which opencode
opencode --version
spctl -a -vv /Applications/OpenCode.app
```

（`spctl` 應顯示 `accepted` 與 `Notarized Developer ID`。）

### 7.2 Open Design（桌面版）

直接安裝官方桌面版應用程式，**不需使用 `git clone` 編譯 CLI 版**：

1. 先完成第 3.2 節安裝 `agy`（Open Design 桌面版啟動時會自動偵測已安裝的 `agy`）。
2. 從 Open Design 官方發佈頁（`nexu-io/open-design`）下載 macOS Apple Silicon 版 `.dmg`。
3. 將 `Open Design.app` 拖入 `/Applications` 並開啟。

> [!NOTE]
> **Agent 與 CLI 自動整合**：
> Open Design 桌面版會自動偵測系統已安裝的 Antigravity CLI (`agy`) 並自動提供內建 CLI 支援；日後若安裝其他 Agent，也直接在 Open Design 桌面版介面內設定即可，不需要另外用 `git clone` 安裝 CLI 版，也不必擔心 `od` 指令與系統內建 `/usr/bin/od` 衝突的問題。

**驗證簽章與本機監聽**：

```bash
spctl -a -vv "/Applications/Open Design.app"
codesign --verify --deep --strict "/Applications/Open Design.app" && echo codesign-ok
lsof -nP -iTCP -sTCP:LISTEN | grep -i -E 'open|7456'
```

- `spctl` 應顯示 `accepted` 與 `source=Notarized Developer ID`。
- 開啟 App 時，監聽位址應為 `127.0.0.1`，不應為 `*` 或 `0.0.0.0`。

---

## 8. 環境驗收

### 8.1 執行環境稽核腳本

先切換（`cd`）至腳本所在目錄，再執行唯讀稽核腳本（或在終端機輸入 `zsh ` 後將 Finder 中的 `audit-install.zsh` 拖曳進視窗），確認所有檢查項目為 **0 FAIL**：

```bash
zsh -n audit-install.zsh
zsh audit-install.zsh 2>&1 | tee ~/install-audit.txt
```

常見且可接受的 `[WARN]`：
- `ollama 有 2 個路徑但指向同一檔案`：Ollama App 在 `/usr/local/bin/ollama` 建立了指向 Homebrew 同一執行檔的符號連結。
- `PATH 含不存在的目錄`（`cryptexd` 等）：macOS 系統預設環境路徑。
- `寫死使用者路徑`（`~/.zprofile`）：若未執行第 3.2 節的 `sed` 替換，Antigravity CLI 安裝腳本會寫入 `/Users/<帳號>/.local/bin`，改為 `$HOME/.local/bin` 即可消除。

### 8.2 手動確認項目（腳本無法取代）

1. **系統登入項目**：系統設定 → 一般 → 登入項目與擴充功能（確認無不明背景程式）。
2. **Ollama App 設定**：確認未對區網暴露服務。
3. **Open WebUI 介面設定**：確認 Connections 與 Documents 皆使用 `127.0.0.1` 與 `bge-m3`。
4. **Open Design 桌面版**：確認已自動偵測到 `agy`。

### 8.3 重開機測試

重新啟動 Mac，登入後等待約 30 秒，確認 Open WebUI 已由 `launchd` 自動啟動（且 PID 為新程序）：

```bash
curl -I http://127.0.0.1:8080
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

應回傳 `200 OK`，且 `lsof` 顯示 `127.0.0.1:8080`。

---

## 9. 備份、升級與回滾（重要維護步驟）

### 9.1 備份與還原 Ollama 模型（`~/.ollama/models`）

Ollama 模型檔案體積龐大（`qwen2.5` 約 4.7 GB、`bge-m3` 約 1.2 GB、`llama3.1` 約 4.9 GB、`gemma4` 約 9.5 GB），慢速網路下重新下載需耗時數小時；此外模型的 `latest` 標籤是浮動的，一旦 `bge-m3` 版本變動，Open WebUI 知識庫的向量檢索結果也會改變。

1. **查看目前模型清單與佔用空間**：
   ```bash
   ollama list
   du -sh ~/.ollama/models
   ```
2. **備份模型資料夾**（可複製至外接硬碟或本機備份區，無需停止 Ollama 服務）：
   ```bash
   cp -Rp "$HOME/.ollama/models" "$HOME/ollama-models.bak-$(date +%Y%m%d)"
   ```
3. **還原或換機移轉模型**（免重新下載）：
   在新機或重裝後，安裝好 Ollama 即可直接將備份的 `models` 放回 `~/.ollama/models`：
   ```bash
   mkdir -p "$HOME/.ollama"
   cp -Rp "$HOME/ollama-models.bak-日期" "$HOME/.ollama/models"
   ollama list
   ```

### 9.2 備份與還原 Open WebUI 資料（`~/open-webui-data` 與密鑰）

Open WebUI 的帳號、對話紀錄、知識庫文件與向量索引皆位於 `~/open-webui-data`，Session 金鑰位於 `~/.webui_secret_key`。升級或維護前請**先停止服務再備份**，避免 SQLite 資料庫寫入到一半損毀：

```bash
launchctl bootout gui/$(id -u)/com.openwebui.service
sleep 5
cp -Rp "$HOME/open-webui-data" "$HOME/open-webui-data.bak-$(date +%Y%m%d)"
cp -p "$HOME/.webui_secret_key" "$HOME/open-webui-data.bak-$(date +%Y%m%d)/webui_secret_key.bak"
chmod -R go-rwx "$HOME/open-webui-data.bak-$(date +%Y%m%d)"
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.openwebui.service.plist"
```

- 備份內含密鑰與資料庫，**請勿放進 Git 版本庫**。
- **還原方式**：先 `launchctl bootout` 停止服務，將備份目錄移回 `~/open-webui-data`、將 `webui_secret_key.bak` 移回 `~/.webui_secret_key`（確認權限為 `600`/`700`），再執行 `launchctl bootstrap` 啟動。

### 9.3 保存環境與模型雜湊快照（`snapshot-versions.zsh`）

執行快照腳本可將各工具版本、Homebrew `Brewfile`、Open WebUI 的 Python 相依清單、以及 Ollama 模型的 `sha256` blob 雜湊寫入 `~/dev-env-baseline`（不含任何密鑰或資料庫）：

```bash
zsh snapshot-versions.zsh
```

### 9.4 升級與回滾流程

1. 升級前先執行 **9.1 / 9.2 備份** 與 **9.3 快照**。
2. 以 `brew outdated` 查看待更新項目，逐一評估並單獨升級（`brew upgrade 套件名稱`），升级後執行 `audit-install.zsh` 驗證。
3. **Open WebUI 回滾**：若新版異常，先還原 9.2 的資料備份，再指定舊版號重裝：
   ```bash
   uv tool install --python 3.11 --reinstall open-webui==舊版號
   ```
4. **Open Design 桌面版回滾**：至官方發佈頁下載舊版 `.dmg` 覆蓋安裝。

---

## 附錄 A：日後擴充 Agent（OpenClaw 與 Hermes）

- **優先透過 Open Design 桌面版管理 Agent**：Open Design 桌面版已內建 CLI 與 Agent 串接能力，日後若安裝其他 Agent，可直接在桌面版介面中設定。
- **Hermes 名稱區分**：`Hermes 3` 是語言模型（`ollama pull hermes3`），`Hermes Agent` 是代理框架，兩者不同。
- **最低權限原則**：外掛與 MCP 服務應採最低必要權限，涉及寫入、刪除、部署或提交程式碼的操作應保留人工確認。

---

## 附錄 B：診斷與故障排除

檢查 Open WebUI 服務狀態與最近錯誤日誌：

```bash
curl -I http://127.0.0.1:8080
lsof -nP -iTCP:8080 -sTCP:LISTEN
tail -n 30 ~/open-webui-data/service.err
```

確認最近一次啟動無 CORS 警告（最後一行應為 `Started server process`，且前一行無 `CORS_ALLOW_ORIGIN IS SET TO '*'`）：

```bash
grep -n -i -E "CORS_ALLOW_ORIGIN IS SET|Started server process" ~/open-webui-data/service.err | tail -4
```

若曾使用 `sudo uvx`（例如執行 `py-spy`）導致 `~/.cache/uv` 留下 `root` 擁有的檔案，請立即修正擁有者：

```bash
sudo chown -R "$(id -un)" ~/.cache/uv
find ~/.cache/uv -user root
```

（`find` 無輸出即代表正常。）

---

## 附錄 C：單項手動驗收指令對照表

```bash
type -a od
which -a agy
grep -c 'typeset -U' ~/.zshrc
grep -c 'brew shellenv' ~/.zprofile
which -a pnpm
which opencode
brew list --versions opencode-v2
brew outdated
find ~/.cache/uv -user root
ls -l ~/.webui_secret_key
curl -I http://127.0.0.1:8080
lsof -nP -iTCP:8080 -sTCP:LISTEN
launchctl print gui/$(id -u)/com.openwebui.service | grep -E "state|working directory|CORS"
curl http://127.0.0.1:11434
ollama list
plutil -lint ~/Library/LaunchAgents/com.openwebui.service.plist
gh auth status
spctl -a -vv "/Applications/Open Design.app"
curl -s http://127.0.0.1:11434/api/embed -d '{"model":"bge-m3","input":"你好"}' | head -c 100
```

| 指令 | 預期結果 |
| --- | --- |
| `type -a od` | 只有 `/usr/bin/od` |
| `which -a agy` | 只有 `~/.local/bin/agy` |
| `grep -c 'typeset -U' ~/.zshrc` | `1` |
| `grep -c 'brew shellenv' ~/.zprofile` | `1` |
| `which -a pnpm` | 只有 nvm 那一份 |
| `which opencode` | `/opt/homebrew/bin/opencode` |
| `brew list --versions opencode-v2` | 有版本號 |
| `brew outdated` | 沒有套件列表（`Downloading Homebrew API data` 屬正常） |
| `find ~/.cache/uv -user root` | 無輸出 |
| `ls -l ~/.webui_secret_key` | 權限 `-rw-------` |
| `curl -I http://127.0.0.1:8080` | `200 OK` |
| `lsof ...8080` | `127.0.0.1:8080`，不是 `*:8080` |
| `launchctl print ... \| grep ...` | `state = running`、`working directory` 為家目錄、`CORS_ALLOW_ORIGIN => ...` |
| `curl http://127.0.0.1:11434` | `Ollama is running` |
| `ollama list` | 有 `qwen2.5`、`bge-m3` |
| `plutil -lint ...plist` | `OK` |
| `gh auth status` | 已登入，協定 `https`，scopes 不含 `delete_repo`、`admin:*` |
| `spctl ... Open Design.app` | `accepted`、`Notarized Developer ID` |
| embedding 測試 | 回傳 `{"model":"bge-m3","embeddings":[[...` |

