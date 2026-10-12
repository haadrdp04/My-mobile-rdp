//+------------------------------------------------------------------+
//|                                        InstitutionalAlgoEA.mq5   |
//|                 PRO SMC GOLD SNIPER: BOS + EMA + AUTO BREAKEVEN  |
//+------------------------------------------------------------------+
#property copyright "Pro Institutional Algo"
#property version   "4.00"
#property strict

//--- INPUT PARAMETERS
input group "=== Risk & Target ==="
input double   InpLotSize           = 0.01;      // Trade Lot Size
input double   InpRiskRewardRatio   = 2.0;       // Risk to Reward Ratio (1:2)
input bool     InpUseBreakEven      = true;      // Auto Move SL to Break-Even at 1:1
input ulong    InpMagicNumber       = 777999;    // Bot Magic Number

input group "=== Strategy Filters ==="
input int      InpEMAPeriod         = 200;       // Institutional Trend Filter (200 EMA)
input int      InpSwingBars         = 15;        // Swing Lookback Bars (BOS)
input double   InpImpulseFactor     = 2.0;       // Strong Breakout Multiplier
input int      InpCooldownCandles   = 3;         // Wait X candles after a trade

//--- GLOBAL VARIABLES
datetime lastBarTime = 0;
int      barsSinceLastTrade = 10;
int      emaHandle;
int      atrHandle;

