//+------------------------------------------------------------------+
//|                                     Reclaimed_Order_Block_ICT.mq5 |
//|                        Reclaimed Order Block - ICT / Smart Money  |
//|                        MetaTrader 5 Indicator, version 1.00       |
//+------------------------------------------------------------------+
#property copyright   "Reclaimed Order Block ICT"
#property version     "1.00"
#property description "ICT-style Reclaimed Order Block indicator."
#property description "Detects order blocks that price breaks, then reclaims"
#property description "after a structural shift, and issues buy/sell signals"
#property description "when price returns to the reclaimed zone."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- settings shown in the PDF -------------------------------------
input group "===== Indicator Setting ====="
input int    InpBarCount         = 1000;          // Bar Count (number of candles)
input bool   InpBuySide          = true;          // Buy Side Of The Curve (bullish curve)
input bool   InpSellSide         = true;          // Sell Side Of The Curve (bearish curve)
input bool   InpPointStrategy3   = true;          // 3 Point Strategy (triple)
input bool   InpPointStrategy5   = true;          // 5 Point Strategy (quintuple)
input color  InpOppositeColor    = clrBlack;      // Opposit Color (structure line hue)

input group "===== Zones & Signals ====="
input color  InpBullZoneColor    = C'244,164,96'; // Bullish reclaimed zone color
input color  InpBearZoneColor    = C'244,164,96'; // Bearish reclaimed zone color
input color  InpSignalColor      = clrRed;        // Signal arrow color
input int    InpMaxZones         = 6;             // Max live zones per side
input bool   InpSignalFirstTouch = true;          // Signal on first return to the zone
input bool   InpSignalReclaim    = true;          // Signal on reclaim after the zone was broken

input group "===== Alerts ====="
input bool   InpAlertPopup       = true;          // Popup alert
input bool   InpAlertPush        = false;         // Push notification
input bool   InpAlertEmail       = false;         // Email

//+------------------------------------------------------------------+
//| internals                                                        |
//+------------------------------------------------------------------+
#define ROB_PREFIX "ROB_"

enum ENUM_ZONE_STATE
{
   ZS_ACTIVE   = 0,   // waiting for price to return
   ZS_BROKEN   = 1,   // price closed through the zone - waiting for reclaim
   ZS_CONSUMED = 2    // signal fired, zone frozen
};

struct Zone
{
   int      dir;        // +1 bullish, -1 bearish
   double   top;
   double   bottom;
   int      startBar;
   datetime startTime;
   int      state;
   bool     wasAway;    // price has fully left the zone at least once
   string   name;
};

//--- zigzag style pivot store (built from 3-point / 5-point pivots)
int      g_pivBar[];
double   g_pivPrice[];
int      g_pivType[];       // +1 = swing high, -1 = swing low
int      g_lastHighIdx = -1;
int      g_lastLowIdx  = -1;
bool     g_highBroken  = true;
bool     g_lowBroken   = true;

Zone     g_zones[];
datetime g_lastAlertTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Reclaimed Order Block ICT MT5 1.00");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, ROB_PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 10)
      return(0);

   //--- full rebuild over the configured lookback (cheap for <= a few thousand bars)
   int start = MathMax(4, rates_total - InpBarCount);
   Rebuild(start, rates_total, time, open, high, low, close);
   ChartRedraw();
   return(rates_total);
}

