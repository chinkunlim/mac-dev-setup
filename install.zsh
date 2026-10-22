#!/bin/zsh
# install.zsh  新機環境安裝（對應 SOP v4.3，不固定版本）
#
# 用法：
#   zsh install.zsh                 依序執行全部階段
#   zsh install.zsh node webui      只執行指定階段（可重複執行，已完成的會略過）
#
# 階段：brew pkgs git python agy ollama node webui opendesign audit
#
# 需要從網路下載並執行腳本的地方（curl）只有三處，都會先下載到暫存檔、
# 顯示網址與 sha256，輸入 yes 才執行：Homebrew、Antigravity CLI、nvm。
# 其他的 curl 都只是對本機 127.0.0.1 的連線檢查。
#
# 建議整段錄下來：script -a ~/install-logs/install-$(date +%Y%m%d).log zsh install.zsh

# ---------------------------------------------------------------
# 需要你確認的網址（改這裡即可）
URL_BREW="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
URL_AGY="https://antigravity.google/cli/install.sh"
URL_NVM="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"

# Open WebUI 目前要求 Python 3.11（相容性需求，不是版本固定）
PY_FOR_WEBUI="3.11"
OLLAMA_MODELS=(qwen2.5 bge-m3)

# ---------------------------------------------------------------
SCRIPT_DIR=${0:A:h}
DATA_DIR="$HOME/open-webui-data"
PLIST="$HOME/Library/LaunchAgents/com.openwebui.service.plist"
LABEL="com.openwebui.service"
ALL_STAGES=(brew pkgs git python agy ollama node webui opendesign audit)

C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_OFF=$'\e[0m'
step() { print -r -- ""; print -r -- "${C_CYAN}=== $* ===${C_OFF}"; }
ok()   { print -r -- "  ${C_GREEN}[OK]${C_OFF}   $*"; }
warn() { print -r -- "  ${C_YELLOW}[WARN]${C_OFF} $*"; }
info() { print -r -- "         $*"; }
die()  { print -r -- "  ${C_RED}[STOP]${C_OFF} $*"; exit 1; }

add_line() {
  local line=$1 file=$2
  touch "$file"
  grep -qxF -- "$line" "$file" && return 0
  print -r -- "$line" >> "$file"
  info "已加入 $file: $line"
}

load_env() {
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  path=("$HOME/.local/bin" $path)
  typeset -U path PATH
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" >/dev/null 2>&1
  export DATA_DIR
}

run_remote() {
  local name=$1 url=$2 f ans
  f=$(mktemp -t "install-$name") || die "無法建立暫存檔"
  print -r -- ""
  print -r -- "${C_YELLOW}>>> 需要從網路下載並執行：$name${C_OFF}"
  print -r -- "    網址: $url"
  curl -fsSL "$url" -o "$f" || { rm -f "$f"; die "下載失敗: $url"; }
  print -r -- "    大小: $(wc -c < "$f" | tr -d ' ') bytes, $(wc -l < "$f" | tr -d ' ') 行"
  print -r -- "    sha256: $(shasum -a 256 "$f" | cut -d' ' -f1)"
  print -r -- "    暫存檔: $f"
  while true; do
    read "ans?    輸入 yes 執行、view 查看內容、其他鍵取消: "
    case $ans in
      view) less "$f" ;;
      yes)  /bin/bash "$f"; local rc=$?; rm -f "$f"; return $rc ;;
      *)    rm -f "$f"; return 1 ;;
    esac
  done
}

wait_http() {
  local url=$1 secs=$2 i=0
  while (( i < secs )); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null) == 200 ]] && return 0
    sleep 5; (( i += 5 ))
    (( i % 60 == 0 )) && info "等待 $url ... 已 $((i / 60)) 分鐘"
  done
  return 1
}

# ---------------------------------------------------------------
stage_brew() {
  step "brew：Command Line Tools 與 Homebrew"
  [[ $(uname -m) == arm64 ]] || die "只支援 Apple Silicon"
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "沒有 Command Line Tools，已開啟安裝視窗；裝完後重新執行: zsh install.zsh"
    xcode-select --install
    exit 1
  fi
  ok "xcode-select -p = $(xcode-select -p)"
  if [[ $(xcode-select -p) == *Xcode.app* ]]; then
    xcodebuild -license check >/dev/null 2>&1 || sudo xcodebuild -license accept || die "Xcode 授權未同意"
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    ok "Homebrew 已安裝"
  else
    run_remote homebrew "$URL_BREW" || die "Homebrew 未安裝"
  fi
  if grep -q '/opt/homebrew/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
    ok "~/.zprofile 已有 brew shellenv 設定"
  else
    print -r -- 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> ~/.zprofile
    info "已依 Homebrew Next steps 寫入 ~/.zprofile（不需再手動貼上 Next steps）"
  fi
  load_env
  ok "$(brew --version | head -1)"
  local n=$(grep -c 'brew shellenv' ~/.zprofile 2>/dev/null)
  (( n == 1 )) && ok "~/.zprofile 只有 1 行 brew shellenv" || warn "~/.zprofile 有 $n 行 brew shellenv，請手動刪到剩 1 行"
}

