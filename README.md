# Markov FX — マルコフ連鎖 FX レジーム予測システム

マルコフ連鎖による市場レジーム（Bull / Sideways / Bear）予測を用いた
FX トレードシステム。MT5 / MQL5 で動作する。

## 概要

日足の累積リターンを z スコアで正規化し 3 状態（Bull / Sideways / Bear）へ
ラベリング → 遷移行列を構築 → 行列累乗で N 日先の状態確率を予測 →
Bull−Bear 差分をシグナルとして売買判断を行う。

主な特徴:

- 通貨ペアごとに独立した遷移行列を学習
- z スコア型閾値により全ペアに公平適用可能
- ストラテジーテスターでパラメータ最適化可能（17 個の外部パラメータ）
- 残高 % ベースのロット計算 + ATR 動的 SL
- 4 つのエントリーモード（SINGLE / REVERSAL / PYRAMID / SCALE_BY_STRENGTH）
- SQLite による試行データ管理とシンボル別ベスト選定
- Python ランナーによる複数シンボル連続最適化

## ディレクトリ構成

```
Markov/
├─ docs/
│   ├─ 概要要件定義書.md        # 要件定義
│   └─ 詳細設計書.md            # 詳細設計
├─ MQL5/
│   ├─ Include/Markov/          # 計算ロジック（共通 .mqh）
│   │   ├─ MarkovTypes.mqh      # enum・構造体
│   │   ├─ MarkovLabeler.mqh    # z スコア・状態ラベリング
│   │   ├─ MarkovMatrix.mqh     # 遷移行列構築・累乗
│   │   ├─ MarkovSignal.mqh     # 差分シグナル
│   │   ├─ MarkovSizing.mqh     # ロット計算
│   │   ├─ MarkovDB.mqh         # SQLite DB 管理
│   │   └─ MarkovEngine.mqh     # ファサード
│   ├─ Indicators/Markov/
│   │   └─ MarkovRegime.mq5     # レジーム可視化インジケーター
│   ├─ Experts/Markov/
│   │   ├─ MarkovBacktestEA.mq5 # バックテスト・最適化用 EA
│   │   └─ MarkovPortfolioEA.mq5# 全シンボル一括検証 EA
│   └─ Scripts/Markov/
│       └─ MarkovSelfTest.mq5   # 単体検証スクリプト
├─ tools/orchestrator/
│   ├─ run_optimization.py      # シンボル連続最適化ランナー
│   └─ config.example.json      # ランナー設定例
└─ README.md                    # 本ファイル
```

## 前提条件

| 項目 | 要件 |
|------|------|
| MetaTrader 5 | Build 3000 以降推奨 |
| MetaEditor | MT5 同梱版 |
| Python | 3.8 以降（連続最適化ランナーを使う場合のみ） |
| OS | Windows（MT5 の動作環境） |
| ブローカー | MT5 対応ブローカー口座（デモ口座可） |

## セットアップ

### 1. ファイル配置

MT5 のデータフォルダ（ターミナルで `ファイル > データフォルダを開く`）の
`MQL5/` 配下へ、本リポジトリの `MQL5/` の内容をコピーする。

```
<MT5データフォルダ>/MQL5/
├─ Include/Markov/     ← MQL5/Include/Markov/ をコピー
├─ Indicators/Markov/  ← MQL5/Indicators/Markov/ をコピー
├─ Experts/Markov/     ← MQL5/Experts/Markov/ をコピー
└─ Scripts/Markov/     ← MQL5/Scripts/Markov/ をコピー
```

### 2. コンパイル

MetaEditor で以下のファイルを順にコンパイルする（`F7` または `コンパイル` ボタン）。
共通 `.mqh` は `#include` で自動参照されるため個別コンパイル不要。

1. `Scripts/Markov/MarkovSelfTest.mq5`
2. `Indicators/Markov/MarkovRegime.mq5`
3. `Experts/Markov/MarkovBacktestEA.mq5`
4. `Experts/Markov/MarkovPortfolioEA.mq5`

全ファイルが **0 errors** でコンパイルされることを確認する。

