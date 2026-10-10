//+------------------------------------------------------------------+
//|                                           ExnessConnectionTest   |
//+------------------------------------------------------------------+
#property copyright "Algo Test"
#property version   "1.00"
#property strict

bool orderPlaced = false;

int OnInit()
{
   Print("=== EXNESS BOT READY. WAITING FOR FIRST PRICE TICK ===");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(orderPlaced) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0) return; // Wait for live broker price

   orderPlaced = true;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(ask * 0.99, digits);
   double tp = NormalizeDouble(ask * 1.01, digits);

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = 0.01;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 20;
   request.magic = 111222;
   request.comment = "Exness Test";
   
   // Auto-detect broker filling mode
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) request.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0) request.type_filling = ORDER_FILLING_IOC;
   else request.type_filling = ORDER_FILLING_RETURN;

   MqlTradeResult result;
   ZeroMemory(result);

   Print("Placing 0.01 BUY on ", _Symbol, " at Ask: ", ask);
   if(OrderSend(request, result))
   {
      Print(">>> SUCCESS! ORDER PLACED ON EXNESS! Ticket: ", result.order, " <<<");
   }
   else
   {
      Print(">>> Order failed. Retcode: ", result.retcode, " Error: ", GetLastError());
   }
}