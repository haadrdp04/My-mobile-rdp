
//+------------------------------------------------------------------+
//|                                           ExnessConnectionTest   |
//+------------------------------------------------------------------+
#property copyright "Algo Test"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

bool orderPlaced = false;

int OnInit()
{
   Print("=== EXNESS BOT INITIALIZED. WAITING FOR FIRST LIVE TICK ===");
   
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   trade.SetExpertMagicNumber(111222);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(orderPlaced) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0) return; // Wait until real broker price arrives

   orderPlaced = true;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(ask * 0.99, digits);
   double tp = NormalizeDouble(ask * 1.01, digits);

   Print(">>> FIRST TICK RECEIVED! Placing 0.01 BUY on ", _Symbol, " at Ask: ", ask);
   bool success = trade.Buy(0.01, _Symbol, ask, sl, tp, "Exness Test");

   if(success)
      Print(">>> SUCCESS! ORDER PLACED ON EXNESS! <<<");
   else
      Print(">>> Order failed. Error code: ", GetLastError());
}