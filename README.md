# OpenListen

免費、MIT 開源的 iPhone 音訊收藏播放器。使用者自行安裝 App，並在自己的 Mac 或 Linux 電腦運行音訊處理工具。

**早期開發版本。** 本專案不是已完成真機驗收的正式發行版。請先閱讀下方的已知限制。

```text
貼上連結 → 自己的電腦處理音訊 → 下載到 iPhone → 離線及背景播放
```

沒有收費功能、廣告、分析追蹤或中央轉檔服務。軟件免費；電腦、網絡及可能的 Apple 開發者帳戶費用由使用者自行負責。

## 首版功能

- 加入 YouTube 影片、播放清單、`@handle` 或 `/channel/…` 頻道連結。
- 儲存連結，稍後批次處理；每次最多 10 條連結、合共 50 項。
- 電腦依次取得音訊，轉成 M4A，保留處理狀態；失敗可重試，項目可移除。
- 將完成的音訊下載到 iPhone；已下載內容不依賴電腦在線。
- 自建播放清單、排序、連播及保存播放進度。
- 原生背景音訊、鎖屏及耳機播放／暫停／上一首／下一首控制。
- 主畫面快速入口小工具：開啟收藏或加入連結。

使用者須自行確認有權下載及使用內容。開源授權只涵蓋本專案程式碼，不會授予 YouTube 或創作者內容的權利。本專案與 YouTube、Google、Apple 無隸屬關係。

## 安裝電腦工具

