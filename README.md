# 33 Works Safe Duplicate File Cleaner

> 找出檔名不同、位置不同，但內容完全相同的檔案。先確認，再安全整理。  
> Find files with different names or locations but identical contents. Review first, then clean up safely.

![33 Works](app/assets/33works-logo.png)

這是一套給 Windows 使用者的重複檔案整理工具。它不只比較檔名，而是先依副檔名與檔案大小篩選，再使用 SHA-256 核對檔案內容。

只有內容完全相同的檔案才會列入同一組；工具不會自動替使用者刪除檔案。

## Why this tool｜為什麼製作它

工作資料經常被複製到不同資料夾，甚至改成不同檔名。只看名稱很難判斷是否能刪除，而直接交給清理軟體自動處理又容易不安心。

本工具的設計重點是：

- Exact-content matching with SHA-256｜使用 SHA-256 核對實際內容
- Human review before cleanup｜每一組都由使用者親自確認
- Recycle Bin instead of permanent deletion｜只移到 Windows 資源回收筒
- Clear paths, sizes and dates｜清楚顯示位置、大小與修改時間
- Local processing｜檔案全程在本機處理

## Features｜功能

- 找出檔名不同但內容完全相同的檔案
- 將三份以上的相同內容合併為同一組
- 顯示完整路徑、大小、時間及 SHA-256
- 圖片縮圖與常見檔案類型預覽
- 可直接開啟檔案或顯示所在資料夾
- 自行選擇要保留的版本
- 不確定時可選擇全部保留／忽略
- 產生 HTML、CSV 與處理紀錄
- 移除項目進入 Windows 資源回收筒

## Download｜下載

[⬇️ Download Windows v1.3.1｜下載 Windows v1.3.1](https://github.com/dw5000tw-33/safe-duplicate-file-cleaner/raw/refs/heads/main/downloads/Safe-Duplicate-File-Cleaner-Windows-v1.3.1.zip)

下載 ZIP 後請完整解壓縮，再雙擊 `start.cmd`。檔案的 SHA-256 可在 [SHA256SUMS.txt](SHA256SUMS.txt) 核對。

### System requirements｜系統需求

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- 不需要安裝 Python

## How it works｜判定方式

1. 依副檔名與檔案大小找出候選檔案。
2. 對候選檔案計算 SHA-256。
3. 只有大小與 SHA-256 都相同的檔案才會歸入同一組。
4. 使用者親自選擇保留版本。
5. 執行前再次核對內容並顯示確認視窗。
6. 其他版本移到 Windows 資源回收筒。

## Privacy and network behavior｜隱私與網路行為

- 掃描、雜湊計算、預覽及報告都在本機執行。
- 工具不會上傳檔案、檔名、路徑或掃描結果。
- 工具不包含使用情況追蹤或分析服務。
- 只有使用者主動點擊「加入官方 LINE」或「支持 33 Works」時，才會用預設瀏覽器開啟相對應網站。

## Important limitations｜重要限制

- 本工具尋找的是「內容完全相同」的檔案，不是肉眼看起來相似的照片。
- 照片若經過裁切、縮圖、重新壓縮或修改中繼資料，就不會被視為完全相同。
- 大量檔案或大型影片需要較長的掃描時間。
- 第一次使用建議先選擇有備份的小型測試資料夾。

## Security｜安全

原始碼公開於 `app/checker.ps1`。安全問題請參閱 [SECURITY.md](SECURITY.md)。

Windows 可能對從網路下載的批次檔或 PowerShell 指令碼顯示提醒。請只從本 Repository 的 Releases 下載，並在執行前確認來源。

## Version history｜版本紀錄

請參閱 [CHANGELOG.md](CHANGELOG.md)。

## License｜授權

本專案採用 [MIT License](LICENSE)。

## Feedback｜回饋

如果你遇到問題，請透過 GitHub Issues 提供：

- Windows 版本
- 操作步驟
- 錯誤畫面或 `掃描錯誤.txt`
- 測試資料的檔案數量與類型（請勿上傳私人檔案）

---

Built by [33 Works](https://github.com/dw5000tw-33)