//+------------------------------------------------------------------+
//| main pass over historical bars                                   |
//+------------------------------------------------------------------+
void Rebuild(const int start, const int total,
             const datetime &time[], const double &open[],
             const double &high[], const double &low[], const double &close[])
{
   ArrayResize(g_pivBar, 0);
   ArrayResize(g_pivPrice, 0);
   ArrayResize(g_pivType, 0);
   ArrayResize(g_zones, 0);
   g_lastHighIdx = -1; g_lastLowIdx = -1;
   g_highBroken  = true; g_lowBroken = true;

   ObjectsDeleteAll(0, ROB_PREFIX);

   datetime futureRight = time[total - 1] + (datetime)(12 * PeriodSeconds(_Period));
   int lastCompleted   = total - 2;             // bar total-1 is still forming

   for(int i = start; i <= lastCompleted; i++)
   {
      //--- 1) pivots confirmed by the close of bar i
      if(InpPointStrategy3)
      {
         int c = i - 1;
         if(c > start && IsPivotHigh3(c, high)) AddPivot(+1, c, high[c]);
         if(c > start && IsPivotLow3 (c, low )) AddPivot(-1, c, low[c]);
      }
      if(InpPointStrategy5)
      {
         int c = i - 2;
         if(c > start + 1 && IsPivotHigh5(c, high)) AddPivot(+1, c, high[c]);
         if(c > start + 1 && IsPivotLow5 (c, low )) AddPivot(-1, c, low[c]);
      }

      //--- 2) structural breaks (BOS)
      if(g_lastHighIdx >= 0 && !g_highBroken && close[i] > g_pivPrice[g_lastHighIdx])
      {
         int origin = (g_lastLowIdx >= 0) ? g_pivBar[g_lastLowIdx] : start;
         DrawStructureLine(g_pivBar[g_lastHighIdx], i, g_pivPrice[g_lastHighIdx], time, futureRight);
         if(InpBuySide)
            CreateZone(+1, i, origin, open, high, low, close, time, futureRight);
         g_highBroken = true;
      }
      if(g_lastLowIdx >= 0 && !g_lowBroken && close[i] < g_pivPrice[g_lastLowIdx])
      {
         int origin = (g_lastHighIdx >= 0) ? g_pivBar[g_lastHighIdx] : start;
         DrawStructureLine(g_pivBar[g_lastLowIdx], i, g_pivPrice[g_lastLowIdx], time, futureRight);
         if(InpSellSide)
            CreateZone(-1, i, origin, open, high, low, close, time, futureRight);
         g_lowBroken = true;
      }

      //--- 3) zone lifecycle (touch -> signal, close-through -> broken, re-entry -> reclaim)
      bool allowAlert = (i == lastCompleted);
      for(int k = 0; k < ArraySize(g_zones); k++)
         UpdateZone(g_zones[k], i, high, low, close, time, allowAlert, futureRight);
   }
}

//+------------------------------------------------------------------+
//| pivot detection (center bar i, non-series arrays)                |
//+------------------------------------------------------------------+
bool IsPivotHigh3(const int i, const double &high[])
{  return(high[i] > high[i-1] && high[i] > high[i+1]); }

bool IsPivotLow3(const int i, const double &low[])
{  return(low[i] < low[i-1] && low[i] < low[i+1]); }

bool IsPivotHigh5(const int i, const double &high[])
{  return(high[i] > high[i-1] && high[i] > high[i-2] &&
          high[i] > high[i+1] && high[i] > high[i+2]); }

bool IsPivotLow5(const int i, const double &low[])
{  return(low[i] < low[i-1] && low[i] < low[i-2] &&
          low[i] < low[i+1] && low[i] < low[i+2]); }

//+------------------------------------------------------------------+
//| zigzag compression: keep alternating, most-extreme pivots        |
//+------------------------------------------------------------------+
void AddPivot(const int type, const int bar, const double price)
{
   int n = ArraySize(g_pivType);
   if(n > 0 && g_pivType[n-1] == type)
   {
      bool better = (type == +1) ? (price > g_pivPrice[n-1])
                                 : (price < g_pivPrice[n-1]);
      if(better)
      {
         g_pivBar[n-1]   = bar;
         g_pivPrice[n-1] = price;
         // a fresh, more extreme pivot is a new level to break
         if(type == +1) g_highBroken = false;
         else           g_lowBroken  = false;
      }
      return;
   }
   ArrayResize(g_pivBar,   n + 1);
   ArrayResize(g_pivPrice, n + 1);
   ArrayResize(g_pivType,  n + 1);
   g_pivBar[n]   = bar;
   g_pivPrice[n] = price;
   g_pivType[n]  = type;

   if(type == +1) { g_lastHighIdx = n; g_highBroken = false; }
   else           { g_lastLowIdx  = n; g_lowBroken  = false; }
}