macOS 需要 [Homebrew](https://brew.sh/)。在終端機執行：

```sh
brew install uv ffmpeg node
git clone https://github.com/Toolsai/openlisten.git
cd openlisten
uv sync --project companion --frozen
uv run --project companion openlisten --host 0.0.0.0
```

電腦會顯示一組配對碼。手機與電腦需連上同一個可信任的 Wi-Fi。

電腦地址可在「系統設定 → 一般 → 共享」找到本地主機名稱，例如 `my-mac.local`。在 App 設定填入 `http://my-mac.local:8765` 及配對碼。亦可使用電腦的私人 IP，例如 `http://192.168.1.20:8765`。

- 工具預設只監聽本機；上述 `--host 0.0.0.0` 讓同一網絡的 iPhone 可連接。
- 每次重啟會產生新配對碼，需要在手機更新。進階使用者可透過環境變數 `OPENLISTEN_TOKEN` 提供至少 24 字元的固定秘密；不要把它提交到 Git。
- 預設音訊及資料庫位於 `~/.local/share/openlisten`，可用 `--data-dir` 改變位置。
- 電腦需要保持開啟才能處理新內容及傳送音檔；按 `Control-C` 停止工具。
- 電腦剩餘空間不足 1 GB 時會停止開始新的轉換，已有音檔不會自動刪除。

Linux 先安裝 Python 3.11 以上、uv、FFmpeg 及受 yt-dlp 支援的 JavaScript runtime（例如 Node），其餘命令相同。Windows 尚未支援。

## 安裝 iPhone App

需要 Mac、完整 Xcode 16 以上及 iOS 17 以上的 iPhone。單獨安裝 Command Line Tools 不足以編譯 App。

```sh
brew install xcodegen
xcodegen generate
open OpenListen.xcodeproj
```

1. 在 Xcode 登入自己的 Apple 帳戶，並連接 iPhone。
2. 在專案設定把 `BASE_BUNDLE_ID` 改為自己獨有的識別名稱，例如 `com.yourname.openlisten`。
3. 為 `OpenListen` 與 `OpenListenWidget` 兩個 target 選擇自己的 Signing Team。
4. 選擇 `OpenListen` scheme、你的 iPhone，按 Run。按 iPhone 提示啟用 Developer Mode。
5. App 首次連線時，允許「本地網絡」存取，再於設定輸入電腦地址及配對碼。

免費 Personal Team 的安裝授權會在 7 日後到期，需要重新編譯安裝；它不是永久免維護的安裝方式。[Apple 官方說明](https://developer.apple.com/help/account/basics/about-your-developer-account)

程式碼公開不代表有可直接點擊安裝的已簽署 IPA。App 不需要提交 App Store，但每位安裝者仍需符合 Apple 的安裝及簽署要求。

## 第一次使用

1. 到「設定」測試電腦連線。
2. 按「加入」，貼上你有權處理的來源，選「開始處理」。
3. 到「下載」等待電腦處理完成，按「下載全部已完成音訊」。
4. 在收藏按音訊播放；按 `⋯` 可加入自己的播放清單。
5. 關閉 Wi-Fi，確認已下載內容可播，再測試鎖屏及耳機控制。

儲存的連結會保留，不會在處理後自動刪除；可在加入畫面向左掃移除。重複匯入同一影片會沿用電腦上的現有項目。

## 已知限制

- 尚未完成真人 iPhone 驗收；背景播放、來電中斷、背景下載及小工具需要真機確認。
- 本機測試使用自行產生的短音訊與替代來源，**不代表已通過真實 YouTube 來源驗收**。
- 每批最多取 50 項；頻道讀取最近影片，沒有完整歷史分頁或自動訂閱排程。
- 不處理直播、超過 3 小時、需要登入或受地區／付費限制的內容。不提供登入憑證擷取或限制繞過。
- yt-dlp 可能因來源改動而失效。公開影片亦可能因來源拒絕連線而無法取得。
- 手機需要先下載完整音檔才能播放；首版不提供即時串流或自動跨裝置同步。
- 小工具是快速入口，尚未提供小工具內的即時播放狀態及控制。
- iPhone 第一次從電腦取得清單時需開啟 App；已開始的檔案下載交由 iOS 管理，時間由系統決定。
- 不會自動限制音檔總容量；可在 App 移除手機音檔或同時移除電腦項目。
- 電腦工具是單一使用者服務，沒有多使用者隔離、公開網站管理或公網部署配置。

## 更新來源工具

yt-dlp 的 JavaScript 支援由 `yt-dlp[default]` 依賴提供，電腦另需 Node 或受支援的 runtime。OpenListen 不會遠端下載並執行額外的 EJS 插件。

需要更新時，可在自己的 checkout 執行：

```sh
uv lock --project companion --upgrade-package yt-dlp --upgrade-package yt-dlp-ejs
uv sync --project companion --frozen
```

更新後請重新執行測試；新的來源行為仍需以實際連結確認。

## 開發及驗證

```sh
uv run --project companion pytest companion/tests -q
uv run --project companion ruff check companion/openlisten companion/tests
swift test --package-path Core
xcodegen generate
xcodebuild -project OpenListen.xcodeproj -scheme OpenListen -sdk iphonesimulator -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions 執行電腦工具測試、Swift 資料模型測試、iOS App／Widget 編譯及模擬器啟動截圖。這些檢查不能代替真機及真來源驗收。手動驗收表見 [docs/TESTING.md](docs/TESTING.md)。

| 位置 | 內容 |
| --- | --- |
| `iOS/OpenListen` | SwiftUI App、播放器、背景下載及鑰匙圈配對 |
| `iOS/Widget` | WidgetKit 快速入口 |
| `Core` | 可獨立測試的資料模型、清單合併及地址驗證 |
| `companion` | Python／FastAPI、SQLite、yt-dlp 及 FFmpeg 處理工具 |
| `project.yml` | XcodeGen 專案定義 |

## 授權與私隱

本專案自有程式碼採用 [MIT License](LICENSE)，免費使用。MIT 容許第三方修改、重新發布及商用；本專案不加入收費功能。

第三方軟件有各自授權，見 [THIRD_PARTY.md](THIRD_PARTY.md)。[PRIVACY.md](PRIVACY.md) 說明資料保存及網絡連線。歡迎透過 issue 回報可重現的問題；請勿提交配對碼、私人連結或音檔。
