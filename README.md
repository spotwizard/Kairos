# Kairos

Kairos 是 macOS 上的終端影像工作流儀表板，整合 RAW 匯入、照片案件整理，以及 Adobe Photoshop／Camera Raw 修圖輸出流程。

## 使用方式

```bash
kairos
```

所有選項選單都使用上下方向鍵選擇，按 Enter 確認，按 ESC 返回上一層；在主選單按 ESC 會離開 Kairos。

主選單提供：

- **傳輸記憶卡 RAW 檔案**：把記憶卡裡的 RAW 依拍攝日期傳輸到原圖封存目錄，來源檔會保留。複製與驗證都成功後，會自動退出記憶卡（`diskutil eject /Volumes/Untitled`），畫面顯示「已退出記憶卡，可以拔除」即可拔除；有其他程式正在使用記憶卡而退出失敗時，會每 3 秒重試、共 3 次，仍失敗就提示到 Finder 手動退出，傳輸結果仍算成功。複製或驗證失敗時不退出，方便重新傳輸。
- **轉移 RAW 檔案**：把 Transfer 裡的 `名稱-YYYYMMDD` 目錄轉移成攝影案件。
- **修圖**：選擇攝影專案後執行重新修圖、前置作業、載入 RAW、開啟 PSD 檔案或輸出 IG／FB 成品。

進入 AfterRAW 後，先排除名稱為「咖啡」「街拍」「夕陽」「橋樑」「人像」的目錄，以及名稱以「__」加數字開頭的目錄（例如 `__2025`、`__01 舊案`），再列出 Dropbox 攝影專案，依各專案內照片（含子目錄）的最新修改時間由新到舊排列；沒有照片的專案列在最後。不會預設或沿用上次修圖專案。

專案清單可以直接打字搜尋，不需要先按其他鍵：

- **輸入文字**：只列出名稱包含這些文字的專案，英文不分大小寫，可輸入中文；以空白分隔多個關鍵字時，專案名稱必須包含全部關鍵字（例如 `石 2026`）。
- **Backspace**：刪除最後一個字。
- **上下方向鍵**：在符合的專案間移動；**Enter**：選定游標所在的專案；沒有符合的專案時按 Enter 不會有動作。
- **ESC**：不論是否已輸入搜尋文字，按一次就返回主選單。

因為打字會變成搜尋文字，專案清單不能用 `j`、`k` 移動。

選定專案後顯示操作選單：

```text
1  重新修圖
2  前置作業
3  載入 RAW
4  開啟 PSD 檔案
5  輸出PSD+IG+FB
6  輸出PSD
7  輸出IG+FB
8  輸出IG
9  輸出FB
```

選定操作後，會再列出檔名供選擇，同樣使用上下方向鍵。「開啟 PSD 檔案」「輸出IG+FB」「輸出IG」「輸出FB」列出專案 `PSD` 目錄內的 `.psd` 檔名，其他操作列出專案 `RAW` 目錄內的 `.ARW`／`.RAW` 檔名：

- **空白鍵**：勾選或取消勾選目前項目，可勾選多個檔名。
- **Enter**：確認勾選的項目；沒有勾選任何項目時，直接選定游標所在的單一項目。
- **ESC**：不執行，回到操作選單。

勾選「全部 RAW 檔案」或「全部 PSD 檔案」時處理整個專案，行為與原本相同；勾選「全部」會自動取消已勾選的檔名，之後再勾選檔名則會自動取消「全部」。只勾選檔名時只處理這些檔案。

專案沒有可列出的 RAW（或 PSD）檔時不顯示此清單。選好檔案後會立即執行；只有「重新修圖」會先要求確認（預設為取消）。程序成功完成後會自動回到目前專案的操作選單，不需要按 Enter；程序失敗時會停在錯誤訊息，按 Enter 才返回選單。

AfterRAW 各層選單都以 ESC 返回上一層：RAW／PSD 檔案清單 → 操作選單 → 專案清單 → 主選單。每層選單標題會註明 ESC 返回的位置。

## 蓋上螢幕後繼續執行

「傳輸記憶卡 RAW 檔案」「轉移 RAW 檔案」與五種輸出（輸出PSD+IG+FB、輸出PSD、輸出IG+FB、輸出IG、輸出FB）不需要操作畫面，執行期間蓋上 MacBook 螢幕，Mac 仍會繼續執行：

