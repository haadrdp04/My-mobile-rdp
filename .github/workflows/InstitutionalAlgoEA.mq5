//+------------------------------------------------------------------+
//|                                        InstitutionalAlgoEA.mq5   |
//|                   Autonomous SMC Regime & Execution Engine       |
//+------------------------------------------------------------------+
#property copyright "Algorithmic Trader"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- ENUMS
enum ENUM_TRADING_MODE
{
   MODE_PROP_STEADY = 0,    // Steady Growth / Prop-Firm (1 trade, strict 1% risk)
   MODE_SNIPER_LAYER = 1    // Sniper Layering (Multi-order stack inside Order Block)
};

enum ENUM_MARKET_REGIME
{
   REGIME_BAD = 0,          // High spread, dead/erratic volatility -> SLEEP
   REGIME_NORMAL = 1,       // Standard market -> Fixed 1:2 R:R
   REGIME_PRIME = 2         // Trend momentum -> Extended targets + Trail
};

//--- INPUT PARAMETERS
input group "=== Trading Mode & Risk ==="
input ENUM_TRADING_MODE InpTradingMode      = MODE_PROP_STEADY; // Execution Style
input double            InpRiskPercent      = 1.0;              // Total Risk % per setup
input double            InpMaxDailyLossPct  = 3.0;              // Daily Hard Stop Loss % (Anti-Blowup)
input double            InpFixedRR          = 2.0;              // Normal Market Risk:Reward
input int               InpSniperLayers     = 4;                // Number of stacked orders (Sniper Mode)
input ulong             InpMagicNumber      = 777999;           // Magic Number

input group "=== Market Regime Filters ==="
input int               InpMaxSpreadPoints  = 35;               // Max Spread allowed (XAUUSD points)
input int               InpADXPeriod        = 14;               // ADX Period
input double            InpADXBadLevel      = 20.0;             // ADX below this = Choppy (No Trade)
input double            InpADXPrimeLevel    = 32.0;             // ADX above this = Prime Trend

input group "=== News Protection ==="
input bool              InpEnableNewsFilter = true;             // Blackout trading during High Impact News
input int               InpNewsMinutesBefore= 15;               // Minutes before news to halt
input int               InpNewsMinutesAfter = 15;               // Minutes after news to resume

input group "=== Order Block / SMC Settings ==="
input int               InpSwingBars        = 10;               // Lookback bars for Swing Levels
input double            InpImpulseFactor    = 1.8;              // Impulse body multiplier

//--- GLOBAL HANDLES & VARIABLES
int      adxHandle;
int      atrHandle;
datetime lastBarTime = 0;
double   dailyStartEquity = 0;
datetime lastDailyReset = 0;

struct OrderBlockZone {
   double   top;
   double   bottom;
   bool     isBullish;
   bool     active;
   datetime formedTime;
};
OrderBlockZone activeOB;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   adxHandle = iADX(_Symbol, _Period, InpADXPeriod);
   atrHandle = iATR(_Symbol, _Period, 14);
   
   if(adxHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) {
      Print("Error creating indicator handles.");
      return(INIT_FAILED);
   }

   dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastDailyReset = iTime(_Symbol, PERIOD_D1, 0);
   activeOB.active = false;

   Print("InstitutionalAlgoEA active. Mode: ", EnumToString(InpTradingMode));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(adxHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Reset Daily Drawdown Baseline at 00:00 Server Time               |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != lastDailyReset) {
      lastDailyReset = currentDay;
      dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("Daily reset. Baseline Equity: ", dailyStartEquity);
   }
}

