#!/bin/zsh
# audit-install.zsh  唯讀檢查：不會修改、不會刪除任何東西
# 修訂：Open Design 改檢查桌面版 App；antigravity(agy) 改為檢查 ~/.local/bin；移除對 CLI 版 odesign 的必要檢查
# 用法：zsh audit-install.zsh 2>&1 | tee ~/install-audit.txt

setopt extendedglob
[ -f ~/.zprofile ] && source ~/.zprofile >/dev/null 2>&1
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1

PASS=0; WARN=0; FAIL=0
sec()  { print; print -r -- "=== $1 ==="; }
ok()   { print -r -- "  [OK]   $1"; PASS=$((PASS+1)); }
warn() { print -r -- "  [WARN] $1"; WARN=$((WARN+1)); }
bad()  { print -r -- "  [FAIL] $1"; FAIL=$((FAIL+1)); }
info() { print -r -- "$1" | sed 's/^/         /'; }

UIDN=$(id -u)
LABEL=com.openwebui.service
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DATA="$HOME/open-webui-data"
OD_DIR="$HOME/Services/open-design-cli"

# 版本基準：來自 SOP 的實際安裝紀錄。升級後請同步修改這裡。
EXP_NODE="v24.21.0"
EXP_PNPM="12.11.2"
EXP_OPENWEBUI="0.12.0"
EXP_OPENCODE_MIN="2.0.26"

# ---------------------------------------------------------------
sec "0. 系統"
info "$(sw_vers -productName) $(sw_vers -productVersion) / $(uname -m)"
[[ $(uname -m) == arm64 ]] && ok "Apple Silicon" || warn "不是 arm64"
bp=$(brew --prefix 2>/dev/null)
[[ $bp == /opt/homebrew ]] && ok "Homebrew prefix = /opt/homebrew" || bad "Homebrew prefix 異常: ${bp:-找不到 brew}"
info "$(df -h ~ | tail -1 | awk '{print "磁碟已用 "$5"，剩餘 "$4}')"