### 3. Python 環境（連続最適化ランナーを使う場合）

```bash
# Python 3.8+ が必要。外部ライブラリは不要（標準ライブラリのみ使用）。
python --version
```

## 検証手順

### ステップ 0: 単体検証（MarkovSelfTest）

共通ライブラリの計算ロジックが正しく動作するかを確認する。

1. MT5 でチャートを開く（任意のシンボル・タイムフレーム）
2. ナビゲーターから `Scripts > Markov > MarkovSelfTest` をチャートにドロップ
3. エキスパートタブのログを確認

**期待結果:**

```
[PASS] Build returns true
[PASS] row 0 sums to 1
[PASS] row 1 sums to 1
[PASS] row 2 sums to 1
[PASS] P^1 equals P
[PASS] P^2 row 0 sums to 1
[PASS] P^2 row 1 sums to 1
[PASS] P^2 row 2 sums to 1
[PASS] one-hot(Bull) * P == row(Bull)
[PASS] signal: diff=0.45 -> Long
[PASS] signal: diff=-0.30 -> Short
[PASS] signal: small diff -> neutral
[PASS] laplace row 0 sums to 1
[PASS] laplace row 1 sums to 1
[PASS] laplace row 2 sums to 1
=== SelfTest finished: ALL PASS (failures=0) ===
```

全テストが `[PASS]` で `ALL PASS` と表示されれば OK。

### ステップ 1: インジケーター可視化（MarkovRegime）

1. 任意の通貨ペアの日足チャートを開く
2. ナビゲーターから `Indicators > Markov > MarkovRegime` を適用
3. パラメータはデフォルトのまま OK を押す

**確認ポイント:**

- サブウィンドウに P(Bull)（青）、P(Bear)（赤）、Diff（緑）の 3 ラインが表示される
- Diff が ±閾値を超える箇所がシグナル発火ポイント
- 値が 0〜1 の範囲に収まっている

## 実行手順

### 方法 A: 単一シンボル最適化（手動）

1 つの通貨ペアのパラメータを手動で最適化する場合。

1. `Ctrl+R` でストラテジーテスターを開く
2. 以下を設定:

| 項目 | 設定値 |
|------|--------|
| EA | `Markov\MarkovBacktestEA` |
| シンボル | 任意の通貨ペア（例: EURUSD） |
| 期間 | D1（日足） |
| モデル | 始値のみ or 1分足OHLC |
| 期間指定 | 2015.01.01 〜 2024.12.31（推奨） |
| 最適化 | 遺伝的アルゴリズム（高速） |
| 最適化基準 | Custom（OnTester が返す複合スコア） |

3. パラメータタブで最適化範囲を設定（推奨範囲は `config.example.json` を参照）
4. `スタート` を押して最適化を実行
5. 完了後、最適化結果タブでベストパラメータを確認
6. 結果は SQLite DB（`Common\Files\Markov\markov_trials.sqlite`）にも自動記録される

### 方法 B: 複数シンボル連続最適化（Python ランナー）

全シンボルを自動で連続最適化する場合。

#### 1. 設定ファイルの準備

```bash
cd tools/orchestrator
cp config.example.json config.json
```

`config.json` を環境に合わせて編集:

```jsonc
{
  "terminal_path": "C:\\Program Files\\MetaTrader 5\\terminal64.exe",
  "expert": "Markov\\MarkovBacktestEA.ex5",
  "symbols": ["EURUSD", "USDJPY", "GBPUSD", "AUDUSD"],
  "period": "D1",
  "from_date": "2015.01.01",
  "to_date": "2024.12.31",
  // ... 他のパラメータは config.example.json を参照
}
```

- `terminal_path`: MT5 ターミナルの実行ファイルパス
- `symbols`: 最適化対象の通貨ペアリスト
- `inputs` 内の `start` / `step` / `stop`: 各パラメータの最適化範囲

#### 2. 実行

```bash
python run_optimization.py --config config.json
```

各シンボルについて MT5 ターミナルが起動 → 最適化実行 → 自動終了を繰り返す。
全シンボルのパスの結果は EA の `OnTesterPass` から SQLite DB へ自動記録される。

