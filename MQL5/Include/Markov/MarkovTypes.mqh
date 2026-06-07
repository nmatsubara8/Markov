//+------------------------------------------------------------------+
//|                                                  MarkovTypes.mqh  |
//|     共通型定義（enum・構造体・定数）／詳細設計書 第3章           |
//+------------------------------------------------------------------+
#ifndef __MARKOV_TYPES_MQH__
#define __MARKOV_TYPES_MQH__

//--- 市場状態（3 状態：要件 #3）。遷移行列の添字としても使う。
enum ENUM_REGIME
  {
   REGIME_BEAR = 0,
   REGIME_SIDE = 1,
   REGIME_BULL = 2
  };
#define REGIME_COUNT 3

//--- エントリーモード（D-5：input で選択可能）
enum ENUM_ENTRY_MODE
  {
   ENTRY_SINGLE,            // 1ポジションのみ。保有中は新規エントリーしない
   ENTRY_REVERSAL,          // 反対シグナルで決済して即ドテン（反転）
   ENTRY_PYRAMID,           // 同方向シグナル継続で上限まで積み増し
   ENTRY_SCALE_BY_STRENGTH  // 差分強度に応じて分割エントリー
  };

//--- 3x3 行列・3 次ベクトルの固定サイズラッパ（多次元配列の受け渡しを単純化）
struct Mat3
  {
   double            m[REGIME_COUNT][REGIME_COUNT];
  };
struct Vec3
  {
   double            v[REGIME_COUNT];
  };

//--- 1 本ぶんの予測結果
struct MarkovForecast
  {
   double            prob[REGIME_COUNT];       // 各状態の予測確率（和=1）
   double            diff;                     // P(Bull) - P(Bear)
   int               signalDir;                // +1=Long, -1=Short, 0=中立
   double            stickiness[REGIME_COUNT]; // 遷移行列の対角成分（持続性）
   int               currentState;            // 直近確定足の状態
   bool              valid;                    // 予測が生成できたか
  };

#endif // __MARKOV_TYPES_MQH__
//+------------------------------------------------------------------+
