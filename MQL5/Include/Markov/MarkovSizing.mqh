//+------------------------------------------------------------------+
//|                                                 MarkovSizing.mqh  |
//|     残高%ベースのロット計算／詳細設計書 5.6（Y2/Y3/Y4 反映）   |
//+------------------------------------------------------------------+
#ifndef __MARKOV_SIZING_MQH__
#define __MARKOV_SIZING_MQH__

#include "MarkovTypes.mqh"

//+------------------------------------------------------------------+
//| 残高(equity)% × 差分強度 × ATR ベース SL からロットを算出        |
//+------------------------------------------------------------------+
class CMarkovSizing
  {
public:
   //--- ロット計算
   //--- diff       : P(Bull)-P(Bear)（強度は |diff| を 0..1 で使用）
   //--- baseRiskPct: 基準リスク（%、例 0.5）
   //--- maxRiskPct : 最大リスク（%、例 2.0）
   //--- atrValue   : 動的 SL 用 ATR 値（価格距離の素）
   //--- atrMult    : SL = atrMult * atrValue
   //--- 戻り値      : 正規化済みロット（不能なら 0）
   static double     CalcLots(const string symbol, const double diff,
                              const double baseRiskPct, const double maxRiskPct,
                              const double atrValue, const double atrMult,
                              double &slDistanceOut)
     {
      slDistanceOut = 0.0;
      if(atrValue <= 0.0)
         return 0.0;

      //--- リスク割合を差分強度でスケール（要件 #9）
      double strength = MathMin(MathAbs(diff), 1.0);
      double riskFrac = (baseRiskPct + (maxRiskPct - baseRiskPct) * strength) / 100.0;
      if(riskFrac <= 0.0)
         return 0.0;

      //--- Y4: 「投資可能残高%」は口座 equity 基準
      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * riskFrac;

      //--- 動的 SL（価格距離）と 1 ロットあたりの損切り金額
      double slDistance = atrMult * atrValue;
      slDistanceOut     = slDistance;

      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE); // Y3: 口座通貨建て・ペア依存
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return 0.0;

      double slValuePerLot = (slDistance / tickSize) * tickValue;
      if(slValuePerLot <= 0.0)
         return 0.0;

      double lots = riskAmount / slValuePerLot;
      return NormalizeLots(symbol, lots);
     }

   //--- ブローカー制約（Min/Step/Max）でロットを丸める
   static double     NormalizeLots(const string symbol, double lots)
     {
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0.0)
         lotStep = 0.01;

      lots = MathFloor(lots / lotStep) * lotStep;
      if(lots < minLot)
         lots = 0.0;          // 最小ロット未満は発注不可とする
      if(lots > maxLot)
         lots = maxLot;

      //--- lotStep の桁数で丸め誤差を除去
      int digits = (int)MathRound(-MathLog10(lotStep));
      if(digits < 0)
         digits = 0;
      return NormalizeDouble(lots, digits);
     }
  };

#endif // __MARKOV_SIZING_MQH__
//+------------------------------------------------------------------+
