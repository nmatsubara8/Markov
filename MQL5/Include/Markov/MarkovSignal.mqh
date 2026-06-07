//+------------------------------------------------------------------+
//|                                                 MarkovSignal.mqh  |
//|     差分シグナル算出／詳細設計書 5.5                            |
//+------------------------------------------------------------------+
#ifndef __MARKOV_SIGNAL_MQH__
#define __MARKOV_SIGNAL_MQH__

#include "MarkovTypes.mqh"

//+------------------------------------------------------------------+
//| 予測確率分布から差分・売買方向を決める                            |
//+------------------------------------------------------------------+
class CMarkovSignal
  {
public:
   //--- prob[]（和=1）と中立帯 diffThreshold から差分と方向を算出
   static void       Evaluate(const double &prob[], const double diffThreshold,
                              double &diff, int &signalDir)
     {
      diff = prob[REGIME_BULL] - prob[REGIME_BEAR];
      if(diff >= diffThreshold)
         signalDir = +1;       // Long
      else if(diff <= -diffThreshold)
         signalDir = -1;       // Short
      else
         signalDir = 0;        // 中立帯
     }
  };

#endif // __MARKOV_SIGNAL_MQH__
//+------------------------------------------------------------------+
