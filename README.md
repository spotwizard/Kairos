# Kairos

Kairos 是 macOS 上的終端影像工作流儀表板，整合 RAW 匯入、照片案件整理，以及 Adobe Photoshop／Camera Raw 修圖輸出流程。

## 使用方式

```bash
kairos
```

所有選項選單都使用上下方向鍵選擇，按 Enter 確認，按 ESC 返回上一層；在主選單按 ESC 會離開 Kairos。

主選單提供：

- **傳輸記憶卡 RAW 檔案**：把記憶卡裡的 RAW 依拍攝日期傳輸到原圖封存目錄，來源檔會保留。
- **轉移 RAW 檔案**：把 Transfer 裡的 `名稱-YYYYMMDD` 目錄轉移成攝影案件。
- **修圖**：選擇攝影專案後執行重新修圖、前置作業、載入 RAW、開啟 PSD 檔案或輸出 IG／FB 成品。

進入 AfterRAW 後，先列出 Dropbox 攝影專案，依各專案內照片（含子目錄）的最新修改時間由新到舊排列；沒有照片的專案列在最後。不會預設或沿用上次修圖專案。

選定專案後顯示操作選單：

```text
1  重新修圖
2  前置作業
3  載入 RAW
4  開啟 PSD 檔案
5  IG＋FB 後置輸出
6  僅 IG 後置輸出
7  僅 FB 後置輸出
```

選定操作後，會再列出檔名供選擇，同樣使用上下方向鍵。「開啟 PSD 檔案」列出專案 `PSD` 目錄內的 `.psd` 檔名，其他操作列出專案 `RAW` 目錄內的 `.ARW`／`.RAW` 檔名：

- **空白鍵**：勾選或取消勾選目前項目，可勾選多個檔名。
- **Enter**：確認勾選的項目；沒有勾選任何項目時，直接選定游標所在的單一項目。
- **ESC**：不執行，回到操作選單。

勾選「全部 RAW 檔案」或「全部 PSD 檔案」時處理整個專案，行為與原本相同（同時勾選的檔名會被忽略）。只勾選檔名時只處理這些檔案。

專案沒有 RAW 檔時不顯示此清單。選好檔案後會立即執行；只有「重新修圖」會先要求確認（預設為取消）。程序成功完成後會自動回到目前專案的操作選單，不需要按 Enter；程序失敗時會停在錯誤訊息，按 Enter 才返回選單。

AfterRAW 各層選單都以 ESC 返回上一層：RAW 檔案清單 → 操作選單 → 專案清單 → 主選單。每層選單標題會註明 ESC 返回的位置。

## 固定路徑

| 用途 | 路徑 |
|---|---|
| 記憶卡來源 | `/Volumes/Untitled/DCIM` |
| 原圖封存 | `/Users/robbie/Pictures/原圖/YYYYMMDD` |
| Transfer 來源 | `/Users/robbie/Pictures/Transfer` |
| 攝影案件 | `/Users/robbie/Dropbox/__攝影` |
| IG PSD template | `/Users/robbie/Dropbox/__攝影/__IG 底版.psd` |

## AfterRAW

- 重新修圖會刪除專案 `RAW` 目錄下的 `.xmp`、`.acr` 檔案，以及 `PSD`、`IG`、`FB` 目錄，接著執行前置作業。刪除後無法復原。指定 RAW 檔名時，只刪除這些檔案的 `.xmp`、`.acr`，以及 `PSD`、`IG`、`FB` 目錄內同名的 `.psd`、`.jpg`，再只對這些檔案執行前置作業。
- 前置作業會寫入 Adobe Color、鏡頭校正、4:5 置中裁切與雜訊設定，操作 Camera Raw 去除雜色，最後重新載入 RAW 等待人工修圖。
- 載入只開啟 RAW，不寫入 sidecar 或輸出成品。
- 所有操作在讀取檔案前，會先把要處理的檔案（RAW 與其 `.xmp`、`.acr`、PSD、IG 底版）完整讀取一遍；被 Dropbox 設為「僅供線上存取」的檔案會在這次讀取時由 Dropbox 下載到本機，再交給 Photoshop。有檔案讀不到或下載失敗時中止，不開啟 Photoshop。這只是把檔案下載下來，不會把資料夾永久設為「可供離線存取」，Dropbox 日後仍可能把久未使用的檔案改回僅供線上存取。
- 開啟 PSD 檔案會用 Photoshop 開啟選定專案 `PSD` 目錄下的 `.psd` 檔案。
- 後置輸出只處理同時具有 `.xmp` 與 `.acr` 的 `.ARW`／`.RAW`，建立 PSD 並輸出 IG、FB JPG。
- 後置程序會沿用原本的覆寫與孤兒輸出清除行為，沒有 preview、確認或 dry-run。指定 RAW 檔名時只覆寫這些檔案的成品，不清除其他輸出檔。
- 指定 RAW 檔名的前置作業仍會跳過同時已有 `.xmp` 與 `.acr` 的檔案；要重做該檔請使用「重新修圖」。

## 環境需求

- macOS
- Homebrew `gum`
- `exiftool`
- Adobe Photoshop 2026 或 Adobe Photoshop Beta
- `swift`、`osascript` 與 Terminal 的 Accessibility automation 權限

若 TUI dependency 缺失：

```bash
brew install gum
```

`kairos` 指令由下列連結提供；`~/.local/bin` 必須位於 `PATH`：

```bash
ln -sfn /Users/robbie/Projects/Kairos/kairos ~/.local/bin/kairos
```

## 測試

```bash
./tests/run.sh
```

測試只操作暫存 fixture 與 mock worker，不會搬移、覆寫或清除正式照片，也不會啟動 Photoshop UI automation。RAW 檔案多選清單的按鍵測試需要 `python3`；找不到時會略過該項測試。