stage_pkgs() {
  step "pkgs：Homebrew 套件"
  command -v brew >/dev/null || die "先執行 brew 階段"
  local f
  for f in gh uv ffmpeg; do
    brew list --formula $f >/dev/null 2>&1 && ok "$f 已安裝" || brew install $f || die "brew install $f 失敗"
  done

  if [ -d /Applications/Ollama.app ]; then ok "Ollama.app 已存在"
  else brew install --cask ollama || die "brew install --cask ollama 失敗"; fi

  brew list --formula opencode >/dev/null 2>&1 && warn "裝了 formula opencode，與 opencode-v2 指令同名，請 brew uninstall opencode"
  if brew list --formula opencode-v2 >/dev/null 2>&1; then ok "opencode-v2 已安裝"
  else brew install anomalyco/tap/opencode-v2 || die "opencode-v2 安裝失敗"; fi

  if brew list --cask opencode-desktop >/dev/null 2>&1; then ok "opencode-desktop 已安裝"
  elif [ -d /Applications/OpenCode.app ]; then warn "/Applications/OpenCode.app 不是 Homebrew 裝的，請先移到垃圾桶再重跑此階段"
  else brew install --cask opencode-desktop || die "opencode-desktop 安裝失敗"; fi

  if [ -d /Applications/OpenCode.app ]; then
    local s=$(spctl -a -vv /Applications/OpenCode.app 2>&1)
    [[ $s == *accepted* && $s == *"Anomaly Innovations"* ]] && ok "OpenCode.app 簽章正確" || warn "OpenCode.app 簽章異常，不要使用: $s"
  fi
}

stage_git() {
  step "git：GitHub 登入與 git 設定"
  command -v gh >/dev/null || die "先執行 pkgs 階段"
  if gh auth status >/dev/null 2>&1; then ok "gh 已登入"
  else
    info "接下來是互動步驟：按 Enter 開瀏覽器，貼上一次性代碼完成登入"
    gh auth login --hostname github.com --git-protocol https --web || die "gh 登入失敗"
  fi
  info "$(gh auth status 2>&1 | grep -i 'token scopes')"
  local c=$(grep -c oauth_token ~/.config/gh/hosts.yml 2>/dev/null)
  [[ ${c:-0} == 0 ]] && ok "token 不是純文字存放" || warn "hosts.yml 有純文字 token，請 gh auth logout 後重新登入"

  local v
  git config --global --get user.mail >/dev/null && { git config --global --unset user.mail; info "已移除打錯的 user.mail"; }
  v=$(git config --global --get user.name)
  if [[ -z $v ]]; then read "v?git user.name: "; git config --global user.name "$v"; fi
  v=$(git config --global --get user.email)
  if [[ -z $v ]]; then
    info "不想公開信箱，可用 GitHub 設定頁的 ID+帳號@users.noreply.github.com"
    read "v?git user.email: "; git config --global user.email "$v"
  fi
  git config --global init.defaultBranch main
  gh auth setup-git

  local p
  for p in '.env' '.env.*' '!.env.example' '.DS_Store' '*.pem' '*.key' 'node_modules'; do
    add_line "$p" ~/.gitignore_global
  done
  git config --global core.excludesfile ~/.gitignore_global
  git config --global --get-regexp 'user\.|credential|excludesfile|defaultBranch' | sed 's/^/         /'
}

stage_python() {
  step "python：uv、Python $PY_FOR_WEBUI 與 PATH"
  command -v uv >/dev/null || die "先執行 pkgs 階段"
  uv python install $PY_FOR_WEBUI || die "uv python install 失敗"
  uv python update-shell
  mkdir -p ~/.local/bin
  add_line 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc
  add_line 'typeset -U path PATH' ~/.zshrc
  load_env
  [[ $(grep -c 'typeset -U' ~/.zshrc) == 1 ]] && ok "typeset -U 只有 1 行" || warn "~/.zshrc 的 typeset -U 不只 1 行"
  [[ $(whence -p od) == /usr/bin/od ]] && ok "od 仍是 /usr/bin/od" || warn "od 被蓋過: $(whence -p od)"
}

