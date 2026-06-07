//+------------------------------------------------------------------+
//|                                               MarkovSelfTest.mq5  |
//|     共通ライブラリの単体検証／詳細設計書 第13章                 |
//|     既知データで行列・累乗・差分の不変条件を assert する         |
//+------------------------------------------------------------------+
#property copyright "Markov FX"
#property version   "1.00"
#property script_show_inputs

#include <Markov/MarkovMatrix.mqh>
#include <Markov/MarkovSignal.mqh>

int g_fail = 0;

void Check(const bool cond, const string msg)
  {
   if(cond)
      PrintFormat("[PASS] %s", msg);
   else
     {
      PrintFormat("[FAIL] %s", msg);
      g_fail++;
     }
  }

bool AlmostEqual(const double a, const double b, const double eps = 1e-9)
  {
   return MathAbs(a - b) < eps;
  }

void OnStart()
  {
   g_fail = 0;

   //--- テスト用ラベル列（as_series: index 小=新しい）
   //--- 並び（新→古）: B,B,S,U,U,S,B,U,S,B  (U=Bull,S=Side,B=Bear)
   int label[];
   ArrayResize(label, 10);
   label[0]=REGIME_BEAR; label[1]=REGIME_BEAR; label[2]=REGIME_SIDE;
   label[3]=REGIME_BULL; label[4]=REGIME_BULL; label[5]=REGIME_SIDE;
   label[6]=REGIME_BEAR; label[7]=REGIME_BULL; label[8]=REGIME_SIDE;
   label[9]=REGIME_BEAR;

   //--- 行列構築（平滑化なし）
   Mat3 P;
   bool ok = CMarkovMatrix::Build(label, 1, 8, 0.0, P);
   Check(ok, "Build returns true");

   //--- 各行の和=1（平滑化なしでも、観測のある行は 1 に正規化）
   for(int i = 0; i < REGIME_COUNT; i++)
     {
      double s = P.m[i][0] + P.m[i][1] + P.m[i][2];
      Check(AlmostEqual(s, 1.0, 1e-9), StringFormat("row %d sums to 1 (=%.6f)", i, s));
     }

   //--- P^1 == P
   Mat3 P1;
   CMarkovMatrix::MatPow(P, 1, P1);
   bool same = true;
   for(int i = 0; i < REGIME_COUNT; i++)
      for(int j = 0; j < REGIME_COUNT; j++)
         if(!AlmostEqual(P1.m[i][j], P.m[i][j]))
            same = false;
   Check(same, "P^1 equals P");

   //--- P^2 も各行の和=1（確率行列の性質）
   Mat3 P2;
   CMarkovMatrix::MatPow(P, 2, P2);
   for(int i = 0; i < REGIME_COUNT; i++)
     {
      double s = P2.m[i][0] + P2.m[i][1] + P2.m[i][2];
      Check(AlmostEqual(s, 1.0, 1e-9), StringFormat("P^2 row %d sums to 1 (=%.6f)", i, s));
     }

   //--- one-hot × P = 該当行
   Vec3 cur; cur.v[0]=0; cur.v[1]=0; cur.v[2]=1;   // 現状態=Bull
   Vec3 pv;
   CMarkovMatrix::VecMat(cur, P, pv);
   Check(AlmostEqual(pv.v[0], P.m[REGIME_BULL][0]) &&
         AlmostEqual(pv.v[1], P.m[REGIME_BULL][1]) &&
         AlmostEqual(pv.v[2], P.m[REGIME_BULL][2]), "one-hot(Bull) * P == row(Bull)");

   //--- 差分シグナル
   double prob[REGIME_COUNT];
   prob[REGIME_BEAR]=0.20; prob[REGIME_SIDE]=0.15; prob[REGIME_BULL]=0.65;
   double diff; int dir;
   CMarkovSignal::Evaluate(prob, 0.10, diff, dir);
   Check(AlmostEqual(diff, 0.45) && dir == +1, "signal: diff=0.45 -> Long");

   prob[REGIME_BEAR]=0.50; prob[REGIME_SIDE]=0.30; prob[REGIME_BULL]=0.20;
   CMarkovSignal::Evaluate(prob, 0.10, diff, dir);
   Check(AlmostEqual(diff, -0.30) && dir == -1, "signal: diff=-0.30 -> Short");

   prob[REGIME_BEAR]=0.34; prob[REGIME_SIDE]=0.33; prob[REGIME_BULL]=0.33;
   CMarkovSignal::Evaluate(prob, 0.10, diff, dir);
   Check(dir == 0, "signal: small diff -> neutral");

   //--- ラプラス平滑化: 観測ゼロ行でも一様に近い分布になる
   int sparse[]; ArrayResize(sparse, 4);
   sparse[0]=REGIME_BULL; sparse[1]=REGIME_BULL; sparse[2]=REGIME_BULL; sparse[3]=REGIME_BULL;
   Mat3 Ps;
   CMarkovMatrix::Build(sparse, 1, 2, 1.0, Ps);
   for(int i = 0; i < REGIME_COUNT; i++)
     {
      double s = Ps.m[i][0] + Ps.m[i][1] + Ps.m[i][2];
      Check(AlmostEqual(s, 1.0, 1e-9), StringFormat("laplace row %d sums to 1", i));
     }

   PrintFormat("=== SelfTest finished: %s (failures=%d) ===",
               (g_fail == 0 ? "ALL PASS" : "HAS FAILURES"), g_fail);
  }
//+------------------------------------------------------------------+
