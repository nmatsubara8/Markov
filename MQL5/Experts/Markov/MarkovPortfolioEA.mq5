//+------------------------------------------------------------------+
//|                                             MarkovPortfolioEA.mq5 |
//|     ポートフォリオ検証 EA／詳細設計書 14.3                      |
//|     DB からシンボル別ベスト param を読み、全シンボルを一括検証   |
//+------------------------------------------------------------------+
#property copyright "Markov FX"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Markov/MarkovEngine.mqh>
#include <Markov/MarkovSizing.mqh>
#include <Markov/MarkovDB.mqh>

input string          InpSymbolList   = "EURUSD,USDJPY,GBPUSD";  // 対象シンボル（カンマ区切り）
input ENUM_TIMEFRAMES InpTimeframe    = PERIOD_D1;               // タイムフレーム
input int             InpAtrPeriod    = 14;                      // ATR 期間
input double          InpTpRMultiple  = 1.5;                     // TP = SL × R
input int             InpExitBars     = 5;                       // N 本経過手仕舞い
input double          InpScoreWSharpe = 1.0;
input double          InpScoreWPayoff = 1.0;
input double          InpScoreWMaxDD  = 1.0;
input long            InpMagicBase    = 780000;

CTrade        g_trade;
CMarkovDB     g_db;

string            g_symbols[];
CMarkovEngine     g_engines[];
MarkovBestParams  g_params[];
int               g_atrHandles[];
datetime          g_lastBar[];
long              g_magics[];
int               g_count = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   int n = StringSplit(InpSymbolList, ',', g_symbols);
   if(n <= 0)
      return INIT_FAILED;

   if(!g_db.Open())
      return INIT_FAILED;

   ArrayResize(g_engines, n);
   ArrayResize(g_params, n);
   ArrayResize(g_atrHandles, n);
   ArrayResize(g_lastBar, n);
   ArrayResize(g_magics, n);
   g_count = 0;

   for(int i = 0; i < n; i++)
     {
      string sym = g_symbols[i];
      StringTrimLeft(sym); StringTrimRight(sym);
      g_symbols[i] = sym;
      if(sym == "")
         continue;

      if(!SymbolSelect(sym, true))
        {
         PrintFormat("symbol not available: %s", sym);
         continue;
        }

      MarkovBestParams bp;
      if(!g_db.SelectBest(sym, InpScoreWSharpe, InpScoreWPayoff, InpScoreWMaxDD, bp))
        {
         PrintFormat("no best params in DB for %s — skipped", sym);
         continue;
        }

      g_params[g_count] = bp;
      g_symbols[g_count] = sym;
      g_engines[g_count].Configure(bp.ret_window, bp.std_window, bp.sigma_thr,
                                   bp.train_lookback, false, bp.forecast_steps,
                                   bp.diff_threshold, bp.laplace_alpha);
      g_atrHandles[g_count] = iATR(sym, InpTimeframe, InpAtrPeriod);
      g_lastBar[g_count] = 0;
      g_magics[g_count] = InpMagicBase + g_count;
      g_count++;
     }

   g_db.Close();
   PrintFormat("Portfolio initialized with %d symbols", g_count);
   return (g_count > 0) ? INIT_SUCCEEDED : INIT_FAILED;
  }

void OnDeinit(const int reason)
  {
   for(int i = 0; i < g_count; i++)
      if(g_atrHandles[i] != INVALID_HANDLE)
         IndicatorRelease(g_atrHandles[i]);
  }

//+------------------------------------------------------------------+
double GetAtr(const int idx, const int shift)
  {
   double buf[];
   if(CopyBuffer(g_atrHandles[idx], 0, shift, 1, buf) != 1)
      return 0.0;
   return buf[0];
  }

int CountPositions(const string sym, const long magic, int &dir)
  {
   int cnt = 0; dir = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      cnt++;
      dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
     }
   return cnt;
  }

void ClosePositions(const string sym, const long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      g_trade.PositionClose(ticket);
     }
  }

int BarsSinceEntry(const string sym, const long magic)
  {
   datetime entry = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t > entry) entry = t;
     }
   if(entry == 0) return 0;
   return iBarShift(sym, InpTimeframe, entry, false);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   for(int i = 0; i < g_count; i++)
     {
      string sym = g_symbols[i];

      //--- 新規バー検出（シンボルごと）
      datetime t = iTime(sym, InpTimeframe, 0);
      if(t == g_lastBar[i])
         continue;
      g_lastBar[i] = t;

      MarkovForecast fc;
      if(!g_engines[i].BuildForecast(sym, InpTimeframe, 1, fc) || !fc.valid)
         continue;

      double atr = GetAtr(i, 1);
      if(atr <= 0.0)
         continue;

      long magic = g_magics[i];
      g_trade.SetExpertMagicNumber(magic);

      int dir;
      int posCount = CountPositions(sym, magic, dir);

      //--- 手仕舞い（反対シグナル or N 本経過）
      if(posCount > 0)
        {
         bool opposite = (fc.signalDir != 0 && fc.signalDir == -dir);
         bool timeExit = (BarsSinceEntry(sym, magic) >= InpExitBars);
         if(opposite || timeExit)
           {
            ClosePositions(sym, magic);
            posCount = 0;
           }
        }

      //--- エントリー（ポートフォリオは SINGLE 相当で簡潔に）
      if(posCount == 0 && fc.signalDir != 0)
        {
         double slDist = 0.0;
         double lots = CMarkovSizing::CalcLots(sym, fc.diff, g_params[i].base_risk_pct,
                                               g_params[i].max_risk_pct, atr, g_params[i].atr_mult, slDist);
         if(lots <= 0.0 || slDist <= 0.0)
            continue;

         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double tpDist = slDist * InpTpRMultiple;
         if(fc.signalDir > 0)
            g_trade.Buy(lots, sym, ask, ask - slDist, ask + tpDist, "markov-pf");
         else
            g_trade.Sell(lots, sym, bid, bid + slDist, bid - tpDist, "markov-pf");
        }
     }
  }
//+------------------------------------------------------------------+
