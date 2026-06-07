//+------------------------------------------------------------------+
//|                                              MarkovBacktestEA.mq5 |
//|     バックテスト用 EA／詳細設計書 第8章・第14章                 |
//|     確定足ごとに予測→エントリー、結果を SQLite へ記録           |
//+------------------------------------------------------------------+
#property copyright "Markov FX"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Markov/MarkovEngine.mqh>
#include <Markov/MarkovSizing.mqh>
#include <Markov/MarkovDB.mqh>

//--- 分析・モデル（詳細設計書 第6章）
input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_D1;  // 分析タイムフレーム
input int             InpReturnWindow   = 20;         // 累積リターン窓長
input int             InpStdWindow      = 100;        // z スコア標準偏差の窓長
input double          InpSigmaThreshold = 0.5;        // σ 閾値
input int             InpTrainLookback  = 500;        // 学習本数
input bool            InpExpandingWindow= false;      // 全履歴学習
input int             InpForecastSteps  = 1;          // 予測ステップ（予測地平）
input double          InpDiffThreshold  = 0.10;       // シグナル中立帯
input double          InpLaplaceAlpha   = 1.0;        // ラプラス平滑化
//--- サイジング・SL/TP
input double          InpBaseRiskPct    = 0.5;        // 基準リスク（equity%）
input double          InpMaxRiskPct     = 2.0;        // 最大リスク（equity%）
input int             InpAtrPeriod      = 14;         // ATR 期間（動的 SL）
input double          InpAtrSLMult      = 1.5;        // SL = 係数 × ATR
input double          InpTpRMultiple    = 1.5;        // TP = SL × R
//--- エントリー挙動（D-5）
input ENUM_ENTRY_MODE InpEntryMode      = ENTRY_SINGLE;
input int             InpMaxPyramid     = 3;          // 積み増し/分割の上限
input int             InpExitBars       = 5;          // N 本経過手仕舞い
//--- 複合スコア重み（14.5）
input double          InpScoreWSharpe   = 1.0;
input double          InpScoreWPayoff   = 1.0;
input double          InpScoreWMaxDD    = 1.0;
//--- その他
input long            InpMagic          = 770001;

CTrade        g_trade;
CMarkovEngine g_engine;
int           g_atrHandle = INVALID_HANDLE;
datetime      g_lastBarTime = 0;

//--- Y1: 的中率の自前集計
int           g_predCount = 0;
int           g_predHits  = 0;
int           g_lastSignalDir = 0;
double        g_lastClose = 0.0;
bool          g_havePrev = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_engine.Configure(InpReturnWindow, InpStdWindow, InpSigmaThreshold,
                      InpTrainLookback, InpExpandingWindow, InpForecastSteps,
                      InpDiffThreshold, InpLaplaceAlpha);

   g_atrHandle = iATR(_Symbol, InpTimeframe, InpAtrPeriod);   // Y2: ハンドル取得
   if(g_atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(InpMagic);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
  }

//+------------------------------------------------------------------+
//| 新規バー確定検出                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
  }

double GetAtr(const int shift)
  {
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1)   // Y2: CopyBuffer で値取得
      return 0.0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| ポジション集計（自分の magic + シンボル）                        |
//+------------------------------------------------------------------+
int CountMyPositions(int &dir, double &totalVol)
  {
   int cnt = 0; dir = 0; totalVol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      cnt++;
      totalVol += PositionGetDouble(POSITION_VOLUME);
      dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
     }
   return cnt;
  }

void CloseMyPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      g_trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| 発注（成行 + ATR ベース SL/TP）                                  |
//+------------------------------------------------------------------+
bool OpenTrade(const int signalDir, const double diff, const double atr)
  {
   double slDist = 0.0;
   double lots = CMarkovSizing::CalcLots(_Symbol, diff, InpBaseRiskPct, InpMaxRiskPct,
                                         atr, InpAtrSLMult, slDist);
   if(lots <= 0.0 || slDist <= 0.0)
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpDist = slDist * InpTpRMultiple;

   if(signalDir > 0)
     {
      double sl = ask - slDist;
      double tp = ask + tpDist;
      return g_trade.Buy(lots, _Symbol, ask, sl, tp, "markov");
     }
   else if(signalDir < 0)
     {
      double sl = bid + slDist;
      double tp = bid - tpDist;
      return g_trade.Sell(lots, _Symbol, bid, sl, tp, "markov");
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 直近エントリーからの経過バー数                                    |
//+------------------------------------------------------------------+
int BarsSinceEntry()
  {
   datetime entry = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t > entry) entry = t;
     }
   if(entry == 0) return 0;
   int shift = iBarShift(_Symbol, InpTimeframe, entry, false);
   return shift;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar())
      return;

   //--- 直近確定足の予測
   MarkovForecast fc;
   if(!g_engine.BuildForecast(_Symbol, InpTimeframe, 1, fc) || !fc.valid)
      return;

   double atr = GetAtr(1);

   //--- Y1: 前回シグナルの的中判定（直近確定足の実現方向で評価）
   double closeNow = iClose(_Symbol, InpTimeframe, 1);
   if(g_havePrev && g_lastSignalDir != 0)
     {
      int realized = (closeNow > g_lastClose) ? +1 : ((closeNow < g_lastClose) ? -1 : 0);
      if(realized != 0)
        {
         g_predCount++;
         if(realized == g_lastSignalDir)
            g_predHits++;
        }
     }
   g_lastSignalDir = fc.signalDir;
   g_lastClose     = closeNow;
   g_havePrev      = true;

   //--- 既存ポジション状況
   int dir; double vol;
   int posCount = CountMyPositions(dir, vol);

   //--- 手仕舞い（D-4: 反対シグナル or N 本経過）。TP/SL は注文に付与済み。
   if(posCount > 0)
     {
      bool opposite = (fc.signalDir != 0 && fc.signalDir == -dir);
      bool timeExit = (BarsSinceEntry() >= InpExitBars);
      if(opposite || timeExit)
        {
         CloseMyPositions();
         posCount = 0; dir = 0; vol = 0.0;
        }
     }

   //--- エントリー（D-5: モード分岐）
   switch(InpEntryMode)
     {
      case ENTRY_SINGLE:
         if(posCount == 0 && fc.signalDir != 0)
            OpenTrade(fc.signalDir, fc.diff, atr);
         break;

      case ENTRY_REVERSAL:
         if(posCount > 0 && fc.signalDir != 0 && fc.signalDir == -dir)
           {
            CloseMyPositions();
            OpenTrade(fc.signalDir, fc.diff, atr);   // ドテン
           }
         else if(posCount == 0 && fc.signalDir != 0)
            OpenTrade(fc.signalDir, fc.diff, atr);
         break;

      case ENTRY_PYRAMID:
         if(posCount == 0 && fc.signalDir != 0)
            OpenTrade(fc.signalDir, fc.diff, atr);
         else if(posCount > 0 && fc.signalDir == dir && posCount < InpMaxPyramid)
            OpenTrade(fc.signalDir, fc.diff, atr);   // 同方向に積み増し
         break;

      case ENTRY_SCALE_BY_STRENGTH:
         //--- 強度に応じた分割エントリー（上限 InpMaxPyramid 回）
         if(fc.signalDir != 0 && (posCount == 0 || (fc.signalDir == dir && posCount < InpMaxPyramid)))
            OpenTrade(fc.signalDir, fc.diff, atr);
         break;
     }
  }

//+------------------------------------------------------------------+
//| 的中率（自前集計）                                                |
//+------------------------------------------------------------------+
double HitRate()
  {
   return (g_predCount > 0) ? (double)g_predHits / g_predCount : 0.0;
  }

//+------------------------------------------------------------------+
//| OnTester: 複合スコアを返しつつ、結果をフレームで送出（14.1）      |
//+------------------------------------------------------------------+
double OnTester()
  {
   double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);
   double payoff   = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double maxdd    = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double netprof  = TesterStatistics(STAT_PROFIT);
   double trades   = TesterStatistics(STAT_TRADES);
   double hit      = HitRate();

   //--- フレームでパラメータ＋指標をターミナルへ送る（OnTesterPass で DB 記録）
   double data[16];
   data[0]  = (double)InpReturnWindow;
   data[1]  = (double)InpStdWindow;
   data[2]  = InpSigmaThreshold;
   data[3]  = (double)InpTrainLookback;
   data[4]  = (double)InpForecastSteps;
   data[5]  = InpDiffThreshold;
   data[6]  = InpLaplaceAlpha;
   data[7]  = InpAtrSLMult;
   data[8]  = InpBaseRiskPct;
   data[9]  = InpMaxRiskPct;
   data[10] = hit;
   data[11] = payoff;
   data[12] = sharpe;
   data[13] = maxdd;
   data[14] = netprof;
   data[15] = trades;
   FrameAdd("markov", 0, 0.0, data);

   //--- 最適化のランク付け用（生の重み付け。最終選定は DB 側で正規化）
   double score = InpScoreWSharpe * sharpe + InpScoreWPayoff * payoff - InpScoreWMaxDD * maxdd;
   return score;
  }

//+------------------------------------------------------------------+
//| 最適化：各パスのフレームを受信して DB へ INSERT（ターミナル側）  |
//+------------------------------------------------------------------+
CMarkovDB g_db;

int OnTesterInit()
  {
   if(!g_db.Open())
      return INIT_FAILED;
   return INIT_SUCCEEDED;
  }

void OnTesterDeinit()
  {
   g_db.Close();
  }

void OnTesterPass()
  {
   ulong  pass; string name; long id; double value; double data[];
   while(FrameNext(pass, name, id, value, data))
     {
      if(name != "markov" || ArraySize(data) < 16)
         continue;

      string pj = StringFormat("{\"ret\":%d,\"std\":%d,\"sig\":%.4f,\"train\":%d,\"fc\":%d,\"diff\":%.4f,\"alpha\":%.4f,\"atr\":%.4f}",
                               (int)data[0], (int)data[1], data[2], (int)data[3], (int)data[4], data[5], data[6], data[7]);

      g_db.InsertTrial(_Symbol, pj,
                       (int)data[0], (int)data[1], data[2], (int)data[3], (int)data[4],
                       data[5], data[6], data[7], data[8], data[9],
                       data[10], data[11], data[12], data[13], data[14], (int)data[15]);
     }
  }
//+------------------------------------------------------------------+
