//+------------------------------------------------------------------+
//| Gold_EMA_9_21_Demo.mq5                                          |
//| Educational starter EA. Test on demo only before any live use.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "EMA 9/21 crossover starter EA for gold, M5. Demo testing only."

#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
input int             InpFastEMA = 9;
input int             InpSlowEMA = 21;
input double          InpRiskPercent = 0.5;    // risk per trade (% of equity)
input double          InpRewardRisk = 2.0;    // TP distance = SL distance * this
input int             InpStopLossPoints = 500; // broker points; verify for your gold symbol
input int             InpMaxSpreadPoints = 80; // broker points; verify for your broker
input ulong           InpMagic = 9210501;
input int             InpDeviationPoints = 20;
input bool            InpAllowBuy = true;
input bool            InpAllowSell = true;

int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

int OnInit()
{
   fastHandle = iMA(_Symbol, InpTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, InpTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
   {
      Print("Could not create EMA indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   Print("Gold EMA 9/21 demo EA initialized on ", _Symbol,
         ". Confirm symbol is gold and timeframe/settings match your broker.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
}

void OnTick()
{
   // Evaluate once per new candle, using the two most recently closed bars.
   datetime currentBar = iTime(_Symbol, InpTimeframe, 0);
   if(currentBar == 0 || currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   if(BarsCalculated(fastHandle) < InpSlowEMA + 3 || BarsCalculated(slowHandle) < InpSlowEMA + 3)
      return;

   double fast[3], slow[3];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(fastHandle, 0, 0, 3, fast) != 3 || CopyBuffer(slowHandle, 0, 0, 3, slow) != 3)
   {
      Print("EMA data not ready. Error: ", GetLastError());
      return;
   }

   // [1] is last closed candle; [2] is the candle before it.
   bool crossUp   = (fast[2] <= slow[2] && fast[1] > slow[1]);
   bool crossDown = (fast[2] >= slow[2] && fast[1] < slow[1]);
   if(!crossUp && !crossDown) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0 || tick.bid <= 0) return;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;
   double spreadPoints = (tick.ask - tick.bid) / point;
   if(spreadPoints > InpMaxSpreadPoints)
   {
      Print("Signal skipped: spread too high (", DoubleToString(spreadPoints, 1), " points).");
      return;
   }

   // One position at a time on this symbol/magic. If one exists, do not stack trades.
   if(HasOurPosition()) return;

   if(crossUp && InpAllowBuy)  OpenTrade(ORDER_TYPE_BUY, tick);
   if(crossDown && InpAllowSell) OpenTrade(ORDER_TYPE_SELL, tick);
}

bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void OpenTrade(const ENUM_ORDER_TYPE orderType, const MqlTick &tick)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(point <= 0 || InpStopLossPoints <= 0 || InpRewardRisk <= 0) return;

   double volume = CalculateRiskVolume(InpStopLossPoints);
   if(volume <= 0)
   {
      Print("Trade skipped: calculated volume is below broker minimum or invalid.");
      return;
   }

   double entry = (orderType == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   double slDistance = InpStopLossPoints * point;
   double tpDistance = slDistance * InpRewardRisk;
   double sl = (orderType == ORDER_TYPE_BUY) ? entry - slDistance : entry + slDistance;
   double tp = (orderType == ORDER_TYPE_BUY) ? entry + tpDistance : entry - tpDistance;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Check broker's minimum stop distance before sending the order.
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel > 0 && InpStopLossPoints < stopsLevel)
   {
      Print("Trade skipped: stop-loss distance is smaller than broker's minimum stop level.");
      return;
   }

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(volume, _Symbol, 0.0, sl, tp, "EMA9x21 demo BUY");
   else
      ok = trade.Sell(volume, _Symbol, 0.0, sl, tp, "EMA9x21 demo SELL");

   if(!ok)
      Print("Order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   else
      Print("Order sent. Volume=", DoubleToString(volume, 2), " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits), ". DEMO TEST FIRST.");
}

double CalculateRiskVolume(const int slPoints)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * InpRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(equity <= 0 || riskMoney <= 0 || tickSize <= 0 || tickValue <= 0 || point <= 0 || minVol <= 0 || stepVol <= 0)
      return 0.0;

   double lossPerLot = ((slPoints * point) / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0.0;
   double rawVol = riskMoney / lossPerLot;
   double vol = MathFloor(rawVol / stepVol) * stepVol;
   vol = MathMin(vol, maxVol);
   if(vol < minVol) return 0.0; // never force the minimum if it exceeds the intended risk

   int volumeDigits = 0;
   double step = stepVol;
   while(volumeDigits < 8 && MathAbs(step - MathRound(step)) > 1e-8)
   {
      step *= 10.0;
      volumeDigits++;
   }
   return NormalizeDouble(vol, volumeDigits);
}
//+------------------------------------------------------------------+
