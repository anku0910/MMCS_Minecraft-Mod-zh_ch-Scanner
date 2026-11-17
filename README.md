# moddedMinecraft-Scanner-zh_cn

掃描 Minecraft 模組包（或任何資料夾）中所有主檔名為 `zh_cn` 的檔案與資料夾，遞迴列出位置、大小與修改日期，並自動配對顯示同資料夾的 `zh_tw`。

A tiny, dependency-free PowerShell GUI that recursively scans a folder tree for files/folders whose base name is `zh_cn` (any extension), lists where they are, and detects matching `zh_tw` siblings — with a WizTree-style treemap view.

## 特色

- **輕量化**：純 Windows PowerShell 5.1 + GDI+，零相依、免安裝，全部程式碼約 30 KB
- **背景掃描**：Runspace 背景執行不卡 UI，即時顯示進度（已掃 N 個資料夾），可隨時取消
- **快速掃描引擎**：.NET 手動遞迴，比 `Get-ChildItem -Recurse` 快；單一資料夾無權限僅跳過、不中斷整體掃描；自動避開 junction/symlink 防止無限迴圈
- **萬用字元比對**：支援 `zh_cn`、`zh_cn.*`、`zh_cn*`、`*zh_cn*`
- **zh_tw 配對偵測**：同資料夾有 `zh_cn` 時自動一併列出 `zh_tw`（**僅偵測**，不會建立或修改任何檔案）
- **WizTree 風格樹狀圖**：treemap 面積＝檔案大小、顏色＝語系
- **結果處理**：副檔名/大小/修改日期欄位、點欄位標題排序、複製路徑清單、匯出 CSV（Excel 可直接開）、開啟檔案或所在資料夾
- **排除資料夾**：預設跳過 `.git`、`node_modules`，可自行修改
- **記住設定**：路徑、比對值、排除清單、視窗位置大小，下次開啟自動恢復

## 系統需求

- Windows 10 / 11
- 使用內建的 Windows PowerShell 5.1 即可，**無需安裝任何東西**

## 使用方式

1. 下載：Code → Download ZIP（或 `git clone`）
2. 雙擊 `找 zh_cn 檔案.bat`
3. 輸入掃描路徑，四種方式任選：
   - 直接打字（有資料夾名稱自動補全，像檔案總管位址列）
   - 貼上路徑（Ctrl+V）
   - 把資料夾拖進視窗任何位置 → 自動填入並直接開掃
   - 把資料夾拖到 `找 zh_cn 檔案.bat` 上啟動
4. 按 Enter 或點「開始掃描」
5. 結果清單：雙擊任一列＝開啟所在資料夾；選取後可「開啟檔案」、「複製路徑」、「匯出 CSV」

### 檔名比對語法

| 輸入 | 意義 |
|---|---|
| `zh_cn` | 精確比對主檔名、忽略副檔名：`zh_cn.json`、`zh_cn.txt`、`zh_cn`（無副檔名）、資料夾 `zh_cn` |
| `zh_cn.*` | `zh_cn` + 任意副檔名（不含無副檔名的檔案與資料夾） |
| `zh_cn*` | 主檔名以 `zh_cn` 開頭（含 `zh_cn_backup.json`、`zh_cn_extra.md` 等） |
| `*zh_cn*` | 檔名任何位置含 `zh_cn`（如 `my_zh_cn.json`） |

比對值以 `zh_cn` 開頭時，會自動推導對應的 `zh_tw` 模式（`zh_cn` → `zh_tw`、`zh_cn.*` → `zh_tw.*`），同一資料夾內有 `zh_cn` 就會把旁邊的 `zh_tw` 一併列出，方便檢查缺漏。

### 樹狀圖（WizTree 風格）

掃描後點「樹狀圖」按鈕：

- **面積 = 檔案大小**，哪個資料夾、哪個檔案佔最多空間一目了然
- **顏色 = 語系**：綠藍 `zh_cn`、橘 `zh_tw`、灰「其他」
- 外層容器是資料夾（按內含結果檔案總大小分配），內層是個別檔案
- 滑鼠停留顯示完整路徑與大小（小檔案靠這個找）
- 超過 2000 個檔案時取前 2000 名，其餘合併為「其他 N 個」

### 排除資料夾

預設排除 `.git`、`node_modules`（不遞迴進入）。可輸入逗號分隔的資料夾名稱清單自訂，設定會自動保存到 `find_zh_cn.settings.json`。

## 檔案說明

| 檔案 | 說明 |
|---|---|
| `找 zh_cn 檔案.bat` | 啟動器（雙擊入口，內容純 ASCII 避免編碼問題） |
| `find_zh_cn.ps1` | 主程式（PowerShell WinForms GUI，UTF-8 with BOM） |
| `find_zh_cn.settings.json` | 執行後自動產生的個人設定（已 gitignore，不會上傳） |

## 授權

MIT
