//+------------------------------------------------------------------+
//|                                                MarkovLabeler.mqh  |
//|     z スコア算出・状態ラベリング／詳細設計書 5.1, 5.2           |
//+------------------------------------------------------------------+
#ifndef __MARKOV_LABELER_MQH__
#define __MARKOV_LABELER_MQH__

#include "MarkovTypes.mqh"

//+------------------------------------------------------------------+
//| 状態ラベリング器                                                  |
//|  - close[] は時系列順（as_series=true, index0=形成中の足）を想定 |
//|  - label[p] は確定足 p の状態。データ不足の位置は -1。           |
//+------------------------------------------------------------------+
class CMarkovLabeler
  {
private:
   int               m_retWindow;     // 累積リターン窓長
   int               m_stdWindow;     // z スコア用標準偏差の窓長
   double            m_sigmaThr;      // 状態判定の σ 閾値

public:
                     CMarkovLabeler(void): m_retWindow(20), m_stdWindow(100), m_sigmaThr(0.5) {}

   void              Configure(int retWindow, int stdWindow, double sigmaThreshold)
     {
      m_retWindow = retWindow;
      m_stdWindow = stdWindow;
      m_sigmaThr  = sigmaThreshold;
     }

   //--- ラベリングに必要な最小バー数（位置 p までラベル化するなら p + これ）
   int               WarmupBars(void) const { return m_retWindow + m_stdWindow; }

   //--- close[] からラベル列を構築。label[] は close[] と同じ長さ・同じ添字。
   //--- 戻り値: ラベル化できた最古の添字 + 1（=有効ラベル数の上限位置）。失敗時 false。
   bool              BuildLabels(const double &close[], const int copied, int &label[], double &zout[])
     {
      if(copied <= 0)
         return false;

      ArrayResize(label, copied);
      ArrayResize(zout, copied);
      ArrayInitialize(label, -1);
      ArrayInitialize(zout, 0.0);

      //--- 累積対数リターン系列 r[p] = log(close[p] / close[p+ret])
      double r[];
      ArrayResize(r, copied);
      ArrayInitialize(r, 0.0);
      bool rvalid[];
      ArrayResize(rvalid, copied);
      ArrayInitialize(rvalid, false);

      for(int p = 0; p + m_retWindow < copied; p++)
        {
         double base = close[p + m_retWindow];
         if(base > 0.0 && close[p] > 0.0)
           {
            r[p]      = MathLog(close[p] / base);
            rvalid[p] = true;
           }
        }

      //--- 各 p について直近 stdWindow 本の r で標準化して状態を決める
      for(int p = 0; p + m_stdWindow - 1 + m_retWindow < copied; p++)
        {
         //--- r[p .. p+stdWindow-1] の標準偏差（母標準偏差）
         double sum = 0.0, sumsq = 0.0;
         int    n   = 0;
         for(int k = p; k < p + m_stdWindow; k++)
           {
            if(!rvalid[k])
               continue;
            sum   += r[k];
            sumsq += r[k] * r[k];
            n++;
           }
         if(n <= 1)
            continue;

         double mean  = sum / n;
         double var   = sumsq / n - mean * mean;
         double sigma = (var > 0.0) ? MathSqrt(var) : 0.0;
         double z     = (sigma > 0.0) ? (r[p] / sigma) : 0.0;

         zout[p] = z;
         if(z >= m_sigmaThr)
            label[p] = REGIME_BULL;
         else if(z <= -m_sigmaThr)
            label[p] = REGIME_BEAR;
         else
            label[p] = REGIME_SIDE;
        }

      return true;
     }
  };

#endif // __MARKOV_LABELER_MQH__
//+------------------------------------------------------------------+