//+------------------------------------------------------------------+
//| order block = last opposite candle before the structural break   |
//+------------------------------------------------------------------+
void CreateZone(const int dir, const int bosBar, const int originBar,
                const double &open[], const double &high[],
                const double &low[],  const double &close[],
                const datetime &time[], const datetime futureRight)
{
   int ob = -1;
   for(int j = bosBar - 1; j >= MathMax(originBar, 1); j--)
   {
      if(dir == +1 && close[j] < open[j]) { ob = j; break; }  // bearish candle -> bullish OB
      if(dir == -1 && close[j] > open[j]) { ob = j; break; }  // bullish candle -> bearish OB
   }
   if(ob < 0)   // fallback: most extreme candle of the originating swing
   {
      ob = MathMax(originBar, 1);
      for(int j = MathMax(originBar, 1); j < bosBar; j++)
      {
         if(dir == +1 && low[j]  < low[ob])  ob = j;
         if(dir == -1 && high[j] > high[ob]) ob = j;
      }
   }

   PruneZones(dir);

   int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1);
   Zone z;
   z.dir      = dir;
   z.top      = high[ob];
   z.bottom   = low[ob];
   z.startBar = ob;
   z.startTime= time[ob];
   z.state    = ZS_ACTIVE;
   z.wasAway  = false;
   z.name     = StringFormat("%sZone_%s_%d", ROB_PREFIX, (dir > 0 ? "Bull" : "Bear"), ob);
   g_zones[n] = z;

   DrawZone(g_zones[n], futureRight);
}

//+------------------------------------------------------------------+
//| keep at most InpMaxZones live zones per direction                |
//+------------------------------------------------------------------+
void PruneZones(const int dir)
{
   int live = 0;
   for(int k = 0; k < ArraySize(g_zones); k++)
      if(g_zones[k].dir == dir && g_zones[k].state != ZS_CONSUMED)
         live++;

   for(int k = 0; k < ArraySize(g_zones) && live >= InpMaxZones; k++)
   {
      if(g_zones[k].dir == dir && g_zones[k].state != ZS_CONSUMED)
      {
         ObjectDelete(0, g_zones[k].name);
         g_zones[k].state = ZS_CONSUMED;
         live--;
      }
   }
}

//+------------------------------------------------------------------+
//| zone lifecycle for one bar                                       |
//+------------------------------------------------------------------+
void UpdateZone(Zone &z, const int i,
                const double &high[], const double &low[], const double &close[],
                const datetime &time[], const bool allowAlert, const datetime futureRight)
{
   if(z.state == ZS_CONSUMED || z.startBar >= i)
      return;

   double top = z.top, bot = z.bottom;

   if(z.dir == +1)                                   // ---- bullish (buy side)
   {
      if(!z.wasAway && low[i] > top) z.wasAway = true;

      if(z.state == ZS_ACTIVE)
      {
         if(z.wasAway && InpSignalFirstTouch && low[i] <= top && close[i] >= bot)
         {
            FireSignal(z, +1, i, high, low, time, allowAlert);
            z.state = ZS_CONSUMED;
            ObjectSetInteger(0, z.name, OBJPROP_TIME, 1, time[i]);
         }
         else if(close[i] < bot)
            z.state = ZS_BROKEN;                     // order block violated
      }
      else if(z.state == ZS_BROKEN)
      {
         if(InpSignalReclaim && close[i] >= bot)      // reclaimed from below
         {
            FireSignal(z, +1, i, high, low, time, allowAlert);
            z.state = ZS_CONSUMED;
            ObjectSetInteger(0, z.name, OBJPROP_TIME, 1, time[i]);
         }
      }
   }
   else                                              // ---- bearish (sell side)
   {
      if(!z.wasAway && high[i] < bot) z.wasAway = true;

      if(z.state == ZS_ACTIVE)
      {
         if(z.wasAway && InpSignalFirstTouch && high[i] >= bot && close[i] <= top)
         {
            FireSignal(z, -1, i, high, low, time, allowAlert);
            z.state = ZS_CONSUMED;
            ObjectSetInteger(0, z.name, OBJPROP_TIME, 1, time[i]);
         }
         else if(close[i] > top)
            z.state = ZS_BROKEN;
      }
      else if(z.state == ZS_BROKEN)
      {
         if(InpSignalReclaim && close[i] <= top)      // reclaimed from above
         {
            FireSignal(z, -1, i, high, low, time, allowAlert);
            z.state = ZS_CONSUMED;
            ObjectSetInteger(0, z.name, OBJPROP_TIME, 1, time[i]);
         }
      }
   }

   if(z.state != ZS_CONSUMED)
      ObjectSetInteger(0, z.name, OBJPROP_TIME, 1, futureRight);   // keep extending
}