struct OrderBlock {
   double   high;
   double   low;
   bool     isBullish;
   bool     active;
};
OrderBlock currentOB;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== PRO GOLD SMC ENGINE ACTIVATED ===");
   emaHandle = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, 14);

   if(emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error loading indicators!");
      return(INIT_FAILED);
   }

   currentOB.active = false;
   UpdateDashboard("Scanning for A+ Trend & Structure Setups...");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   ObjectDelete(0, "ProOrderBlock");
   IndicatorRelease(emaHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Helper: Live On-Chart Dashboard                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(string status)
{
   string text = "====================================\n"
               + "  GOLD PRO INSTITUTIONAL SMC \n"
               + "====================================\n"
               + " Symbol: " + _Symbol + " | TF: " + EnumToString((ENUM_TIMEFRAMES)_Period) + "\n"
               + " Status: " + status + "\n"
               + " Active Zone: " + (currentOB.active ? (currentOB.isBullish ? "BULLISH OB" : "BEARISH OB") : "None") + "\n";

   if(currentOB.active)
   {
      text += " Zone: " + DoubleToString(currentOB.low, _Digits) + " - " + DoubleToString(currentOB.high, _Digits) + "\n";
   }

   text += " Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n"
         + " Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n"
         + "====================================";

   Comment(text);
}

//+------------------------------------------------------------------+
//| Helper: Draw Visual Zone                                         |
//+------------------------------------------------------------------+
void DrawZone(datetime timeStart, double high, double low, color clr)
{
   ObjectDelete(0, "ProOrderBlock");
   ObjectCreate(0, "ProOrderBlock", OBJ_RECTANGLE, 0, timeStart, high, TimeCurrent() + PeriodSeconds()*30, low);
   ObjectSetInteger(0, "ProOrderBlock", OBJPROP_COLOR, clr);
   ObjectSetInteger(0, "ProOrderBlock", OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, "ProOrderBlock", OBJPROP_FILL, true);
   ObjectSetInteger(0, "ProOrderBlock", OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Manage Break-Even on Open Trades                                 |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   if(!InpUseBreakEven) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         long posType = PositionGetInteger(POSITION_TYPE);

         // BUY: Move SL to Entry + Spread when price reaches 50% to TP
         if(posType == POSITION_TYPE_BUY)
         {
            double riskDist = openPrice - sl;
            if(riskDist > 0 && (currentPrice - openPrice) >= riskDist && sl < openPrice)
            {
               MqlTradeRequest req;
               ZeroMemory(req);
               req.action = TRADE_ACTION_SLTP;
               req.position = ticket;
               req.sl = NormalizeDouble(openPrice + (10 * _Point), _Digits);
               req.tp = tp;
               MqlTradeResult res;
               OrderSend(req, res);
               Print(">>> MOVED TO BREAK-EVEN! Ticket: ", ticket);
            }
         }
         // SELL: Move SL to Entry - Spread when price reaches 50% to TP
         else if(posType == POSITION_TYPE_SELL)
         {
            double riskDist = sl - openPrice;
            if(riskDist > 0 && (openPrice - currentPrice) >= riskDist && (sl > openPrice || sl == 0))
            {
               MqlTradeRequest req;
               ZeroMemory(req);
               req.action = TRADE_ACTION_SLTP;
               req.position = ticket;
               req.sl = NormalizeDouble(openPrice - (10 * _Point), _Digits);
               req.tp = tp;
               MqlTradeResult res;
               OrderSend(req, res);
               Print(">>> MOVED TO BREAK-EVEN! Ticket: ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute Order on Broker                                          |
//+------------------------------------------------------------------+
bool SendOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp, string comment)
{
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = InpLotSize;
   request.type = orderType;
   request.price = price;
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = 30;
   request.magic = InpMagicNumber;
   request.comment = comment;

   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) request.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0) request.type_filling = ORDER_FILLING_IOC;
   else request.type_filling = ORDER_FILLING_RETURN;

   MqlTradeResult result;
   ZeroMemory(result);

   if(OrderSend(request, result))
   {
      Print(">>> A+ TRADE OPENED! Ticket #", result.order, " SL: ", sl, " TP: ", tp);
      barsSinceLastTrade = 0;
      return true;
   }
   else
   {
      Print(">>> Order Send Failed! Retcode: ", result.retcode, " Error: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Main OnTick Execution                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageBreakEven();

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBarTime != lastBarTime);
   if(isNewBar)
   {
      lastBarTime = currentBarTime;
      barsSinceLastTrade++;
   }

   // 1. Scan for Break of Structure (BOS) on bar close
   if(isNewBar && barsSinceLastTrade >= InpCooldownCandles)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, _Period, 0, InpSwingBars + 5, rates) >= InpSwingBars + 5)
      {
         double emaVal[];
         ArraySetAsSeries(emaVal, true);
         CopyBuffer(emaHandle, 0, 0, 2, emaVal);

         double highestHigh = rates[2].high;
         double lowestLow = rates[2].low;
         for(int i = 3; i <= InpSwingBars; i++)
         {
            if(rates[i].high > highestHigh) highestHigh = rates[i].high;
            if(rates[i].low < lowestLow) lowestLow = rates[i].low;
         }

         double prevBody = MathAbs(rates[1].close - rates[1].open);
         double avgBody = 0;
         for(int i = 2; i <= InpSwingBars; i++) avgBody += MathAbs(rates[i].close - rates[i].open);
         avgBody /= (InpSwingBars - 1);

         // BULLISH BOS: Close ABOVE Swing High AND Price > 200 EMA
         if(rates[1].close > highestHigh && rates[1].close > emaVal[1] && prevBody > (avgBody * InpImpulseFactor))
         {
            for(int k = 2; k <= 5; k++)
            {
               if(rates[k].close < rates[k].open)
               {
                  currentOB.high = rates[k].high;
                  currentOB.low = rates[k].low;
                  currentOB.isBullish = true;
                  currentOB.active = true;
                  DrawZone(rates[k].time, currentOB.high, currentOB.low, clrDodgerBlue);
                  Print(">>> Bullish BOS! Mapped OB: ", currentOB.low, " - ", currentOB.high);
                  break;
               }
            }
         }
         // BEARISH BOS: Close BELOW Swing Low AND Price < 200 EMA
         else if(rates[1].close < lowestLow && rates[1].close < emaVal[1] && prevBody > (avgBody * InpImpulseFactor))
         {
            for(int k = 2; k <= 5; k++)
            {
               if(rates[k].close > rates[k].open)
               {
                  currentOB.high = rates[k].high;
                  currentOB.low = rates[k].low;
                  currentOB.isBullish = false;
                  currentOB.active = true;
                  DrawZone(rates[k].time, currentOB.high, currentOB.low, clrCrimson);
                  Print(">>> Bearish BOS! Mapped OB: ", currentOB.low, " - ", currentOB.high);
                  break;
               }
            }
         }
      }
   }

   // 2. Sniper Mitigation Entry
   if(currentOB.active)
   {
      UpdateDashboard(currentOB.isBullish ? "Waiting for Bullish Pullback Entry" : "Waiting for Bearish Pullback Entry");

      int openCount = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            openCount++;
      }

      if(openCount == 0)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         double atrVal[];
         ArraySetAsSeries(atrVal, true);
         CopyBuffer(atrHandle, 0, 0, 1, atrVal);
         double atrBuffer = (atrVal[0] > 0) ? (atrVal[0] * 1.5) : (3.0); 

         // BUY TRIGGER
         if(currentOB.isBullish && bid <= currentOB.high && bid >= currentOB.low)
         {
            double sl = currentOB.low - atrBuffer;
            double slDist = ask - sl;
            double tp = ask + (slDist * InpRiskRewardRatio);

            if(SendOrder(ORDER_TYPE_BUY, ask, sl, tp, "Gold SMC Buy"))
            {
               currentOB.active = false;
               ObjectDelete(0, "ProOrderBlock");
            }
         }
         // SELL TRIGGER
         else if(!currentOB.isBullish && ask >= currentOB.low && ask <= currentOB.high)
         {
            double sl = currentOB.high + atrBuffer;
            double slDist = sl - bid;
            double tp = bid - (slDist * InpRiskRewardRatio);

            if(SendOrder(ORDER_TYPE_SELL, bid, sl, tp, "Gold SMC Sell"))
            {
               currentOB.active = false;
               ObjectDelete(0, "ProOrderBlock");
            }
         }
      }
   }
   else
   {
      UpdateDashboard("Scanning 200 EMA & Structure for Breakouts...");
   }
}