//+------------------------------------------------------------------+
//| Anti-FOMO Daily Loss Circuit Breaker                             |
//+------------------------------------------------------------------+
bool IsDailyLossExceeded()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double maxAllowedLoss = dailyStartEquity * (InpMaxDailyLossPct / 100.0);
   if((dailyStartEquity - currentEquity) >= maxAllowedLoss) {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| High-Impact News Filter (MT5 Calendar API)                       |
//+------------------------------------------------------------------+
bool IsNewsEventActive()
{
   if(!InpEnableNewsFilter) return false;
   
   datetime now = TimeCurrent();
   datetime from = now - (InpNewsMinutesAfter * 60);
   datetime to   = now + (InpNewsMinutesBefore * 60);
   
   MqlCalendarValue values[];
   // Checks country code of current base/profit currency (e.g. US for USD)
   int count = CalendarValueHistory(values, from, to, "US");
   if(count > 0) {
      for(int i = 0; i < count; i++) {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event)) {
            // Priority 3 = High Impact event (CPI, NFP, Interest Rates)
            if(event.importance == CALENDAR_IMPORTANCE_HIGH) {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Market Regime Classification Engine                              |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectMarketRegime()
{
   // 1. Spread Check
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > InpMaxSpreadPoints) {
      return REGIME_BAD;
   }
   
   // 2. Trend & Volatility Strength
   double adxVal[];
   ArraySetAsSeries(adxVal, true);
   if(CopyBuffer(adxHandle, 0, 0, 1, adxVal) <= 0) return REGIME_BAD;
   
   if(adxVal[0] < InpADXBadLevel) {
      return REGIME_BAD; // Flat, directionless chop
   }
   else if(adxVal[0] >= InpADXPrimeLevel) {
      return REGIME_PRIME; // Strong institutional trend
   }
   
   return REGIME_NORMAL;
}

//+------------------------------------------------------------------+
//| Helper: Check For New Candle (0% CPU Idle)                       |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(currentBar != lastBarTime) {
      lastBarTime = currentBar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Dynamic Lot Calculation (Server-Side Exactness)                  |
//+------------------------------------------------------------------+
double CalculateLots(double slDistance, double riskPct)
{
   if(slDistance <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (riskPct / 100.0);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize == 0 || tickValue == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   double lossPerLot = (slDistance / tickSize) * tickValue;
   double rawLot = riskMoney / lossPerLot;
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double normLot = MathFloor(rawLot / step) * step;
   return MathMax(minLot, MathMin(maxLot, normLot));
}

//+------------------------------------------------------------------+
//| Main Execution Cycle                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyReset();
   
   // Hard Circuit Breaker (Prevents tilt/FOMO)
   if(IsDailyLossExceeded()) return;
   
   // Execute core logic on bar close to save CPU
   if(!IsNewBar()) return;
   
   // Halt on News
   if(IsNewsEventActive()) return;

   // Classify Market Quality
   ENUM_MARKET_REGIME regime = DetectMarketRegime();
   if(regime == REGIME_BAD) {
      activeOB.active = false; // Invalidate setups in bad chop
      return;
   }

   // Scan for Order Blocks
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, InpSwingBars + 5, rates) < InpSwingBars + 5) return;

   double prevBody = MathAbs(rates[1].close - rates[1].open);
   double avgBody = 0;
   for(int i = 2; i <= InpSwingBars; i++) avgBody += MathAbs(rates[i].close - rates[i].open);
   avgBody /= (InpSwingBars - 1);

   // Bullish Displacement -> Identify Bullish OB
   if(rates[1].close > rates[1].open && prevBody > (avgBody * InpImpulseFactor)) {
      if(rates[2].close < rates[2].open) {
         activeOB.top = rates[2].high;
         activeOB.bottom = rates[2].low;
         activeOB.isBullish = true;
         activeOB.active = true;
         activeOB.formedTime = rates[1].time;
      }
   }
   // Bearish Displacement -> Identify Bearish OB
   else if(rates[1].close < rates[1].open && prevBody > (avgBody * InpImpulseFactor)) {
      if(rates[2].close > rates[2].open) {
         activeOB.top = rates[2].high;
         activeOB.bottom = rates[2].low;
         activeOB.isBullish = false;
         activeOB.active = true;
         activeOB.formedTime = rates[1].time;
      }
   }

   // Entry Verification & Execution
   if(!activeOB.active) return;
   
   // Ensure no active trades exist with this magic number
   int openCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         openCount++;
   }
   if(openCount > 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Determine Reward multiplier by Regime (Take more profit in prime market)
   double targetRR = (regime == REGIME_PRIME) ? (InpFixedRR * 1.6) : InpFixedRR;

   // BUY TRIGGER: Price pulled back inside Bullish Order Block
   if(activeOB.isBullish && bid <= activeOB.top && bid >= activeOB.bottom)
   {
      double sl = activeOB.bottom - (15 * _Point); // Hard SL below block
      double slDist = ask - sl;
      double tp = ask + (slDist * targetRR);

      if(InpTradingMode == MODE_PROP_STEADY) {
         double lot = CalculateLots(slDist, InpRiskPercent);
         trade.Buy(lot, _Symbol, ask, sl, tp, "Steady OB Buy");
      }
      else { // SNIPER LAYERING: Split risk into stacked micro-orders
         double layerRisk = InpRiskPercent / InpSniperLayers;
         double lot = CalculateLots(slDist, layerRisk);
         for(int k = 0; k < InpSniperLayers; k++) {
            trade.Buy(lot, _Symbol, ask, sl, tp, "Sniper Stack Buy");
         }
      }
      activeOB.active = false; // Zone consumed
   }
   // SELL TRIGGER: Price pulled back inside Bearish Order Block
   else if(!activeOB.isBullish && ask >= activeOB.bottom && ask <= activeOB.top)
   {
      double sl = activeOB.top + (15 * _Point); // Hard SL above block
      double slDist = sl - bid;
      double tp = bid - (slDist * targetRR);

      if(InpTradingMode == MODE_PROP_STEADY) {
         double lot = CalculateLots(slDist, InpRiskPercent);
         trade.Sell(lot, _Symbol, bid, sl, tp, "Steady OB Sell");
      }
      else { // SNIPER LAYERING
         double layerRisk = InpRiskPercent / InpSniperLayers;
         double lot = CalculateLots(slDist, layerRisk);
         for(int k = 0; k < InpSniperLayers; k++) {
            trade.Sell(lot, _Symbol, bid, sl, tp, "Sniper Stack Sell");
         }
      }
      activeOB.active = false;
   }
}