//+------------------------------------------------------------------+
//| signal arrow + alert                                             |
//+------------------------------------------------------------------+
void FireSignal(const Zone &z, const int dir, const int i,
                const double &high[], const double &low[],
                const datetime &time[], const bool allowAlert)
{
   double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double off = (high[i] - low[i]) * 0.5 + 10 * pt;

   string nm = StringFormat("%sArrow_%s_%d", ROB_PREFIX, (dir > 0 ? "Buy" : "Sell"), i);
   if(ObjectFind(0, nm) < 0)
   {
      if(dir > 0)
      {
         ObjectCreate(0, nm, OBJ_ARROW, 0, time[i], low[i] - off);
         ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, 233);      // up arrow below the bar
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_TOP);
      }
      else
      {
         ObjectCreate(0, nm, OBJ_ARROW, 0, time[i], high[i] + off);
         ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, 234);      // down arrow above the bar
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
      }
      ObjectSetInteger(0, nm, OBJPROP_COLOR, InpSignalColor);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }

   if(allowAlert && time[i] > g_lastAlertTime)
   {
      g_lastAlertTime = time[i];
      string msg = StringFormat("Reclaimed Order Block ICT: %s signal on %s (%s) @ %s",
                                (dir > 0 ? "BUY" : "SELL"), _Symbol,
                                EnumToString(_Period),
                                DoubleToString(dir > 0 ? low[i] : high[i], _Digits));
      if(InpAlertPopup) Alert(msg);
      if(InpAlertPush)  SendNotification(msg);
      if(InpAlertEmail) SendMail("Reclaimed Order Block ICT", msg);
   }
}

//+------------------------------------------------------------------+
//| drawing helpers                                                  |
//+------------------------------------------------------------------+
void DrawZone(const Zone &z, const datetime right)
{
   if(ObjectFind(0, z.name) < 0)
      ObjectCreate(0, z.name, OBJ_RECTANGLE, 0, z.startTime, z.top, right, z.bottom);
   ObjectSetInteger(0, z.name, OBJPROP_COLOR, z.dir > 0 ? InpBullZoneColor : InpBearZoneColor);
   ObjectSetInteger(0, z.name, OBJPROP_FILL, true);
   ObjectSetInteger(0, z.name, OBJPROP_BACK, true);
   ObjectSetInteger(0, z.name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, z.name, OBJPROP_TIME, 1, right);
}

void DrawStructureLine(const int pivotBar, const int bosBar, const double price,
                       const datetime &time[], const datetime futureRight)
{
   string nm = StringFormat("%sBOS_%d", ROB_PREFIX, bosBar);
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_TREND, 0, time[pivotBar], price, futureRight, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, InpOppositeColor);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
