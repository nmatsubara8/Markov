//+------------------------------------------------------------------+
//|                                                     MarkovDB.mqh  |
//|     SQLite アクセス層／詳細設計書 第14章・14.3a                 |
//|     試行データ（シンボル・パラメータ・結果）の記録と照会         |
//+------------------------------------------------------------------+
#ifndef __MARKOV_DB_MQH__
#define __MARKOV_DB_MQH__

//+------------------------------------------------------------------+
//| シンボル別ベスト param（③ が読み込む結果）                       |
//+------------------------------------------------------------------+
struct MarkovBestParams
  {
   string            symbol;
   int               ret_window;
   int               std_window;
   double            sigma_thr;
   int               train_lookback;
   int               forecast_steps;
   double            diff_threshold;
   double            laplace_alpha;
   double            atr_mult;
   double            base_risk_pct;
   double            max_risk_pct;
   double            score;
   bool              valid;
  };

//+------------------------------------------------------------------+
//| SQLite ラッパ                                                     |
//+------------------------------------------------------------------+
class CMarkovDB
  {
private:
   int               m_db;
   string            m_path;

public:
                     CMarkovDB(void): m_db(INVALID_HANDLE), m_path("") {}
                    ~CMarkovDB(void) { Close(); }

   //--- DB を開く（COMMON フラグで複数ターミナル間共有）。無ければ作成。
   bool              Open(const string path = "Markov\\markov_trials.sqlite")
     {
      m_path = path;
      m_db = DatabaseOpen(path, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_COMMON);
      if(m_db == INVALID_HANDLE)
        {
         PrintFormat("DatabaseOpen failed: %s err=%d", path, GetLastError());
         return false;
        }
      return CreateSchema();
     }

   void              Close(void)
     {
      if(m_db != INVALID_HANDLE)
        {
         DatabaseClose(m_db);
         m_db = INVALID_HANDLE;
        }
     }

   //--- スキーマ作成（14.3a）
   bool              CreateSchema(void)
     {
      string sql_runs =
         "CREATE TABLE IF NOT EXISTS runs("
         "run_id INTEGER PRIMARY KEY AUTOINCREMENT,"
         "symbol TEXT, tf TEXT, from_date TEXT, to_date TEXT, created_at TEXT);";

      string sql_trials =
         "CREATE TABLE IF NOT EXISTS trials("
         "id INTEGER PRIMARY KEY AUTOINCREMENT,"
         "run_id INTEGER,"
         "symbol TEXT,"
         "params_json TEXT,"
         "ret_window INTEGER, std_window INTEGER, sigma_thr REAL,"
         "train_lookback INTEGER, forecast_steps INTEGER,"
         "diff_threshold REAL, laplace_alpha REAL, atr_mult REAL,"
         "base_risk_pct REAL, max_risk_pct REAL,"
         "hit_rate REAL, exp_payoff REAL, sharpe REAL, max_dd_pct REAL,"
         "net_profit REAL, trades INTEGER, created_at TEXT);";

      if(!DatabaseExecute(m_db, sql_runs))   { PrintFormat("create runs failed err=%d", GetLastError());   return false; }
      if(!DatabaseExecute(m_db, sql_trials)) { PrintFormat("create trials failed err=%d", GetLastError()); return false; }
      return true;
     }

   //--- 試行 1 件を INSERT（ターミナル側 OnTesterPass から呼ぶ）
   bool              InsertTrial(const string symbol, const string params_json,
                                 const int ret_window, const int std_window, const double sigma_thr,
                                 const int train_lookback, const int forecast_steps,
                                 const double diff_threshold, const double laplace_alpha, const double atr_mult,
                                 const double base_risk_pct, const double max_risk_pct,
                                 const double hit_rate, const double exp_payoff, const double sharpe,
                                 const double max_dd_pct, const double net_profit, const int trades)
     {
      string sql = StringFormat(
         "INSERT INTO trials(symbol,params_json,ret_window,std_window,sigma_thr,"
         "train_lookback,forecast_steps,diff_threshold,laplace_alpha,atr_mult,"
         "base_risk_pct,max_risk_pct,hit_rate,exp_payoff,sharpe,max_dd_pct,net_profit,trades,created_at)"
         " VALUES('%s','%s',%d,%d,%.6f,%d,%d,%.6f,%.6f,%.6f,%.4f,%.4f,%.6f,%.6f,%.6f,%.6f,%.2f,%d,'%s');",
         symbol, params_json, ret_window, std_window, sigma_thr,
         train_lookback, forecast_steps, diff_threshold, laplace_alpha, atr_mult,
         base_risk_pct, max_risk_pct, hit_rate, exp_payoff, sharpe, max_dd_pct, net_profit, trades,
         TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));

      if(!DatabaseExecute(m_db, sql))
        {
         PrintFormat("InsertTrial failed err=%d", GetLastError());
         return false;
        }
      return true;
     }

   //--- シンボル別ベスト param を取得（複合スコアを per-symbol min-max 正規化で算出）
   //--- 重み: wS=Sharpe, wP=Payoff, wD=MaxDD ペナルティ
   bool              SelectBest(const string symbol, const double wS, const double wP, const double wD,
                                MarkovBestParams &out)
     {
      out.valid = false;
      //--- per-symbol の min/max を使って正規化スコアを計算し、最大を 1 件取得
      string sql = StringFormat(
         "WITH s AS (SELECT symbol,"
         " MIN(sharpe) mnS, MAX(sharpe) mxS,"
         " MIN(exp_payoff) mnP, MAX(exp_payoff) mxP,"
         " MIN(max_dd_pct) mnD, MAX(max_dd_pct) mxD"
         " FROM trials WHERE symbol='%s' GROUP BY symbol)"
         " SELECT t.*, ("
         "  %f*CASE WHEN s.mxS>s.mnS THEN (t.sharpe-s.mnS)/(s.mxS-s.mnS) ELSE 0 END"
         " +%f*CASE WHEN s.mxP>s.mnP THEN (t.exp_payoff-s.mnP)/(s.mxP-s.mnP) ELSE 0 END"
         " -%f*CASE WHEN s.mxD>s.mnD THEN (t.max_dd_pct-s.mnD)/(s.mxD-s.mnD) ELSE 0 END"
         " ) AS score"
         " FROM trials t JOIN s ON t.symbol=s.symbol"
         " WHERE t.symbol='%s' ORDER BY score DESC LIMIT 1;",
         symbol, wS, wP, wD, symbol);

      int req = DatabasePrepare(m_db, sql);
      if(req == INVALID_HANDLE)
        {
         PrintFormat("SelectBest prepare failed err=%d", GetLastError());
         return false;
        }

      bool ok = false;
      if(DatabaseRead(req))
        {
         long lv; double dv; string sv;
         out.symbol = symbol;
         DatabaseColumnInteger(req, ColIndex(req, "ret_window"), lv);     out.ret_window     = (int)lv;
         DatabaseColumnInteger(req, ColIndex(req, "std_window"), lv);     out.std_window     = (int)lv;
         DatabaseColumnDouble (req, ColIndex(req, "sigma_thr"), dv);      out.sigma_thr      = dv;
         DatabaseColumnInteger(req, ColIndex(req, "train_lookback"), lv); out.train_lookback = (int)lv;
         DatabaseColumnInteger(req, ColIndex(req, "forecast_steps"), lv); out.forecast_steps = (int)lv;
         DatabaseColumnDouble (req, ColIndex(req, "diff_threshold"), dv); out.diff_threshold = dv;
         DatabaseColumnDouble (req, ColIndex(req, "laplace_alpha"), dv);  out.laplace_alpha  = dv;
         DatabaseColumnDouble (req, ColIndex(req, "atr_mult"), dv);       out.atr_mult       = dv;
         DatabaseColumnDouble (req, ColIndex(req, "base_risk_pct"), dv);  out.base_risk_pct  = dv;
         DatabaseColumnDouble (req, ColIndex(req, "max_risk_pct"), dv);   out.max_risk_pct   = dv;
         DatabaseColumnDouble (req, ColIndex(req, "score"), dv);          out.score          = dv;
         out.valid = true;
         ok = true;
        }
      DatabaseFinalize(req);
      return ok;
     }

private:
   //--- 列名から列インデックスを引く（プリペアドステートメント単位）
   int               ColIndex(const int req, const string name)
     {
      int cols = DatabaseColumnsCount(req);
      for(int c = 0; c < cols; c++)
        {
         string cn;
         if(DatabaseColumnName(req, c, cn) && cn == name)
            return c;
        }
      return -1;
     }
  };

#endif // __MARKOV_DB_MQH__
//+------------------------------------------------------------------+