stage_agy() {
  step "agy：Antigravity CLI（curl 安裝，不用 Homebrew）"
  if [ -x ~/.local/bin/agy ]; then ok "~/.local/bin/agy 已存在"
  else run_remote antigravity-cli "$URL_AGY" || die "agy 未安裝"; fi
  if [ -f ~/.zprofile ] && grep -q "/Users/$(id -un)/" ~/.zprofile; then
    sed -i '' "s|/Users/$(id -un)|\$HOME|g" ~/.zprofile
    ok "已將 ~/.zprofile 內寫死的使用者路徑改為 \$HOME"
  fi
  load_env
  brew list --cask antigravity-cli >/dev/null 2>&1 && warn "同時有 Homebrew cask antigravity-cli，只保留一個"
  info "which -a agy: $(which -a agy | tr '\n' ' ')"
}

stage_ollama() {
  step "ollama：啟動與模型"
  [ -d /Applications/Ollama.app ] || die "先執行 pkgs 階段"
  if ! curl -s http://127.0.0.1:11434 >/dev/null 2>&1; then
    open -a Ollama
    local i=0
    until curl -s http://127.0.0.1:11434 >/dev/null 2>&1; do
      sleep 2; (( i += 2 )); (( i > 60 )) && die "Ollama 60 秒內沒有回應"
    done
  fi
  ok "127.0.0.1:11434 回應正常"
  local m
  for m in $OLLAMA_MODELS; do
    ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -q "^$m:" && ok "模型 $m 已存在" || ollama pull $m || die "ollama pull $m 失敗（重跑會續傳）"
  done
  curl -s http://127.0.0.1:11434/api/embed -d '{"model":"bge-m3","input":"你好"}' | grep -q '"embeddings"' \
    && ok "bge-m3 embedding 可用" || warn "bge-m3 embedding 測試失敗"
  info "llama3.1、gemma4 過後再 pull（要用時手動 ollama pull）"
}

stage_node() {
  step "node：nvm、Node LTS、pnpm"
  if [ -s "$HOME/.nvm/nvm.sh" ]; then ok "nvm 已安裝"
  else run_remote nvm "$URL_NVM" || die "nvm 未安裝"; fi
  load_env
  command -v nvm >/dev/null || die "載入 nvm 失敗"
  nvm install --lts || die "nvm install --lts 失敗"
  nvm alias default 'lts/*' >/dev/null
  corepack enable || die "corepack enable 失敗"
  COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack prepare pnpm@latest --activate || warn "corepack prepare pnpm 失敗"
  ok "node $(node -v) / npm $(npm -v) / pnpm $(pnpm -v 2>/dev/null)"
  local n=$(which -a pnpm 2>/dev/null | wc -l | tr -d ' ')
  (( n == 1 )) && ok "pnpm 只有一份" || warn "pnpm 有 $n 份: $(which -a pnpm | tr '\n' ' ')"
  info "不要執行 pnpm setup"
}

