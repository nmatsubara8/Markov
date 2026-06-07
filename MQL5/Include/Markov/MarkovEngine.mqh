//+------------------------------------------------------------------+
//|                                                 MarkovEngine.mqh  |
//|     計算ロジックのファサード／詳細設計書 第4章                  |
//|     Labeler -> Matrix -> 累乗 -> Signal を束ねて予測を生成       |
//+------------------------------------------------------------------+
#ifndef __MARKOV_ENGINE_MQH__
#define __MARKOV_ENGINE_MQH__

#include "MarkovTypes.mqh"
#include "MarkovLabeler.mqh"
#include "MarkovMatrix.mqh"
#include "MarkovSignal.mqh"

//+------------------------------------------------------------------+
//| マルコフ予測エンジン                                              |
//+------------------------------------------------------------------+
class CMarkovEngine
  {
private:
   CMarkovLabeler    m_labeler;
   int               m_retWindow;
   int               m_stdWindow;
   double            m_sigmaThr;
   int               m_trainLookback;
   bool              m_expanding;
   int               m_forecastSteps;
   double            m_diffThreshold;   // R3: 追加
   double            m_laplaceAlpha;    // R3: 追加

public:
                     CMarkovEngine(void)
     {
      Configure(20, 100, 0.5, 500, false, 1, 0.10, 1.0);
     }

   //--- パラメータ注入（R3: diffThreshold, laplaceAlpha を含む）
   void              Configure(int retWindow, int stdWindow, double sigmaThreshold,
                               int trainLookback, bool expandingWindow, int forecastSteps,
                               double diffThreshold, double laplaceAlpha)
     {
      m_retWindow     = retWindow;
      m_stdWindow     = stdWindow;
      m_sigmaThr      = sigmaThreshold;
      m_trainLookback = trainLookback;
      m_expanding     = expandingWindow;
      m_forecastSteps = (forecastSteps < 1) ? 1 : forecastSteps;
      m_diffThreshold = diffThreshold;
      m_laplaceAlpha  = laplaceAlpha;
      m_labeler.Configure(retWindow, stdWindow, sigmaThreshold);
     }

   //--- 必要バー数の見積り
   int               RequiredBars(const int shift) const
     {
      int train = m_expanding ? (m_trainLookback * 4) : m_trainLookback; // expanding は多めに確保
      return shift + train + m_stdWindow + m_retWindow + 2;
     }

   //--- shift（1=直近確定足）時点で過去のみから予測を生成
   bool              BuildForecast(const string symbol, ENUM_TIMEFRAMES tf,
                                   const int shift, MarkovForecast &out)
     {
      out.valid = false;

      int need = RequiredBars(shift);
      double close[];
      ArraySetAsSeries(close, true);
      int copied = CopyClose(symbol, tf, 0, need, close);
      if(copied < m_stdWindow + m_retWindow + 2)
         return false;

      //--- ラベル列を構築
      int    label[];
      double zser[];
      if(!m_labeler.BuildLabels(close, copied, label, zser))
         return false;

      if(shift >= copied || label[shift] < 0)
         return false;       // 直近確定足がラベル化できない

      //--- 学習区間（expanding=true なら可能な限り全範囲）
      int train = m_trainLookback;
      if(m_expanding)
         train = copied - shift - 2;
      if(train < 1)
         return false;

      //--- 遷移行列 P を構築
      Mat3 P;
      if(!CMarkovMatrix::Build(label, shift, train, m_laplaceAlpha, P))
         return false;

      //--- P^forecastSteps
      Mat3 Pn;
      CMarkovMatrix::MatPow(P, m_forecastSteps, Pn);

      //--- 現状態 one-hot × Pn = 予測分布
      Vec3 cur;
      for(int k = 0; k < REGIME_COUNT; k++)
         cur.v[k] = 0.0;
      out.currentState = label[shift];
      cur.v[out.currentState] = 1.0;

      Vec3 pv;
      CMarkovMatrix::VecMat(cur, Pn, pv);

      for(int k = 0; k < REGIME_COUNT; k++)
        {
         out.prob[k]       = pv.v[k];
         out.stickiness[k] = P.m[k][k];   // 対角成分（持続性）
        }

      //--- 差分シグナル
      CMarkovSignal::Evaluate(out.prob, m_diffThreshold, out.diff, out.signalDir);

      out.valid = true;
      return true;
     }
  };

#endif // __MARKOV_ENGINE_MQH__
//+------------------------------------------------------------------+
