# Markov FX (MT5 / MQL5) — 実装

マルコフ連鎖による FX レジーム予測システムの MQL5 実装。
設計は [`../docs/概要要件定義書.md`](../docs/概要要件定義書.md) と
[`../docs/詳細設計書.md`](../docs/詳細設計書.md) を参照。

## ディレクトリ構成

```
MQL5/
├─ Include/Markov/        # 計算ロジック（共通 .mqh）— インジケーターと EA で共有
│   ├─ MarkovTypes.mqh    # enum・構造体（ENUM_REGIME, MarkovForecast, Mat3/Vec3）
│   ├─ MarkovLabeler.mqh  # z スコア算出・状態ラベリング（5.1, 5.2）
│   ├─ MarkovMatrix.mqh   # 遷移行列の構築・正規化・累乗（5.3, 5.4）
│   ├─ MarkovSignal.mqh   # 差分シグナル（5.5）
│   ├─ MarkovSizing.mqh   # 残高%ベースのロット計算（5.6）
│   ├─ MarkovDB.mqh       # SQLite 試行データ DB（第14章）
│   └─ MarkovEngine.mqh   # 上記を束ねるファサード（第4章）
├─ Indicators/Markov/
│   └─ MarkovRegime.mq5   # レジーム可視化（発注なし）
├─ Experts/Markov/
│   ├─ MarkovBacktestEA.mq5   # バックテスト用 EA（最適化 + DB 記録）
│   └─ MarkovPortfolioEA.mq5  # 全シンボル一括検証（DB からベスト param 読込）
└─ Scripts/Markov/
    └─ MarkovSelfTest.mq5     # 共通ライブラリの単体検証
```

`../tools/orchestrator/` にシンボル連続最適化ランナー（層②, Python）。

## セットアップ

1. このリポジトリの `MQL5/` 配下を、MT5 のデータフォルダ（`File > Open Data Folder` →
   `MQL5/`）へコピー（または該当ディレクトリへ配置）。
2. MetaEditor で以下をコンパイル：
   - `Scripts/Markov/MarkovSelfTest.mq5`
   - `Indicators/Markov/MarkovRegime.mq5`
   - `Experts/Markov/MarkovBacktestEA.mq5`
   - `Experts/Markov/MarkovPortfolioEA.mq5`
   - 共通 `.mqh` は `#include <Markov/...>` で参照される（個別コンパイル不要）。

## 使い方（ワークフロー）

### 0. 単体検証
`MarkovSelfTest` をチャートにドロップ → エキスパートログで `ALL PASS` を確認。

### 1. 可視化（任意）
`MarkovRegime` を通貨ペアのチャートに適用 → P(Bull)/P(Bear)/Diff を確認。

### 2. シンボル別最適化（層① + ②）
- 層②ランナーで全シンボルを連続最適化：
  ```
  cd tools/orchestrator
  python run_optimization.py --config config.example.json
  ```
  各最適化パスの「パラメータ＋成績」は EA の `OnTesterPass` から
  SQLite DB（`Common\Files\Markov\markov_trials.sqlite`）へ自動記録される。
- 手動で 1 シンボルだけ回す場合は、ストラテジーテスターで `MarkovBacktestEA` を
  最適化実行（最適化基準＝Custom）。

### 3. ポートフォリオ一括検証（層③）
`MarkovPortfolioEA` をストラテジーテスター（または実チャート）で実行。
`InpSymbolList` に対象シンボルを指定すると、DB からシンボル別ベスト param を
読み込み、全シンボルを 1 パスで検証する（シンボル切替不要）。

## 設計上の要点
- **データ漏洩防止**: すべての予測は `shift=1`（直近確定足）起点で過去のみ参照。
  バー単位処理がそのままウォークフォワードになる。
- **計算ロジックは `.mqh` に集約**し、インジケーター/EA は薄い層（要件 #12）。
- **試行データは SQLite に一元管理**し、シンボル別ベスト選定は SQL（per-symbol
  min-max 正規化スコア）で行う。

## 注意（実装メモ）
- MQL5 のテクニカル関数（`iATR` 等）はハンドルを返すため `CopyBuffer` で値取得。
- ストラテジーテストのエージェントはネットワーク遮断・並列実行のため、DB 書込みは
  ターミナル側 `OnTesterPass` から一括で行う（フレーム機能）。
- `SYMBOL_TRADE_TICK_VALUE` は口座通貨建て・ペア依存。
- 「投資可能残高%」は口座 equity 基準。
