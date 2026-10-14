//+------------------------------------------------------------------+
//|                                        InstitutionalAlgoEA.mq5   |
//|                 DYNAMIC CONFLUENCE & TELEGRAM REPORTING ENGINE   |
//+------------------------------------------------------------------+
#property copyright "Pro Quant SMC"
#property version   "5.00"
#property strict

//--- INPUT PARAMETERS
input group "=== Telegram Settings ==="
input string   InpTelegramBotToken  = "YOUR_BOT_TOKEN_HERE";  // Telegram Bot Token
input string   InpTelegramChatID    = "YOUR_CHAT_ID_HERE";    // Telegram Chat ID
input bool     InpSendTelegramAlerts= true;                   // Send Trade Reports

input group "=== Confluence & Sizing ==="
input double   InpLotSize           = 0.01;      // Trade Lot Size
input int      InpMinConfidence     = 75;        // Minimum Confidence % to trade (70-90)
input double   InpRiskRewardRatio   = 2.0;       // Target R:R
input ulong    InpMagicNumber       = 777999;

//--- GLOBAL VARIABLES
datetime lastBarTime = 0;
int      emaH1Handle;
int      emaM5Handle;
int      rsiHandle;
int      atrHandle;
int      barsSinceTrade = 5;

//+------------------------------------------------------------------+
//| Send Message Directly to Telegram via WebRequest                 |
//+------------------------------------------------------------------+
void SendTelegramMessage(string message)
{
   if(!InpSendTelegramAlerts) return;
   
   string url = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
   string headers = "Content-Type: application/json\r\n";
   string payload = "{\"chat_id\":\"" + InpTelegramChatID + "\",\"text\":\"" + message + "\",\"parse_mode\":\"HTML\"}";
   
   char postData[], resultData[];
   StringToCharArray(payload, postData, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(postData, ArraySize(postData) - 1);
   string resultHeaders;
   
   int res = WebRequest("POST", url, headers, 3000, postData, resultData, resultHeaders);
   if(res == -1) Print("Telegram WebRequest error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== DYNAMIC CONFLUENCE ENGINE INITIALIZED ===");
   emaH1Handle = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   emaM5Handle = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle   = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   atrHandle   = iATR(_Symbol, PERIOD_M5, 14);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Visual Chart Drawings (Rectangles & Zones)                       |
//+------------------------------------------------------------------+
void DrawVisualZone(string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Dynamic Confluence Scoring Engine (0-100%)                       |
//+------------------------------------------------------------------+
int CalculateConfidence(bool isBuy, string &reasons)
{
   int score = 0;
   reasons = "";

   // 1. Trend Alignment (25 Pts)
   double emaH1[], emaM5[];
   ArraySetAsSeries(emaH1, true); ArraySetAsSeries(emaM5, true);
   CopyBuffer(emaH1Handle, 0, 0, 1, emaH1);
   CopyBuffer(emaM5Handle, 0, 0, 1, emaM5);
   double closePrice = iClose(_Symbol, PERIOD_M5, 1);

   if(isBuy && closePrice > emaH1[0] && closePrice > emaM5[0]) {
      score += 25;
      reasons += "• H1+M5 Bullish Trend (+25%)\n";
   } else if(!isBuy && closePrice < emaH1[0] && closePrice < emaM5[0]) {
      score += 25;
      reasons += "• H1+M5 Bearish Trend (+25%)\n";
   }

   // 2. Momentum Pullback (RSI) (20 Pts)
   double rsiVal[];
   ArraySetAsSeries(rsiVal, true);
   CopyBuffer(rsiHandle, 0, 0, 2, rsiVal);
   if(isBuy && rsiVal[0] < 45 && rsiVal[0] > rsiVal[1]) {
      score += 20;
      reasons += "• RSI Pullback Reversal (+20%)\n";
   } else if(!isBuy && rsiVal[0] > 55 && rsiVal[0] < rsiVal[1]) {
      score += 20;
      reasons += "• RSI Overbought Rejection (+20%)\n";
   }

   // 3. Liquidity Sweep & Displacement (35 Pts)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, PERIOD_M5, 0, 10, rates);
   double body = MathAbs(rates[1].close - rates[1].open);
   double avg = 0;
   for(int i = 2; i <= 6; i++) avg += MathAbs(rates[i].close - rates[i].open);
   avg /= 5;

   if(body > (avg * 1.3)) {
      score += 35;
      reasons += "• Institutional Displacement (+35%)\n";
   }

   // 4. Spread Sanity Check (20 Pts)
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread <= 30) {
      score += 20;
      reasons += "• Tight Spread Condition (+20%)\n";
   }

   return score;
}

//+------------------------------------------------------------------+
//| Main Execution Cycle                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   barsSinceTrade++;

   if(barsSinceTrade < 2) return; // Prevent overtrading

   // Check Open Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, 10, rates) < 10) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Evaluate BUY Setup
   string buyReasons = "";
   int buyScore = CalculateConfidence(true, buyReasons);
   if(buyScore >= InpMinConfidence && rates[1].close > rates[1].open)
   {
      double sl = rates[1].low - (2.0);
      double tp = ask + ((ask - sl) * InpRiskRewardRatio);
      
      MqlTradeRequest req; ZeroMemory(req);
      req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = InpLotSize;
      req.type = ORDER_TYPE_BUY; req.price = ask; req.sl = NormalizeDouble(sl, _Digits);
      req.tp = NormalizeDouble(tp, _Digits); req.magic = InpMagicNumber;
      req.type_filling = ORDER_FILLING_IOC;
      MqlTradeResult res; ZeroMemory(res);

      if(OrderSend(req, res)) {
         DrawVisualZone("SMC_BUY_ZONE", rates[1].time, rates[1].high, TimeCurrent() + PeriodSeconds()*12, sl, clrDodgerBlue);
         string msg = "🟢 <b>BUY ORDER EXECUTED</b>\n\n"
                    + "<b>Symbol:</b> " + _Symbol + "\n"
                    + "<b>Confidence:</b> " + IntegerToString(buyScore) + "%\n"
                    + "<b>Entry:</b> " + DoubleToString(ask, _Digits) + "\n"
                    + "<b>Stop Loss:</b> " + DoubleToString(sl, _Digits) + "\n"
                    + "<b>Take Profit:</b> " + DoubleToString(tp, _Digits) + "\n\n"
                    + "<b>Confluence Factors:</b>\n" + buyReasons;
         SendTelegramMessage(msg);
         barsSinceTrade = 0;
      }
      return;
   }

   // Evaluate SELL Setup
   string sellReasons = "";
   int sellScore = CalculateConfidence(false, sellReasons);
   if(sellScore >= InpMinConfidence && rates[1].close < rates[1].open)
   {
      double sl = rates[1].high + (2.0);
      double tp = bid - ((sl - bid) * InpRiskRewardRatio);
      
      MqlTradeRequest req; ZeroMemory(req);
      req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = InpLotSize;
      req.type = ORDER_TYPE_SELL; req.price = bid; req.sl = NormalizeDouble(sl, _Digits);
      req.tp = NormalizeDouble(tp, _Digits); req.magic = InpMagicNumber;
      req.type_filling = ORDER_FILLING_IOC;
      MqlTradeResult res; ZeroMemory(res);

      if(OrderSend(req, res)) {
         DrawVisualZone("SMC_SELL_ZONE", rates[1].time, sl, TimeCurrent() + PeriodSeconds()*12, rates[1].low, clrCrimson);
         string msg = "🔴 <b>SELL ORDER EXECUTED</b>\n\n"
                    + "<b>Symbol:</b> " + _Symbol + "\n"
                    + "<b>Confidence:</b> " + IntegerToString(sellScore) + "%\n"
                    + "<b>Entry:</b> " + DoubleToString(bid, _Digits) + "\n"
                    + "<b>Stop Loss:</b> " + DoubleToString(sl, _Digits) + "\n"
                    + "<b>Take Profit:</b> " + DoubleToString(tp, _Digits) + "\n\n"
                    + "<b>Confluence Factors:</b>\n" + sellReasons;
         SendTelegramMessage(msg);
         barsSinceTrade = 0;
      }
   }
}