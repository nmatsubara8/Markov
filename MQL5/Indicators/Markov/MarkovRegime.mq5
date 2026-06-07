//+------------------------------------------------------------------+
//|                                                 MarkovRegime.mq5  |
//|     レジーム可視化インジケーター／詳細設計書 第7章             |
//|     P(Bull)/P(Bear)/diff をサブウィンドウに描画（発注はしない）  |
//+------------------------------------------------------------------+
#property copyright "Markov FX"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "P(Bull)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLimeGreen
#property indicator_label2  "P(Bear)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrTomato
#property indicator_label3  "Diff(Bull-Bear)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGold

#include <Markov/MarkovEngine.mqh>

//--- 入力（詳細設計書 第6章）
input int    InpReturnWindow   = 20;     // 累積リターン窓長
input int    InpStdWindow      = 100;    // z スコア標準偏差の窓長
input double InpSigmaThreshold = 0.5;    // σ 閾値
input int    InpTrainLookback  = 500;    // 学習本数
input bool   InpExpandingWindow= false;  // 全履歴学習
input int    InpForecastSteps  = 1;      // 予測ステップ
input double InpDiffThreshold  = 0.10;   // シグナル中立帯
input double InpLaplaceAlpha   = 1.0;    // ラプラス平滑化

double BufBull[];
double BufBear[];
double BufDiff[];

CMarkovEngine g_engine;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBull, INDICATOR_DATA);
   SetIndexBuffer(1, BufBear, INDICATOR_DATA);
   SetIndexBuffer(2, BufDiff, INDICATOR_DATA);
   ArraySetAsSeries(BufBull, true);
   ArraySetAsSeries(BufBear, true);
   ArraySetAsSeries(BufDiff, true);

   g_engine.Configure(InpReturnWindow, InpStdWindow, InpSigmaThreshold,
                      InpTrainLookback, InpExpandingWindow, InpForecastSteps,
                      InpDiffThreshold, InpLaplaceAlpha);

   IndicatorSetString(INDICATOR_SHORTNAME, "MarkovRegime");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Y2: 新規バーガード — 確定足が増えたときだけ末尾を再計算          |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   ArraySetAsSeries(BufBull, true);
   ArraySetAsSeries(BufBear, true);
   ArraySetAsSeries(BufDiff, true);

   //--- 初回はバッファを空に
   if(prev_calculated == 0)
     {
      ArrayInitialize(BufBull, EMPTY_VALUE);
      ArrayInitialize(BufBear, EMPTY_VALUE);
      ArrayInitialize(BufDiff, EMPTY_VALUE);
     }

   //--- 直近確定足（shift=1）に対してのみ予測を更新（過負荷回避）
   MarkovForecast fc;
   if(g_engine.BuildForecast(_Symbol, (ENUM_TIMEFRAMES)_Period, 1, fc) && fc.valid)
     {
      BufBull[1] = fc.prob[REGIME_BULL];
      BufBear[1] = fc.prob[REGIME_BEAR];
      BufDiff[1] = fc.diff;
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
