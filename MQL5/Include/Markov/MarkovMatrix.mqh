//+------------------------------------------------------------------+
//|                                                 MarkovMatrix.mqh  |
//|     遷移行列の構築・正規化・累乗／詳細設計書 5.3, 5.4           |
//+------------------------------------------------------------------+
#ifndef __MARKOV_MATRIX_MQH__
#define __MARKOV_MATRIX_MQH__

#include "MarkovTypes.mqh"

//+------------------------------------------------------------------+
//| 3x3 遷移行列ユーティリティ                                        |
//+------------------------------------------------------------------+
class CMarkovMatrix
  {
public:
   //--- ラベル列から遷移行列 P を構築（行正規化＋ラプラス平滑化）
   //--- label[] は as_series（index 小=新しい）。
   //--- shift..shift+trainLookback の範囲の遷移を数える。
   //--- 遷移は「古い(p+1) -> 新しい(p)」: i=label[p+1], j=label[p]。
   static bool       Build(const int &label[], const int shift, const int trainLookback,
                           const double alpha, Mat3 &P)
     {
      double N[REGIME_COUNT][REGIME_COUNT];
      for(int i = 0; i < REGIME_COUNT; i++)
         for(int j = 0; j < REGIME_COUNT; j++)
            N[i][j] = alpha;   // ラプラス平滑化（各セルに +alpha）

      int total = ArraySize(label);
      int counted = 0;
      for(int p = shift; p <= shift + trainLookback - 1; p++)
        {
         if(p + 1 >= total)
            break;
         int i = label[p + 1];   // 古い側（遷移元）
         int j = label[p];       // 新しい側（遷移先）
         if(i < 0 || j < 0)
            continue;            // データ不足のラベルはスキップ
         N[i][j] += 1.0;
         counted++;
        }

      //--- 行正規化。行和=0 の行は一様分布で埋める。
      for(int i = 0; i < REGIME_COUNT; i++)
        {
         double rowsum = 0.0;
         for(int j = 0; j < REGIME_COUNT; j++)
            rowsum += N[i][j];
         if(rowsum > 0.0)
           {
            for(int j = 0; j < REGIME_COUNT; j++)
               P.m[i][j] = N[i][j] / rowsum;
           }
         else
           {
            for(int j = 0; j < REGIME_COUNT; j++)
               P.m[i][j] = 1.0 / REGIME_COUNT;
           }
        }
      return (counted > 0 || alpha > 0.0);
     }

   //--- 行列積 C = A * B
   static void       MatMul(const Mat3 &A, const Mat3 &B, Mat3 &C)
     {
      for(int i = 0; i < REGIME_COUNT; i++)
         for(int j = 0; j < REGIME_COUNT; j++)
           {
            double s = 0.0;
            for(int k = 0; k < REGIME_COUNT; k++)
               s += A.m[i][k] * B.m[k][j];
            C.m[i][j] = s;
           }
     }

   //--- 行列累乗 R = P^n（n>=1）
   static void       MatPow(const Mat3 &P, const int n, Mat3 &R)
     {
      R = P;
      Mat3 tmp;
      for(int e = 1; e < n; e++)
        {
         MatMul(R, P, tmp);
         R = tmp;
        }
     }

   //--- 行ベクトル × 行列： out = v * M
   static void       VecMat(const Vec3 &v, const Mat3 &M, Vec3 &out)
     {
      for(int j = 0; j < REGIME_COUNT; j++)
        {
         double s = 0.0;
         for(int k = 0; k < REGIME_COUNT; k++)
            s += v.v[k] * M.m[k][j];
         out.v[j] = s;
        }
     }
  };

#endif // __MARKOV_MATRIX_MQH__
//+------------------------------------------------------------------+