# ---------------------------------------------------------------
sec "1. 指令是否只有一個實體"
chk_cmd() {
  local c=$1 p
  local -a paths reals
  paths=(${(f)"$(whence -ap $c 2>/dev/null)"})
  if (( ${#paths} == 0 )); then bad "$c 找不到"; return; fi
  for p in $paths; do reals+=(${p:A}); done
  reals=(${(u)reals})
  if (( ${#paths} == 1 )); then
    ok "$c -> ${paths[1]}"
  elif (( ${#reals} == 1 )); then
    warn "$c 有 ${#paths} 個路徑但指向同一檔案: ${paths[*]}"
  else
    bad "$c 有多個不同的實體: ${paths[*]}"
  fi
}
for c in brew git gh uv ollama node npm pnpm corepack ffmpeg agy open-webui opencode graphify graphify-mcp; do chk_cmd $c; done

od_paths=(${(f)"$(whence -ap od 2>/dev/null)"})
[[ ${#od_paths} -eq 1 && ${od_paths[1]} == /usr/bin/od ]] && ok "od 只有 /usr/bin/od" || bad "od 路徑異常: ${od_paths[*]}"
[ -e ~/.local/bin/od ] && bad "~/.local/bin/od 存在（會蓋過系統的 /usr/bin/od）"

where_is() {
  local p=$(whence -p $1 2>/dev/null)
  if [[ -n $p && $p =~ $2 ]]; then ok "$1 位置符合預期 ($p)"; else bad "$1 位置不符: ${p:-找不到}（預期符合 $2）"; fi
}
where_is uv '^/opt/homebrew/bin/uv$'
where_is gh '^/opt/homebrew/bin/gh$'
where_is node "^$HOME/.nvm/versions/node/"
where_is pnpm "^$HOME/.nvm/versions/node/"
where_is open-webui "^$HOME/.local/bin/open-webui$"
where_is agy "^$HOME/.local/bin/agy$"
where_is opencode '^/opt/homebrew/bin/opencode$'
where_is graphify "^$HOME/.local/bin/graphify$"
where_is graphify-mcp "^$HOME/.local/bin/graphify-mcp$"

# ---------------------------------------------------------------
sec "2. PATH 健康度"
n=0
for d in $path; do
  n=$((n+1))
  if [[ -z $d || $d == . ]]; then bad "PATH 第 $n 項是空白或 '.'"
  elif [[ ! -d $d ]]; then warn "PATH 含不存在的目錄: $d"; fi
done
dups=$(print -l $path | sort | uniq -d)
[[ -z $dups ]] && ok "PATH 無重複項" || warn "PATH 重複: $dups"
info "$(print -l $path | nl)"
info "（launchd 服務的 PATH 另外寫在 plist，不吃這份）"

# ---------------------------------------------------------------
sec "3. Shell 設定檔"
for f in ~/.zshenv ~/.zprofile ~/.zshrc ~/.zlogin ~/.bash_profile ~/.bashrc ~/.profile; do
  [ -f $f ] || continue
  d=$(grep -v -E '^[[:space:]]*(#|$)' $f | sort | uniq -d)
  if [[ -z $d ]]; then ok "$f 無重複行"; else warn "$f 有重複行: $d"; fi
done
c=$(grep -c 'typeset -U' ~/.zshrc 2>/dev/null)
[[ $c == 1 ]] && ok "~/.zshrc 的 typeset -U 剛好 1 行" || bad "~/.zshrc 的 typeset -U 有 ${c:-0} 行"
c=$(cat ~/.zshenv ~/.zprofile ~/.zshrc 2>/dev/null | grep -c 'brew shellenv')
[[ $c == 1 ]] && ok "brew shellenv 只出現 1 次" || warn "brew shellenv 出現 $c 次（跨 .zshenv/.zprofile/.zshrc）"
hit=$(grep -n 'PNPM_HOME' ~/.zshenv ~/.zprofile ~/.zshrc 2>/dev/null)
[[ -z $hit ]] && ok "沒有 PNPM_HOME（未執行 pnpm setup）" || bad "發現 PNPM_HOME: $hit"
if [ -d ~/Library/pnpm ]; then
  other=$(ls -A ~/Library/pnpm 2>/dev/null | grep -v -x store)
  [[ -z $other ]] && ok "~/Library/pnpm 只有 store（pnpm 在 macOS 的預設套件快取位置，正常）" || bad "~/Library/pnpm 有 store 以外的內容（第二份 pnpm？）: $other"
fi
hit=$(grep -n -E '/Users/[A-Za-z0-9._-]+/' ~/.zshenv ~/.zprofile ~/.zshrc 2>/dev/null)
[[ -z $hit ]] && ok "設定檔沒有寫死 /Users/<名稱>" || warn "寫死使用者路徑（因有 typeset -U 不會重複，可接受；SOP 預期由 uv 寫入 ~/.zshenv，實際寫在哪個檔案請留意）: $hit"
hit=$(grep -n -i 'opencode' ~/.zshenv ~/.zprofile ~/.zshrc 2>/dev/null)
[[ -z $hit ]] && ok "設定檔沒有 opencode 的手動 PATH 行" || warn "設定檔出現 opencode（可能是 curl 安裝腳本加的）: $hit"
info "~/.zshrc 內容（不含註解與空行）:"
info "$(grep -v -E '^[[:space:]]*(#|$)' ~/.zshrc 2>/dev/null)"
info "~/.zshenv 內容:"
info "$(grep -v -E '^[[:space:]]*(#|$)' ~/.zshenv 2>/dev/null)"
info "家目錄內的 shell 備份/雜檔: $(ls -A ~ | grep -E 'zsh|bash|profile' | tr '\n' ' ')"

# ---------------------------------------------------------------
sec "4. Homebrew"
if out=$(brew doctor 2>&1); then ok "brew doctor 無警告"; else warn "brew doctor 有警告:"; info "$out"; fi
out=$(brew missing 2>&1); [[ -z $out ]] && ok "brew missing 無缺少相依" || bad "brew missing: $out"
out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet 2>/dev/null); [[ -z $out ]] && ok "沒有待升級套件" || warn "待升級（依 SOP 11.2 評估後再升級，不要全部升）: $(print -r -- $out | tr '\n' ' ')"
info "formulae: $(brew list --formula | tr '\n' ' ')"
info "casks:    $(brew list --cask | tr '\n' ' ')"
info "leaves:   $(brew leaves | tr '\n' ' ')"
info "taps:     $(brew tap | tr '\n' ' ')"
for f in gh uv ffmpeg; do
  brew list --formula | grep -qx $f && ok "formula $f 已安裝" || bad "缺少 formula $f"
done
brew list --cask | grep -q -E '^ollama' && ok "cask ollama 已安裝" || bad "缺少 cask ollama"
if [ -x ~/.local/bin/agy ]; then
  ok "agy 由 ~/.local/bin 提供（curl 安裝，大小 $(du -h ~/.local/bin/agy | cut -f1)）"
  brew list --cask 2>/dev/null | grep -qx 'antigravity-cli' && warn "同時裝了 Homebrew cask antigravity-cli，agy 有兩個來源，只保留一個"
elif brew list --cask 2>/dev/null | grep -qx 'antigravity-cli'; then
  ok "agy 由 Homebrew cask antigravity-cli 提供"
else
  bad "找不到 agy（~/.local/bin/agy 不存在，也沒有 cask antigravity-cli）"
fi
out=$(brew autoremove --dry-run 2>&1); [[ -z $out ]] && ok "沒有可 autoremove 的孤兒相依" || warn "可 autoremove: $out"
out=$(brew cleanup -n 2>&1); [[ -z $out ]] && ok "沒有可清的舊版本/快取" || warn "brew cleanup -n 預覽:"; [[ -z $out ]] || info "$out"
info "brew 快取大小: $(du -sh "$(brew --cache)" 2>/dev/null | cut -f1)"

# ---------------------------------------------------------------
sec "5. opencode（Homebrew 終端機版 + 桌面版）"
oc_f=(${(f)"$(brew list --formula 2>/dev/null | grep -i opencode)"})
oc_c=(${(f)"$(brew list --cask 2>/dev/null | grep -i opencode)"})
info "formula: ${oc_f[*]:-無}"
info "cask:    ${oc_c[*]:-無}"
(( ${#oc_f} == 0 )) && bad "沒有 opencode formula（終端機版）"
(( ${#oc_f} > 1 )) && bad "同時裝了多個 opencode formula (${oc_f[*]})，bin/opencode 會衝突，只保留一個"
(( ${#oc_c} == 0 )) && warn "沒有 opencode cask（桌面版）"
(( ${#oc_c} > 1 )) && warn "多個 opencode cask: ${oc_c[*]}"
for f in $oc_f; do
  info "formula $f: $(brew list --versions $f)"
  info "$(brew list $f 2>/dev/null | grep -E '/bin/')"
done
if [ -L /opt/homebrew/bin/opencode ]; then
  tgt=$(readlink /opt/homebrew/bin/opencode)
  info "/opt/homebrew/bin/opencode -> $tgt"
  if (( ${#oc_f} == 1 )); then
    [[ $tgt == */Cellar/${oc_f[1]}/* ]] && ok "opencode 連結指向 ${oc_f[1]}" || warn "opencode 連結沒有指向 ${oc_f[1]}: $tgt"
  fi
else
  bad "/opt/homebrew/bin/opencode 不是符號連結（可能被其他來源覆蓋）"
fi
info "opencode --version: $(opencode --version 2>&1 | head -1)"
for c in $oc_c; do
  info "cask $c: $(brew list --cask --versions $c)"
  info "$(brew list --cask $c 2>/dev/null | head -8)"
done
apps=( /Applications/(#i)*opencode*.app(N) ~/Applications/(#i)*opencode*.app(N) )
info "桌面版 app: ${apps[*]:-無}"
(( ${#apps} > 1 )) && bad "有多份桌面版 app，可能 dmg 與 Homebrew 重複"
(( ${#apps} >= 1 && ${#oc_c} == 0 )) && warn "有 app 但不是 Homebrew cask 安裝（可能是 dmg 手動安裝）"
(( ${#apps} == 0 && ${#oc_c} >= 1 )) && bad "cask 已安裝但找不到 .app"
for a in $apps; do info "$(spctl --assess --type execute -vv $a 2>&1)"; done
for d in ~/.config/opencode ~/.local/share/opencode ~/.local/state/opencode ~/.cache/opencode ~/.opencode; do
  [ -e $d ] && info "資料夾 $d ($(du -sh $d 2>/dev/null | cut -f1))"
done
info "~/Library 內 opencode 相關: $(find ~/Library -maxdepth 3 -iname '*opencode*' 2>/dev/null | tr '\n' ' ')"
hit=$(grep -rn 'localhost' ~/.config/opencode 2>/dev/null | head -5)
[[ -z $hit ]] && ok "opencode 設定沒有 localhost" || warn "opencode 設定含 localhost，建議改 127.0.0.1: $hit"
info "執行中的 opencode 程序: $(pgrep -fl -i opencode | tr '\n' ';')"

# ---------------------------------------------------------------
sec "6. Ollama"
r=$(curl -s --max-time 3 http://127.0.0.1:11434)
[[ $r == "Ollama is running" ]] && ok "127.0.0.1:11434 回應正常" || bad "11434 無正常回應: ${r:-無回應}（先 open -a Ollama）"
l=$(lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | sort -u)
if [[ -z $l ]]; then warn "11434 沒有程序在監聽"
elif [[ $l == '*:'* || $l == *0.0.0.0* ]]; then bad "Ollama 對所有介面開放: $l"
else ok "Ollama 只監聽 $l"; fi
[[ -z $OLLAMA_HOST ]] && ok "shell 沒有設 OLLAMA_HOST" || warn "OLLAMA_HOST=$OLLAMA_HOST"
lh=$(launchctl getenv OLLAMA_HOST 2>/dev/null)
[[ -z $lh ]] && ok "launchctl 沒有設 OLLAMA_HOST" || warn "launchctl OLLAMA_HOST=$lh"
models=$(ollama list 2>/dev/null | awk 'NR>1{print $1}')
for m in qwen2.5 bge-m3; do
  print -r -- "$models" | grep -q "^$m" && ok "模型 $m" || bad "缺少模型 $m"
done
extra=$(print -r -- "$models" | grep -v -E '^(qwen2.5|bge-m3)')
[[ -z $extra ]] || warn "額外模型: $(print -r -- $extra | tr '\n' ' ')"
emb=$(curl -s --max-time 30 http://127.0.0.1:11434/api/embed -d '{"model":"bge-m3","input":"你好"}')
[[ $emb == *'"embeddings"'* ]] && ok "bge-m3 embedding 可用" || bad "bge-m3 embedding 失敗: ${emb:0:100}"
info "~/.ollama 大小: $(du -sh ~/.ollama 2>/dev/null | cut -f1)"
info "ollama ps: $(ollama ps 2>&1)"

# ---------------------------------------------------------------
sec "7. Open WebUI（uv tool + launchd）"
[[ $DATA_DIR == $DATA ]] && ok "shell DATA_DIR=$DATA_DIR" || warn "shell DATA_DIR=${DATA_DIR:-未設定}（預期 $DATA）"
UVT=$(uv tool dir 2>/dev/null)
v=$(uv tool list 2>/dev/null | grep -E '^open-webui')
info "uv tool: $v"
[[ $v == *$EXP_OPENWEBUI* ]] && ok "open-webui 版本 $EXP_OPENWEBUI" || warn "open-webui 版本不是 $EXP_OPENWEBUI"
[ -x "$UVT/open-webui/bin/python" ] && info "tool Python: $("$UVT/open-webui/bin/python" --version 2>&1)"

if [ -f $PLIST ]; then
  plutil -lint $PLIST >/dev/null 2>&1 && ok "plist 語法 OK" || bad "plist 語法錯誤"
  pb() { /usr/libexec/PlistBuddy -c "Print $1" $PLIST 2>/dev/null; }
  [[ $(pb :WorkingDirectory) == $HOME ]] && ok "WorkingDirectory = 家目錄" || bad "WorkingDirectory 異常: $(pb :WorkingDirectory)"
  [[ $(pb :EnvironmentVariables:DATA_DIR) == $DATA ]] && ok "plist DATA_DIR 正確" || bad "plist DATA_DIR 異常: $(pb :EnvironmentVariables:DATA_DIR)"
  cors=$(pb :EnvironmentVariables:CORS_ALLOW_ORIGIN)
  [[ -n $cors && $cors != '*' ]] && ok "CORS_ALLOW_ORIGIN = $cors" || bad "CORS_ALLOW_ORIGIN 未設或為 *: '$cors'"
  [[ $(pb :EnvironmentVariables:OLLAMA_BASE_URL) == http://127.0.0.1:11434 ]] && ok "plist OLLAMA_BASE_URL 用 127.0.0.1" || warn "plist OLLAMA_BASE_URL: $(pb :EnvironmentVariables:OLLAMA_BASE_URL)"
  args=$(pb :ProgramArguments)
  [[ $args == *127.0.0.1* && $args != *0.0.0.0* ]] && ok "plist 綁定 127.0.0.1" || bad "plist 綁定位址異常"
  exe=$(pb :ProgramArguments:0)
  [ -x "$exe" ] && ok "可執行檔存在: $exe" || bad "plist 指向的可執行檔不存在: $exe"
else
  bad "找不到 $PLIST"
fi

lp=$(launchctl print gui/$UIDN/$LABEL 2>&1)
if print -r -- "$lp" | grep -q 'Could not find service'; then
  bad "launchd 服務 $LABEL 未載入"
else
  st=$(print -r -- "$lp" | grep -E '^[[:space:]]+state = ' | head -1 | sed 's/.*= //')
  lpid=$(print -r -- "$lp" | grep -E '^[[:space:]]+pid = ' | head -1 | sed 's/.*= //')
  wd=$(print -r -- "$lp" | grep -E 'working directory = ' | head -1 | sed 's/.*= //')
  le=$(print -r -- "$lp" | grep -E 'last exit code = ' | head -1 | sed 's/.*= //')
  [[ $st == running ]] && ok "launchd state = running (pid $lpid)" || bad "launchd state = ${st:-未知}"
  [[ $wd == $HOME ]] && ok "launchd working directory = 家目錄" || bad "launchd working directory = ${wd:-未知}"
  info "last exit code: ${le:-無}"
fi

ls8=$(lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $2" "$9}' | sort -u)
info "8080 監聽: ${ls8:-無}"
p8=$(print -r -- "$ls8" | head -1 | awk '{print $1}')
a8=$(print -r -- "$ls8" | head -1 | awk '{print $2}')
[[ $a8 == 127.0.0.1:8080 ]] && ok "8080 只綁 127.0.0.1" || bad "8080 監聽位址異常: ${a8:-無}"
[[ -n $lpid && $p8 == $lpid ]] && ok "8080 的 PID 就是 launchd 服務" || warn "8080 的 PID ($p8) 與 launchd PID (${lpid:-無}) 不同，可能有手動啟動的程序"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8080/)
[[ $code == 200 ]] && ok "GET http://127.0.0.1:8080/ = 200" || bad "GET 8080 = $code"
lan=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
if [[ -n $lan ]]; then
  for port in 8080 11434; do
    c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://$lan:$port/ 2>/dev/null)
    [[ $c == 000 ]] && ok "區網 IP $lan:$port 連不到（正確）" || bad "區網 IP $lan:$port 可連 (HTTP $c)，服務對區網開放"
  done
else
  info "沒有取得區網 IP，略過區網連線測試"
fi

[ -f ~/.webui_secret_key ] && ok "~/.webui_secret_key 存在" || bad "~/.webui_secret_key 不存在"
strays=$(find ~ -maxdepth 4 -name .webui_secret_key -not -path "$HOME/.webui_secret_key" -not -path '*/node_modules/*' 2>/dev/null)
[[ -z $strays ]] && ok "沒有多餘的 .webui_secret_key" || bad "多餘的 .webui_secret_key: $strays"
[ -f $DATA/webui.db ] && ok "資料庫存在 ($(du -h $DATA/webui.db | cut -f1))" || bad "$DATA/webui.db 不存在"
strays=$( { [ -n "$UVT" ] && find "$UVT/open-webui" -name webui.db 2>/dev/null; find ~ -maxdepth 3 -name webui.db -not -path "$DATA/*" 2>/dev/null; } )
[[ -z $strays ]] && ok "沒有落在其他位置的 webui.db" || bad "多餘的 webui.db（空資料庫？）: $strays"
if command -v sqlite3 >/dev/null && [ -f $DATA/webui.db ]; then
  cfg=$(sqlite3 -readonly $DATA/webui.db 'select data from config;' 2>/dev/null)
  if [[ -z $cfg ]]; then
    info "讀不到 config 表（結構因版本而異，請在 UI 內人工確認 Connections 與 Documents）"
  else
    [[ $cfg == *localhost* ]] && warn "資料庫設定含 localhost（Connections/Documents 請改 127.0.0.1）" || ok "資料庫設定沒有 localhost"
    [[ $cfg == *bge-m3* ]] && ok "資料庫設定含 bge-m3" || warn "資料庫設定找不到 bge-m3（Documents 的 embedding 沒設好？）"
  fi
fi
info "$(ls -lh $DATA/service.log $DATA/service.err 2>/dev/null | awk '{print $5" "$9}')"
errf=$DATA/service.err
if [ -f $errf ]; then
  lastcors=$(grep -n 'CORS_ALLOW_ORIGIN IS SET' $errf | tail -1 | cut -d: -f1)
  laststart=$(grep -n 'Started server process' $errf | tail -1 | cut -d: -f1)
  if [[ -z $lastcors ]]; then ok "service.err 沒有 CORS 警告"
  elif [[ -n $laststart ]] && (( laststart - lastcors > 5 )); then ok "CORS 警告是舊紀錄（最近一次啟動後沒有）"
  else bad "最近一次啟動仍有 CORS 警告"; fi
  c=$(grep -c -E 'Read-only file system|Address already in use|Traceback' $errf)
  [[ $c == 0 ]] && ok "service.err 無嚴重錯誤字樣" || warn "service.err 有 $c 行錯誤字樣（可能是歷史紀錄）"
  info "service.err 最後 5 行:"
  info "$(tail -n 5 $errf)"
fi

# ---------------------------------------------------------------
sec "8. Open Design（桌面版）"
od_apps=( /Applications/(#i)*open*design*.app(N) ~/Applications/(#i)*open*design*.app(N) )
info "桌面版 app: ${od_apps[*]:-無}"
if (( ${#od_apps} == 0 )); then
  bad "找不到 Open Design 桌面版（/Applications 與 ~/Applications 都沒有）"
elif (( ${#od_apps} > 1 )); then
  bad "有多份 Open Design app，請只保留一份: ${od_apps[*]}"
else
  oa=${od_apps[1]}
  ok "Open Design app 只有一份: $oa"
  pb=/usr/libexec/PlistBuddy
  ver=$($pb -c 'Print :CFBundleShortVersionString' "$oa/Contents/Info.plist" 2>/dev/null)
  bid=$($pb -c 'Print :CFBundleIdentifier' "$oa/Contents/Info.plist" 2>/dev/null)
  info "版本: ${ver:-?} / bundle id: ${bid:-?}"

  # 簽章與公證
  sp=$(spctl --assess --type execute -vv "$oa" 2>&1)
  info "$sp"
  if [[ $sp == *accepted* && $sp == *"Notarized Developer ID"* ]]; then
    ok "Gatekeeper 接受，且已公證 (Notarized Developer ID)"
  elif [[ $sp == *accepted* ]]; then
    warn "Gatekeeper 接受，但不是 Notarized Developer ID，確認來源"
  else
    bad "Gatekeeper 不接受這個 app，不要使用"
  fi
  info "簽署者（請對照官方網站公布的簽署者是否一致）:"
  info "$(codesign -dv --verbose=2 "$oa" 2>&1 | grep -E '^(Authority=Developer ID Application|TeamIdentifier)')"
  codesign --verify --deep --strict "$oa" >/dev/null 2>&1 && ok "codesign 驗證通過（內容未被改動）" || bad "codesign 驗證失敗（app 內容可能被改動或損毀）"

  # 擁有者與權限
  pm=$(stat -f '%Lp' "$oa" 2>/dev/null); po=$(stat -f '%Su' "$oa" 2>/dev/null)
  if [[ -n $pm ]] && (( ( 8#$pm & 8#022 ) )); then
    bad "app 可被群組或其他人寫入 (權限 $pm)"
  else
    ok "app 權限 $pm，擁有者 $po"
  fi

  # 安裝來源與更新方式
  odc=$(brew list --cask 2>/dev/null | grep -i -E 'open-?design')
  if [[ -n $odc ]]; then
    ok "由 Homebrew cask 安裝: $odc ($(brew list --cask --versions ${=odc} 2>/dev/null))"
  else
    info "不是 Homebrew cask（dmg 手動安裝），版本需自行追蹤"
  fi
  [ -e "$oa/Contents/Resources/app-update.yml" ] && info "app 自帶更新設定 (app-update.yml)，版本可能自動變動"

  # app 內附的 od：只在 app 內，不會進 PATH，不會蓋過 /usr/bin/od
  inner=$(find "$oa/Contents" -maxdepth 6 -type f \( -name od -o -name odesign -o -name open-design \) -perm -111 2>/dev/null | head -5)
  info "app 內附的 od/odesign 執行檔（在 app 包裡面，不在 PATH）: ${inner:-無}"
  [[ $(whence -p od 2>/dev/null) == /usr/bin/od ]] && ok "終端機的 od 仍是系統的 /usr/bin/od，沒有被桌面版蓋過" || bad "終端機的 od 不是 /usr/bin/od: $(whence -p od 2>/dev/null)"
fi

# 執行中的程序與監聽埠
od_pids=(${(f)"$(pgrep -i -f 'open.?design' 2>/dev/null)"})
if (( ${#od_pids} == 0 )); then
  info "Open Design 目前沒在執行（略過監聽埠檢查；想檢查請先開啟 app 再重跑）"
else
  info "執行中的程序: $(ps -o pid=,comm= -p ${(j:,:)od_pids} 2>/dev/null | awk '{print $1":"$2}' | tr '\n' ' ')"
  ol=$(lsof -nP -a -p ${(j:,:)od_pids} -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $1" "$9}' | sort -u)
  if [[ -z $ol ]]; then
    ok "Open Design 沒有開 TCP 監聽埠"
  elif print -r -- $ol | grep -q -E ' (\*:|0\.0\.0\.0:|\[::\]:)'; then
    bad "Open Design 對所有介面開放: $(print -r -- $ol | tr '\n' ';')"
  else
    ok "Open Design 只監聽本機: $(print -r -- $ol | tr '\n' ';')"
  fi
fi
l=$(lsof -nP -iTCP:7456 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $1" "$9}' | sort -u)
if [[ -z $l ]]; then info "7456 沒有服務在監聽"
elif [[ $l == *'*:'* || $l == *0.0.0.0* ]]; then bad "7456 對所有介面開放: $l"
else ok "7456 只監聽本機: $l"; fi

# 使用者資料位置（只列出，不處理）
od_data=(${(f)"$(find ~/Library -maxdepth 3 -iname '*open*design*' 2>/dev/null; find ~ -maxdepth 2 -iname '*open*design*' -not -path "$HOME/Library/*" -not -path "$HOME/Applications/*" 2>/dev/null)"})
for d in $od_data; do info "資料位置: $d ($(du -sh "$d" 2>/dev/null | cut -f1))"; done
(( ${#od_data} == 0 )) && info "沒有找到 Open Design 使用者資料夾（可能尚未啟動過）"

# 舊的 CLI 版殘留
[ -e $OD_DIR ] && warn "舊的 CLI 版資料夾還在: $OD_DIR（改用桌面版後可移走）"
[ -e ~/.local/bin/odesign ] && warn "~/.local/bin/odesign 還在（桌面版不需要；若 OpenClaw 設定還在引用它就先保留）"

# ---------------------------------------------------------------
sec "9. GitHub / git"
gh auth status >/dev/null 2>&1 && ok "gh 已登入" || bad "gh 未登入"
info "$(gh auth status 2>&1)"
info "$(git config --global --get-regexp '^(user\.|credential\.)' 2>/dev/null)"
[ -f ~/.git-credentials ] && bad "~/.git-credentials 存在（明文憑證）" || ok "沒有 ~/.git-credentials"

# ---------------------------------------------------------------
sec "10. Node / pnpm"
info "node $(node -v 2>&1) / npm $(npm -v 2>&1) / pnpm $(pnpm -v 2>&1) / corepack $(corepack --version 2>&1)"
vers=(~/.nvm/versions/node/*(N:t))
(( ${#vers} > 1 )) && warn "nvm 裝了多個 Node 版本: ${vers[*]}" || ok "nvm 只有一個 Node 版本: ${vers[*]}"
info "npm 全域套件:"
info "$(npm ls -g --depth=0 2>/dev/null)"

# ---------------------------------------------------------------
sec "11. uv / Python"
info "$(uv --version 2>&1)"
uv python find 3.11 >/dev/null 2>&1 && ok "Python 3.11 可用" || bad "找不到 uv 管理的 Python 3.11"
info "$(uv python list --only-installed 2>&1)"
info "$(uv tool list 2>&1)"
if [ -x ~/.local/bin/graphify ]; then
  ok "graphify 由 ~/.local/bin 提供 ($(graphify --version 2>&1 | head -1))"
  [ -f ~/.gemini/config/skills/graphify/SKILL.md ] && ok "graphify skill 已註冊至 Antigravity (~/.gemini/config/skills/graphify)" || warn "graphify skill 未註冊至 Antigravity"
  [ -f ~/.claude/skills/graphify/SKILL.md ] && ok "graphify skill 已註冊至 Claude (~/.claude/skills/graphify)" || warn "graphify skill 未註冊至 Claude"
else
  warn "找不到 graphify（尚未以 uv tool install graphifyy 安裝）"
fi
r=$(find ~/.cache/uv -user root 2>/dev/null | head -5)
[[ -z $r ]] && ok "~/.cache/uv 沒有 root 擁有的檔案" || bad "root 擁有的檔案: $r"

# ---------------------------------------------------------------
sec "12. 背景服務"
info "~/Library/LaunchAgents: $(ls -1 ~/Library/LaunchAgents 2>/dev/null | tr '\n' ' ')"
info "/Library/LaunchAgents:  $(ls -1 /Library/LaunchAgents 2>/dev/null | tr '\n' ' ')"
info "/Library/LaunchDaemons: $(ls -1 /Library/LaunchDaemons 2>/dev/null | tr '\n' ' ')"
others=$(ls -1 ~/Library/LaunchAgents 2>/dev/null | grep -v -x "$LABEL.plist")
[[ -z $others ]] && ok "個人 LaunchAgents 只有 $LABEL" || warn "其他個人 LaunchAgent（請確認都認得）: $(print -r -- $others | tr '\n' ' ')"
info "launchctl 中相關項目:"
info "$(launchctl list 2>/dev/null | grep -i -E 'openwebui|open-webui|ollama|opencode|odesign|open-design|openclaw|hermes|antigravity')"
info "（登入項目請手動看：系統設定 → 一般 → 登入項目與擴充功能）"

# ---------------------------------------------------------------
sec "13. 殘留與異常檔案"
r=$(find ~ -xdev -user root -not -path "$HOME/Library/*" 2>/dev/null | head -10)
[[ -z $r ]] && ok "家目錄（不含 Library）沒有 root 擁有的檔案" || bad "root 擁有的檔案: $r"
for d in ~/.openclaw ~/.hermes ~/.pnpm-store ~/.local/share/pnpm; do
  [ -e $d ] && warn "不應存在的路徑: $d"
done
junk=$(ls -A ~ | grep -v -E '^(Desktop|Documents|Downloads|Library|Movies|Music|Pictures|Public|Applications|Services|open-webui-data|\.Trash|\.DS_Store|\.CFUserTextEncoding)$')
for f in ~/package.json ~/pnpm-lock.yaml ~/package-lock.json ~/node_modules; do
  [ -e $f ] && warn "家目錄有專案檔: $f（node/pnpm 會把家目錄當成專案根目錄，確認來源後處理）"
done
info "家目錄其他項目（人工確認沒有奇怪的東西）:"
info "$(print -r -- $junk | tr '\n' ' ')"
d=$(ls ~/Downloads 2>/dev/null | grep -i -E 'ollama|opencode|open.?design|open-webui|antigravity|nvm')
[[ -z $d ]] && ok "~/Downloads 沒有本 SOP 相關的安裝檔殘留" || warn "~/Downloads 有 SOP 相關檔案: $(print -r -- $d | tr '\n' ' ')"
d2=$(ls ~/Downloads 2>/dev/null | grep -i -E '\.(dmg|pkg)$' | grep -v -i -E 'ollama|opencode|open.?design|open-webui|antigravity|nvm')
[[ -n $d2 ]] && info "~/Downloads 其他安裝檔（非本 SOP，自行決定是否刪除）: $(print -r -- $d2 | tr '\n' ' ')"
info "/usr/local/bin: $(ls -1 /usr/local/bin 2>/dev/null | tr '\n' ' ')"
info "各目錄大小:"
for d in ~/.ollama ~/open-webui-data ~/Services ~/.nvm ~/.cache ~/.local/share/uv; do
  [ -e $d ] && info "$(du -sh $d 2>/dev/null)"
done

# ---------------------------------------------------------------
sec "14. 系統安全基線"
fv=$(fdesetup status 2>&1 | head -1)
[[ $fv == *"is On"* ]] && ok "FileVault 已開啟" || warn "FileVault: $fv"
sip=$(csrutil status 2>&1)
[[ $sip == *enabled* ]] && ok "SIP 已啟用" || bad "SIP: $sip"
gk=$(spctl --status 2>&1)
[[ $gk == *enabled* ]] && ok "Gatekeeper 已啟用" || bad "Gatekeeper: $gk"
fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1)
[[ $fw == *enabled* ]] && ok "應用程式防火牆已開啟" || warn "應用程式防火牆: $fw"
info "全部對外監聽的 TCP 埠（預期只有系統服務，不應出現 8080/11434/7456）:"
info "$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && ($9 ~ /^\*:/ || $9 ~ /^0\.0\.0\.0:/ || $9 ~ /^\[::\]:/){print $1" "$9}' | sort -u)"

# ---------------------------------------------------------------
sec "15. 密鑰與權限"
perm() { stat -f '%Lp' "$1" 2>/dev/null; }
owner() { stat -f '%Su' "$1" 2>/dev/null; }
chk_perm() {
  local f=$1 want=$2 p
  [ -e $f ] || { info "不存在，略過: $f"; return; }
  p=$(perm $f)
  if [[ $p == $want ]]; then ok "$f 權限 $p"
  else bad "$f 權限 $p（建議 $want，修復: chmod $want ${(q)f}）"; fi
  [[ $(owner $f) == $(id -un) ]] || bad "$f 擁有者不是你: $(owner $f)"
}
chk_perm ~/.webui_secret_key 600
chk_perm $DATA 700
chk_perm $DATA/webui.db 600
chk_perm ~/.ssh 700
for k in ~/.ssh/id_*(N); do [[ $k == *.pub ]] || chk_perm $k 600; done
pp=$(perm $PLIST)
if [[ -n $pp ]]; then
  [[ $pp == 644 || $pp == 600 ]] && ok "plist 權限 $pp" || bad "plist 權限 $pp（不可被群組或其他人寫入，修復: chmod 644 ${(q)PLIST}）"
fi
if [ -d ~/.local/bin ]; then
  w=$(find ~/.local/bin -maxdepth 1 \( -perm -020 -o -perm -002 \) 2>/dev/null)
  [[ -z $w ]] && ok "~/.local/bin 內無群組或其他人可寫的項目" || bad "可被他人寫入: $w"
  chk_perm ~/.local/bin 755
  info "~/.local/bin 內容（請人工確認全部認得）:"
  info "$(ls -lA ~/.local/bin 2>/dev/null)"
fi
for d in /opt/homebrew/bin /opt/homebrew/Cellar; do
  w=$(find $d -maxdepth 1 -perm -002 2>/dev/null | head -3)
  [[ -z $w ]] && ok "$d 無任何人可寫的項目" || bad "$d 有任何人可寫的項目: $w"
done

if [ -f ~/.config/gh/hosts.yml ]; then
  if grep -q 'oauth_token' ~/.config/gh/hosts.yml 2>/dev/null; then
    bad "gh token 以純文字存在 ~/.config/gh/hosts.yml（應改存 Keychain：gh auth logout 後重新 gh auth login）"
  else
    ok "gh hosts.yml 沒有純文字 token（由系統憑證庫保管）"
  fi
fi
scopes=$(gh auth status 2>&1 | grep -i 'token scopes')
info "gh $scopes"
[[ $scopes == *workflow* ]] && info "gh token 含 workflow 權限（你已決定保留，會影響 push 到 .github/workflows 的操作；不需要時才 gh auth refresh --remove-scopes workflow）"
[[ $scopes == *delete_repo* || $scopes == *admin:* ]] && bad "gh token 含高風險權限: $scopes"
cred=$(git config --global --get-regexp '^credential\..*helper$' 2>/dev/null)
info "git credential.helper: ${cred:-未設定}"
[[ $cred == *osxkeychain* || $cred == *gh* || $cred == *manager* ]] && ok "git 憑證由 helper 管理" || warn "git credential.helper 未設定或未知，避免憑證落在純文字檔"
[ -f ~/.netrc ] && bad "~/.netrc 存在（常含明文憑證）" || ok "沒有 ~/.netrc"

if [ -d $OD_DIR ]; then
  e=$(find $OD_DIR -maxdepth 2 -name '.env*' -not -name '.env.example' -not -path '*/node_modules/*' 2>/dev/null)
  [[ -z $e ]] && ok "Open Design repo 內沒有 .env 檔" || warn "repo 內有 .env 檔，確認已被 .gitignore 排除: $e"
fi
hit=$(grep -n -i -E '(api[_-]?key|secret|token|password)[[:space:]]*=' ~/.zshenv ~/.zprofile ~/.zshrc 2>/dev/null | sed -E 's/=.*/=<已隱藏>/')
[[ -z $hit ]] && ok "shell 設定檔沒有明文金鑰" || bad "shell 設定檔含疑似金鑰（值已隱藏）: $hit"

# ---------------------------------------------------------------
sec "16. 版本基準比對（是否可重現）"
cmp_ver() {
  local name=$1 got=$2 want=$3
  [[ $got == $want ]] && ok "$name = $got" || warn "$name = ${got:-未取得}（基準 $want）"
}
cmp_ver node "$(node -v 2>/dev/null)" $EXP_NODE
cmp_ver pnpm "$(pnpm -v 2>/dev/null)" $EXP_PNPM
cmp_ver open-webui "$(uv tool list 2>/dev/null | awk '/^open-webui/{print $2}' | tr -d v)" $EXP_OPENWEBUI
ocv=$(opencode --version 2>&1 | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -n $ocv ]]; then
  [[ $(printf '%s\n%s\n' $EXP_OPENCODE_MIN $ocv | sort -V | head -1) == $EXP_OPENCODE_MIN ]] && ok "opencode $ocv (>= $EXP_OPENCODE_MIN)" || warn "opencode $ocv 低於 $EXP_OPENCODE_MIN"
fi
[[ $(corepack --version 2>/dev/null) ]] && info "pnpm 由 corepack 管理: $(corepack --version)；project 內可用 package.json 的 packageManager 欄位固定 pnpm 版本"
info "nvm 預設別名: $(nvm alias default 2>/dev/null | head -1)"

if [ -d $OD_DIR/.git ]; then
  sha=$(git -C $OD_DIR rev-parse HEAD 2>/dev/null)
  info "Open Design commit: $sha"
  info "Open Design branch: $(git -C $OD_DIR rev-parse --abbrev-ref HEAD 2>/dev/null) / 最近提交: $(git -C $OD_DIR log -1 --format='%ci %s' 2>/dev/null)"
  [[ $(git -C $OD_DIR rev-parse --is-shallow-repository 2>/dev/null) == true ]] && warn "Open Design 是淺層 clone（--depth 1），無法 checkout 舊版或回滾；需要時 git fetch --unshallow" || ok "Open Design 是完整 clone"
  [ -f $OD_DIR/pnpm-lock.yaml ] && ok "pnpm-lock.yaml 存在 (sha256 $(shasum -a 256 $OD_DIR/pnpm-lock.yaml | cut -c1-16)…)" || bad "找不到 pnpm-lock.yaml，無法可重現安裝"
  [[ -z $(git -C $OD_DIR status --short pnpm-lock.yaml 2>/dev/null) ]] && ok "pnpm-lock.yaml 沒有被安裝流程修改" || bad "pnpm-lock.yaml 與 commit 不一致（安裝時被改動）"
  pm=$(grep -o '"packageManager"[^,]*' $OD_DIR/package.json 2>/dev/null)
  info "repo 指定的 packageManager: ${pm:-未指定}"
  pmv=$(print -r -- $pm | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  gpv=$(pnpm -v 2>/dev/null)
  [[ -n $pmv && -n $gpv && ${pmv%%.*} != ${gpv%%.*} ]] && warn "repo 要求 pnpm $pmv，全域是 $gpv；請在 repo 內執行 pnpm -v 確認實際使用的版本"
  nv=$(cat $OD_DIR/.nvmrc $OD_DIR/.node-version 2>/dev/null | head -1)
  eng=$(grep -A2 '"engines"' $OD_DIR/package.json 2>/dev/null | tr -d '\n ')
  info "repo 指定的 Node: ${nv:-未指定} ${eng}"
fi

info "Ollama 模型 digest（可記錄，確認日後標籤沒有偷偷換內容）:"
info "$(ollama list 2>/dev/null)"
for m in qwen2.5 bge-m3; do
  bl=$(ollama show $m --modelfile 2>/dev/null | grep -E '^FROM ' | head -1 | grep -o 'sha256-[0-9a-f]*' | cut -c1-23)
  mid=$(ollama list 2>/dev/null | awk -v m="$m" '$1 ~ "^"m {print $2; exit}')
  info "$m id=${mid:-?} blob=${bl:-（modelfile 沒有 blob 路徑，以 id 為準）}"
done

# ---------------------------------------------------------------
sec "17. 開發版本控制（git 衛生）"
gn=$(git config --global user.name); ge=$(git config --global user.email)
[[ -n $gn && -n $ge ]] && ok "git user: $gn <$ge>" || bad "git user.name / user.email 未設定"
di=$(git config --global init.defaultBranch)
[[ -n $di ]] && ok "init.defaultBranch = $di" || warn "init.defaultBranch 未設定"
gi=$(git config --global core.excludesfile)
if [[ -n $gi && -f ${gi/#\~/$HOME} ]]; then
  ok "全域 gitignore: $gi"
  for pat in '.env' '.DS_Store' 'node_modules' '*.pem' '*.key' 'graphify-out/'; do
    grep -qxF -- $pat ${gi/#\~/$HOME} || warn "全域 gitignore 缺少 $pat"
  done
else
  warn "沒有全域 gitignore（建議至少排除 .env、.DS_Store、*.pem、*.key、node_modules）"
fi
sg=$(git config --global commit.gpgsign)
[[ $sg == true ]] && ok "commit 簽章已啟用" || info "commit 簽章未啟用（需要可驗證作者時再設定 gpg 或 ssh signing）"
[[ $(git config --global --get-regexp '^url\..*insteadof' 2>/dev/null) ]] && info "git url 重寫: $(git config --global --get-regexp '^url\..*insteadof')"
info "ssh 金鑰: $(print -rl -- ~/.ssh/*.pub(N) | tr '\n' ' ')"
info "你的 git repo（家目錄下 3 層內）:"
info "$(find ~ -maxdepth 3 -name .git -type d -not -path '*/node_modules/*' -not -path '*/.nvm/*' -not -path '*/Library/*' 2>/dev/null | sed 's#/.git$##')"
tr_s=(${(f)"$(find ~ -maxdepth 3 -type f \( -name '.env' -o -name '*.pem' -o -name 'id_rsa' -o -name 'id_ed25519' \) -not -path '*/node_modules/*' -not -path '*/.ssh/*' -not -path '*/.ollama/*' -not -path '*/Library/*' 2>/dev/null)"})
if (( ${#tr_s} == 0 )); then
  ok "家目錄 3 層內沒有 .env/.pem 等敏感檔"
else
  for f in $tr_s; do
    dir=${f:h}
    if git -C $dir rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if git -C $dir ls-files --error-unmatch ${f:t} >/dev/null 2>&1; then
        bad "$f 已被 git 追蹤（若曾推送到遠端，內容視為外洩，需更換金鑰）"
      elif git -C $dir check-ignore -q ${f:t}; then
        ok "$f 在 git repo 內，已被 .gitignore 排除"
      else
        warn "$f 在 git repo 內且未被忽略，commit 時可能被加入"
      fi
    else
      warn "$f 不在 git repo 內（確認用途與權限）"
    fi
  done
fi

# ---------------------------------------------------------------
sec "18. 桌面版 App 一覽（opencode / Open Design）"
info "Homebrew 內 opencode: $(brew list --cask 2>/dev/null | grep -i opencode | sed 's/^/cask:/' | tr '\n' ' ') $(brew list --formula 2>/dev/null | grep -i opencode | sed 's/^/formula:/' | tr '\n' ' ')"
ovf=$(brew list --versions opencode-v2 2>/dev/null | awk '{print $2}')
ovc=$(brew list --cask --versions opencode-desktop 2>/dev/null | awk '{print $2}')
if [[ -n $ovf && $ovf == $ovc ]]; then ok "opencode 終端機版與桌面版版本一致: $ovf"
else info "opencode 終端機版 ${ovf:-?} / 桌面版 ${ovc:-?}（桌面版會自動更新，不一致不一定有問題）"; fi
apps2=( /Applications/(#i)*opencode*.app(N) ~/Applications/(#i)*opencode*.app(N) )
info "opencode 桌面版 app: ${apps2[*]:-無}"
info "Open Design 桌面版 app: ${od_apps[*]:-無}"
info "已裝的 /Applications（人工確認有沒有不認得的）: $(ls -1 /Applications 2>/dev/null | sed 's/\.app$//' | tr '\n' ',')"

# ---------------------------------------------------------------
print
print -r -- "=== 結果: OK $PASS / WARN $WARN / FAIL $FAIL ==="
print -r -- "需要手動確認: 重開機後 Open WebUI 是否自動啟動、登入項目、Ollama App 設定、Open Design 桌面版內的模型與 MCP 設定。"
