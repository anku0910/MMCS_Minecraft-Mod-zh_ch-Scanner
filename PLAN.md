# PLAN：MMCS GUI 佈局重構（Dock 自動縮放）

## Context
目前 `find_zh_cn.ps1` 的視窗佈局全用固定 `Location`/`Size`/`Anchor`：
- 結果清單 `ListView` 高度固定，拉大視窗時清單不會變大，多餘空間浪費；拉小視窗時結果被壓縮到只剩一點點。
- 底部按鈕（複製路徑、匯出 CSV、開啟檔案、開所在資料夾、樹狀圖）座標固定，拉視窗時不會跟著移動或變寬。
- 需要改為：視窗越大，結果清單越大；底部按鈕永遠貼在視窗最下方。

## 目標名稱
- 程式標題：`MMCS - Minecraft Mod zh_cn Scanner`
- 專案/Repo：`moddedMinecraft-Scanner-zh_cn`（保持不變）

## Approach（僅一種方案）
採用 WinForms `Dock` 佈局，三層：
1. **頂部 Panel `Dock=Top`**：路徑輸入、檔名比對、排除資料夾（高度固定，內部控制項保留固定位置並設 `Anchor=Right` 讓輸入框隨寬度擴展）。
2. **中間 `ListView` `Dock=Fill`**：佔據剩餘所有空間，視窗拉大時自動變大、顯示更多行；拉小不會壓縮到只剩一點點。
3. **底部 Panel `Dock=Bottom`**：`lblCount` + 五顆按鈕（高度固定，永遠貼在視窗最下方）。

刪除舊的 `Resize` 事件（Dock 佈局不再需要手動算高度）。

## Files to modify
- `E:/For Me/翻譯語言包工具/尋找zh_cn/find_zh_cn.ps1` — UI 建立區塊（約行 61–178）整段替換；表單標題改為 `MMCS - Minecraft Mod zh_cn Scanner`；刪除 Resize 事件。
- `E:/For Me/翻譯語言包工具/尋找zh_cn/README.md` — 若標題/截圖說明需同步（可選，視是否涉及圖片）。
- 不動：掃描 worker、Show-Results、Finish-Scan、TM-* 樹狀圖、設定讀寫、CSV 匯出、邏輯皆不變。

## Reuse（現有程式碼，不改動）
- `Show-Results`（行 266–288）：只需 `ListView` 物件不變，可直接复用。
- `Finish-Scan`、`Start-Scan`、`Cleanup-Scan`、`Format-Size`：不變。
- `TM-Draw` / `TM-Squarify` / `Show-Treemap`：樹狀圖視窗本身已用 `Dock=Fill` Panel，不變。
- 背景掃描 Runspace：不變。

## Steps
1. [ ] 用 Python 腳本將 `find_zh_cn.ps1` UI 建立區塊替換為 Dock=Top/Fill/Bottom 三層佈局（安全替換，不透過 edit 工具避免參數破壞）。
2. [ ] 表單標題改為 `MMCS - Minecraft Mod zh_cn Scanner`。
3. [ ] 刪除舊的 `$form.Add_Resize` 區塊。
4. [ ] 補上 UTF-8 BOM（Windows PowerShell 5.1 需要）。
5. [ ] PowerShell 語法檢查（0 錯誤）。
6. [ ] 執行 `.bat` 手動驗證：拉大/拉小視窗，結果清單與按鈕行為是否符合預期。
7. [ ] 提交 git 並推送 GitHub。

## Verification
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File find_zh_cn.ps1` 語法檢查（透過 Parser）。
- 手動開啟 `.bat`：拉視窗到最大，確認結果清單佔滿中間、按鈕區貼底；拉到最小，確認清單不會被壓到只剩一行，按鈕仍可見。
- 樹狀圖視窗開啟正常。

---

⚠️ Plannotator planning phase：本計劃僅為規劃，尚未對代碼庫做任何變更。確認後我會執行實作。