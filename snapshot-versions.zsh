#!/bin/zsh
# snapshot-versions.zsh  產生版本基準檔，供版本控制與日後比對。
# 只會寫入輸出資料夾（預設 ~/dev-env-baseline），不會改動系統。
# 輸出不含 token、密鑰、資料庫內容。用法：zsh snapshot-versions.zsh [輸出資料夾]

[ -f ~/.zprofile ] && source ~/.zprofile >/dev/null 2>&1
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1

OUT=${1:-$HOME/dev-env-baseline}
OD_DIR="$HOME/Services/open-design-cli"
mkdir -p "$OUT/manifests"
chmod 700 "$OUT"
cd "$OUT" || exit 1

{
  echo "snapshot: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
  echo "xcode-select: $(xcode-select -p 2>&1)"
  echo "xcodebuild: $(xcodebuild -version 2>&1 | tr '\n' ' ')"
  echo "brew: $(brew --version 2>&1 | head -1)"
  echo "git: $(git --version)"
  echo "gh: $(gh --version 2>&1 | head -1)"
  echo "uv: $(uv --version 2>&1)"
  echo "node: $(node -v 2>&1)"
  echo "npm: $(npm -v 2>&1)"
  echo "pnpm: $(pnpm -v 2>&1)"
  echo "pnpm (open-design packageManager): $(grep -o '"packageManager"[^,]*' "$OD_DIR/package.json" 2>/dev/null)"
  echo "opencode: $(opencode --version 2>&1 | head -1)"
  echo "ollama: $(ollama --version 2>&1 | head -1)"
  echo "agy: $(agy --version 2>&1 | head -1)"
  echo "graphify: $(graphify --version 2>&1 | head -1)"
} > versions.txt

brew list --versions > manifests/brew-versions.txt 2>&1
brew list --cask --versions > manifests/brew-cask-versions.txt 2>&1
brew tap > manifests/brew-taps.txt 2>&1
brew bundle dump --force --file="$OUT/Brewfile" >/dev/null 2>&1

uv python list --only-installed > manifests/uv-python.txt 2>&1
uv tool list --show-version-specifiers > manifests/uv-tools.txt 2>&1
UVT=$(uv tool dir 2>/dev/null)
if [ -x "$UVT/open-webui/bin/python" ]; then
  uv pip freeze --python "$UVT/open-webui/bin/python" > manifests/open-webui-python-freeze.txt 2>&1
fi

ls ~/.nvm/versions/node > manifests/node-versions.txt 2>&1
npm ls -g --depth=0 > manifests/npm-global.txt 2>&1

ollama list > manifests/ollama-models.txt 2>&1
: > manifests/model-blobs.txt
for m in ${(f)"$(ollama list 2>/dev/null | awk 'NR>1{print $1}')"}; do
  b=$(ollama show $m --modelfile 2>/dev/null | grep -E '^FROM ' | head -1 | grep -o 'sha256-[0-9a-f]*')
  id=$(ollama list 2>/dev/null | awk -v m="$m" '$1==m {print $2}')
  echo "$m id=${id:-unknown} blob=${b:-unknown}" >> manifests/model-blobs.txt
done

if [ -d "$OD_DIR/.git" ]; then
  {
    echo "remote: $(git -C $OD_DIR remote get-url origin)"
    echo "commit: $(git -C $OD_DIR rev-parse HEAD)"
    echo "branch: $(git -C $OD_DIR rev-parse --abbrev-ref HEAD)"
    echo "shallow: $(git -C $OD_DIR rev-parse --is-shallow-repository)"
    echo "dirty: $(git -C $OD_DIR status --short | wc -l | tr -d ' ') files"
    [ -f $OD_DIR/pnpm-lock.yaml ] && echo "pnpm-lock sha256: $(shasum -a 256 $OD_DIR/pnpm-lock.yaml | cut -d' ' -f1)"
  } > manifests/source-commits.txt
fi

# Open Design 桌面版（沒有 CLI repo 時，以 app 版本作為基準）
rm -f manifests/open-design-desktop.txt
for oa in "/Applications/Open Design.app" "$HOME/Applications/Open Design.app"; do
  [ -d "$oa" ] || continue
  {
    echo "path: $oa"
    echo "bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$oa/Contents/Info.plist" 2>/dev/null)"
    echo "version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$oa/Contents/Info.plist" 2>/dev/null)"
    echo "signing: $(codesign -dv --verbose=2 "$oa" 2>&1 | grep -E '^(Authority=Developer ID Application|TeamIdentifier)' | tr '\n' ' ')"
  } >> manifests/open-design-desktop.txt
done

cp -p ~/Library/LaunchAgents/com.openwebui.service.plist manifests/ 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables' manifests/com.openwebui.service.plist > manifests/openwebui-env.txt 2>/dev/null

print -r -- "已寫入 $OUT"
ls -1 "$OUT" "$OUT/manifests"
print -r -- "提醒：此資料夾不含密鑰，可以放進私有 git repo；若要公開，先自行檢查內容。"