#### 3. 生成 .ini の保持（デバッグ用）

```bash
python run_optimization.py --config config.json --keep-ini
```

`--keep-ini` を指定すると、生成された .ini ファイルが `ini_out/` に残る。

### 方法 C: ポートフォリオ一括検証（MarkovPortfolioEA）

DB に記録されたシンボル別ベストパラメータで全シンボルを一括検証する。

1. 方法 A または B で最適化を完了させる（DB にデータが必要）
2. ストラテジーテスターで以下を設定:

| 項目 | 設定値 |
|------|--------|
| EA | `Markov\MarkovPortfolioEA` |
| シンボル | 任意（EA 内部でシンボルを切り替える） |
| 期間 | D1 |
| 最適化 | なし（単一パス） |

3. `InpSymbolList` に対象シンボルをカンマ区切りで指定（例: `EURUSD,USDJPY,GBPUSD`）
4. EA が DB からシンボル別ベストパラメータを自動読み込みし、全シンボルを 1 パスで検証

## 推奨ワークフロー

```
① セットアップ（ファイル配置 → コンパイル）
    ↓
② 単体検証（MarkovSelfTest → ALL PASS 確認）
    ↓
③ 可視化確認（MarkovRegime インジケーター → 挙動確認）
    ↓
④ シンボル別最適化（方法 A: 手動 or 方法 B: Python ランナー）
    ↓
⑤ ポートフォリオ一括検証（方法 C: MarkovPortfolioEA）
    ↓
⑥ 結果分析（SQLite DB のデータを確認・評価）
```

## 主な外部パラメータ

| パラメータ | 既定値 | 説明 |
|-----------|--------|------|
| InpTimeframe | PERIOD_D1 | 分析タイムフレーム |
| InpReturnWindow | 20 | 累積リターン算出窓（本数） |
| InpStdWindow | 100 | ローリング標準偏差の窓長 |
| InpSigmaThreshold | 0.5 | z スコアによる状態判定閾値（σ） |
| InpTrainLookback | 500 | 遷移行列の学習区間（本数） |
| InpForecastSteps | 1 | 予測ステップ数（行列累乗の次数） |
| InpDiffThreshold | 0.10 | シグナル発火の差分閾値 |
| InpLaplaceAlpha | 1.0 | ラプラス平滑化の α |
| InpBaseRiskPct | 0.5 | 基本リスク %（残高比） |
| InpMaxRiskPct | 2.0 | 最大リスク % |
| InpAtrPeriod | 14 | ATR 算出期間 |
| InpAtrSLMult | 2.0 | ATR × 倍率 = SL 幅 |
| InpEntryMode | SINGLE | エントリーモード |

## SQLite DB

最適化結果は以下に保存される:

```
<MT5 共通データフォルダ>\Files\Markov\markov_trials.sqlite
```

テーブル構成:

- `runs` — 最適化実行の記録（シンボル・期間・開始日時）
- `trials` — 各パスの結果（パラメータ・利益・DD・的中率・複合スコア）

ベスト選定は `trials` テーブルのシンボル別 min-max 正規化複合スコアで行われる。

## 設計ドキュメント

- [概要要件定義書](docs/概要要件定義書.md) — プロジェクトの目的・スコープ・機能要件
- [詳細設計書](docs/詳細設計書.md) — モジュール設計・アルゴリズム・テスト計画
- [MQL5 README](MQL5/README.md) — MQL5 固有の実装詳細

## 注意事項

- MT5 のストラテジーテスターは 1 インスタンスにつき 1 シンボルのみ最適化可能。
  複数シンボルの連続最適化には Python ランナー（方法 B）を使用する。
- テストエージェントはネットワーク遮断・並列実行されるため、DB 書込みは
  ターミナル側 `OnTesterPass`（フレーム機能）から一括で行われる。
- 日足のクローズ基準は NY クローズ（17:00 ET）を暫定採用。
- 本システムはバックテスト・検証用であり、実口座での自動売買は現時点でスコープ外。

## ライセンス

Private