- 開始前會要求輸入電腦的登入密碼（幾分鐘內剛輸入過則不再詢問），用 `pmset -a disablesleep 1` 暫時關閉睡眠。要求輸入密碼前，會先把輸入法切換成英數輸入法（系統設定中的英文鍵盤配置，通常是「ABC」），避免用注音等中文輸入法打密碼；輸入完畢後不會切回原本的輸入法，剛輸入過密碼而不再詢問時也不切換。程序結束、失敗、按 Ctrl-C 或關掉終端機視窗時，都會自動恢復原本的睡眠設定。原本就關閉睡眠的電腦，結束後維持關閉。
- 沒有輸入密碼或密碼錯誤時仍照常執行，但會提示不要蓋上螢幕；蓋上後 Mac 會睡眠，程序暫停到再次打開螢幕。
- 螢幕打開時也會防止閒置睡眠。
- 傳輸記憶卡時，記憶卡與讀卡機要保持連接。關閉睡眠時放進包包或在電池供電下蓋上，電腦會持續耗電與發熱。

重新修圖、前置作業需要點擊 Camera Raw 畫面，載入 RAW、開啟 PSD 檔案是開檔給人工修圖，這四項不會關閉睡眠，執行時請保持螢幕打開。

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
- 所有操作在讀取檔案前，會先檢查要處理的檔案（RAW 與其 `.xmp`、`.acr`、PSD、IG 底版）是否為 Dropbox 的「僅供線上存取」佔位檔（大小為 0、帶 `com.dropbox.placeholder` 屬性）。是的話用 `open -g -a Dropbox` 請 Dropbox 下載，等到全部下載完成（最多 10 分鐘，每 10 秒顯示剩餘檔案數）才交給 Photoshop；逾時、下載後仍是 0 位元組時，列出檔名並中止，不開啟 Photoshop。Dropbox 下載完會用預設程式開啟檔案，因此下載後會自動關閉因此才被開啟的「預覽程式」「照片」（原本就開著的不動），並關閉「未設定應用程式來打開文件」對話框。這只是把檔案下載下來，不會把資料夾永久設為「可供離線存取」，Dropbox 日後仍可能把久未使用的檔案改回僅供線上存取。
- 開啟 PSD 檔案會用 Photoshop 開啟選定專案 `PSD` 目錄下的 `.psd` 檔案。
- 輸出選項分成根據 RAW 與根據 PSD 兩類：

  | 選項 | 來源 | 產生 |
  |---|---|---|
  | 輸出PSD+IG+FB | RAW | 重新產生 PSD，再從新 PSD 輸出 IG、FB JPG |
  | 輸出PSD | RAW | 只重新產生 PSD |
  | 輸出IG+FB | PSD | 從現有 PSD 重新產生 IG、FB JPG |
  | 輸出IG | PSD | 從現有 PSD 重新產生 IG JPG |
  | 輸出FB | PSD | 從現有 PSD 重新產生 FB JPG |

- 根據 RAW 的選項只處理同時具有 `.xmp` 與 `.acr` 的 `.ARW`／`.RAW`。重新產生 PSD 時複製 IG 底版，放入 RAW 並轉成智慧型物件，在智慧型物件內加上曝光度調整、縮成寬 4000px，再置中於畫布後存檔。
- 根據 PSD 的選項讀取專案 `PSD` 目錄內的 `.psd`，不讀 RAW、不重建 PSD，也不修改 PSD：IG 是整張畫布轉成 sRGB 輸出，FB 是 PSD 內第一個智慧型物件圖層的內容轉成 sRGB 輸出。因此在 Photoshop 手動修改 PSD 後，可以直接用這三個選項重新輸出 JPG。
- 輸出程序會覆寫同名成品並清除孤兒輸出檔，沒有 preview、確認或 dry-run：根據 RAW 時刪除沒有對應 RAW 的 PSD 與要輸出的 IG／FB JPG；根據 PSD 時刪除沒有對應 PSD 的 IG／FB JPG。指定檔名時只覆寫這些檔案的成品，不清除其他輸出檔。
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