stage_webui() {
  step "webui：Open WebUI 與 launchd"
  command -v uv >/dev/null || die "先執行 pkgs 與 python 階段"
  add_line 'export DATA_DIR="$HOME/open-webui-data"' ~/.zshrc
  mkdir -p "$DATA_DIR"

  if [ -x ~/.local/bin/open-webui ]; then ok "open-webui 已安裝: $(uv tool list 2>/dev/null | awk '/^open-webui/{print $2}')"
  else uv tool install --python $PY_FOR_WEBUI open-webui || die "open-webui 安裝失敗"; fi

  if [ ! -f "$DATA_DIR/webui.db" ] && ! launchctl print gui/$(id -u)/$LABEL >/dev/null 2>&1; then
    lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1 && die "8080 已被佔用，先關掉佔用的程式"
    info "第一次啟動：會下載約 900 MB 內建模型，慢速網路可能要 30 分鐘以上，請等待"
    info "進度可另開終端機看: tail -f $DATA_DIR/first-run.log"
    cd ~
    open-webui serve --host 127.0.0.1 --port 8080 > "$DATA_DIR/first-run.log" 2>&1 &
    local pid=$!
    if wait_http http://127.0.0.1:8080 5400; then ok "第一次啟動完成（HTTP 200）"
    else kill $pid 2>/dev/null; die "90 分鐘內沒有回 200，看 $DATA_DIR/first-run.log"; fi
    kill $pid 2>/dev/null; wait $pid 2>/dev/null; sleep 3
    pgrep -f "open-webui serve" >/dev/null && { pkill -f "open-webui serve"; sleep 3; }
    pgrep -f "open-webui serve" >/dev/null && die "手動啟動的 open-webui 沒有關掉"
    ok "手動啟動的服務已關閉"
  fi

  chmod 600 ~/.webui_secret_key 2>/dev/null
  chmod 700 "$DATA_DIR"
  chmod 600 "$DATA_DIR/webui.db" 2>/dev/null
  info "權限: $(stat -f '%Lp %N' ~/.webui_secret_key "$DATA_DIR" "$DATA_DIR/webui.db" 2>/dev/null | tr '\n' ' ')"

  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
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
    <key>DATA_DIR</key><string>$DATA_DIR</string>
    <key>OLLAMA_BASE_URL</key><string>http://127.0.0.1:11434</string>
    <key>CORS_ALLOW_ORIGIN</key><string>http://127.0.0.1:8080;http://localhost:8080</string>
  </dict>
  <key>WorkingDirectory</key><string>$HOME</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DATA_DIR/service.log</string>
  <key>StandardErrorPath</key><string>$DATA_DIR/service.err</string>
</dict>
</plist>
EOF
  chmod 644 "$PLIST"
  plutil -lint "$PLIST" >/dev/null || die "plist 語法錯誤"
  ok "plist 已寫入"

  if launchctl print gui/$(id -u)/$LABEL >/dev/null 2>&1; then
    launchctl bootout gui/$(id -u)/$LABEL
    sleep 5
  fi
  launchctl bootstrap gui/$(id -u) "$PLIST" || die "launchctl bootstrap 失敗"
  wait_http http://127.0.0.1:8080 180 && ok "launchd 服務 HTTP 200" || die "服務沒有回應，看 tail -n 30 $DATA_DIR/service.err"
  local l=$(lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | sort -u)
  [[ $l == 127.0.0.1:8080 ]] && ok "8080 只綁 127.0.0.1" || warn "8080 監聽位址: $l"
  info "接著到 http://127.0.0.1:8080 建立管理員帳號，並依 SOP 6.5 設定 Connections 與 Documents（填 127.0.0.1、bge-m3）"
}

stage_opendesign() {
  step "opendesign：Open Design 桌面版（手動下載，不用 git）"
  local oa="/Applications/Open Design.app"
  if [ ! -d "$oa" ]; then
    warn "找不到 $oa"
    info "請從官方發佈頁下載 dmg，拖進「應用程式」後重跑: zsh install.zsh opendesign"
    return 0
  fi
  info "版本: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :CFBundleShortVersionString' "$oa/Contents/Info.plist" 2>/dev/null | tr '\n' ' ')"
  local s=$(spctl -a -vv "$oa" 2>&1)
  [[ $s == *accepted* && $s == *Notarized* ]] && ok "Gatekeeper: Notarized" || warn "Gatekeeper 結果異常，不要使用: $s"
  info "$(print -r -- $s | grep origin=)"
  codesign --verify --deep --strict "$oa" >/dev/null 2>&1 && ok "codesign 驗證通過" || warn "codesign 驗證失敗"
  [[ $(whence -p od) == /usr/bin/od ]] && ok "od 仍是 /usr/bin/od" || warn "od 被蓋過: $(whence -p od)"
}

stage_audit() {
  step "audit：稽核"
  [ -f "$SCRIPT_DIR/audit-install.zsh" ] || die "找不到 $SCRIPT_DIR/audit-install.zsh"
  zsh -n "$SCRIPT_DIR/audit-install.zsh" || die "audit-install.zsh 語法錯誤"
  zsh "$SCRIPT_DIR/audit-install.zsh" 2>&1 | tee ~/install-audit.txt
  info "結果已存到 ~/install-audit.txt；沒有 [FAIL] 才算通過，最後記得做重開機測試"
}

# ---------------------------------------------------------------
[[ $EUID == 0 ]] && die "不要用 sudo 執行這支腳本"
load_env
stages=(${@:-$ALL_STAGES})
for s in $stages; do
  (( ${ALL_STAGES[(Ie)$s]} )) || die "未知階段: $s（可用: $ALL_STAGES）"
done
for s in $stages; do
  stage_$s
  load_env
done
step "完成：$stages"
