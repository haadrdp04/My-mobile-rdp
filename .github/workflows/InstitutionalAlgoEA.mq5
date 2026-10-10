//+------------------------------------------------------------------+
//|                                           ExnessConnectionTest   |
//+------------------------------------------------------------------+
#property copyright "Algo Test"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

int OnInit()
{
   Print("=== RUNNING EXNESS BITCOIN PING TEST ===");
   
   // Auto-detect Exness filling mode (Prevents error 10030)
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   trade.SetExpertMagicNumber(111222);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // 1% Stop Loss and 1% Take Profit (Safe for BTC volatility)
   double sl = NormalizeDouble(ask * 0.99, digits);
   double tp = NormalizeDouble(ask * 1.01, digits);

   Print("Placing instant test BUY on ", _Symbol, " at Ask: ", ask);
   bool success = trade.Buy(0.01, _Symbol, ask, sl, tp, "Exness BTC Ping Test");

   if(success)
      Print(">>> SUCCESS: Bitcoin test order placed on Exness! <<<");
   else
      Print(">>> Order failed. Error code: ", GetLastError());

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // Idle after test trade is fired
}