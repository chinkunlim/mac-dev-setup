# 本機埠號總表（Port Registry）

這台電腦上所有本機服務的埠號都登記在這裡。開新專案、設定 `.env` 的 `HTTP_PORT` 前先看這張表，選一個沒人用的埠號，再把它加進來，避免兩個服務同時開時衝突。

所有自建服務只綁 `127.0.0.1`，網址寫 `http://127.0.0.1:<port>`，不要寫 `localhost`，也不要綁 `0.0.0.0`。

| 埠號 | 服務 | 專案 / 來源 | 啟動方式 |
|---|---|---|---|
| 5000、7000 | macOS 控制中心（AirPlay 接收器） | 系統內建 | 系統自動，不要使用 |
| 7456 | Open Design | 桌面 App（SOP §7.2） | 打開 App |
| 8080 | Open WebUI | SOP §6 | launchd 開機自動啟動 |
| 8765 | literature-fetch 網頁 / API | `projects/literature-fetch` | `uv run`（見該專案 README） |
| 8766 | 專案母版的範例網頁 | 專案模板 | 開發時手動啟動 |
| 8767 | literature-parser 網頁 / API | `projects/literature-parser` | `uv run`（見該專案 README） |
| 8768 | **Gemini Notebook 學習工作室**（正式） | `projects/notebooklm-batch-studio` | 雙擊「Gemini Notebook 學習工作室.app」 |
| 8769 | 學習工作室：開發驗證用（不自動處理佇列） | 同上 | 開發時由 Claude Code 啟動 |
| 8770 | 學習工作室：隔離測試資料用 | 同上 | 開發時由 Claude Code 啟動 |
| 11434 | Ollama | SOP §2.1 | brew services 開機自動啟動 |

**下一個可用的埠號**：`8771`。用掉之後，請更新這一行，並在上表加一列。

## 查詢某個埠號是誰在用

```zsh
lsof -nP -iTCP:8768 -sTCP:LISTEN
```

## 列出所有正在監聽的埠號

```zsh
lsof -nP -iTCP -sTCP:LISTEN | awk 'NR>1{print $1, $9}' | sort -u
```
