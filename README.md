# Reclaimed Order Block ICT — MT5 Indicator

ICT / Smart Money style indicator for **MetaTrader 5** that identifies order blocks which price initially **breaks**, then **reclaims** after a structural shift. When price returns to the reclaimed zone, the indicator issues a **buy** or **sell** signal with an on-chart arrow and optional alerts.

## How it works

1. **Structure detection** — swing highs/lows are built from 3-point and/or 5-point pivots (ZigZag-style compression keeps alternating, most-extreme pivots).
2. **Break of structure (BOS)** — a close beyond the current swing level marks a structural break; the broken level is drawn as a dotted line (*Opposit Color*).
3. **Order block** — the last opposite candle before the impulsive move that broke structure becomes the order block zone (drawn as an extended rectangle).
4. **Reclaim & signal**
   - *First return*: price leaves the zone, then returns into it → signal.
   - *Reclaim*: price closes through the zone (order block violated), then closes back inside it after the structural shift → signal.
5. **Signals** — red arrows (233/234 Wingdings) at the pivot's end, plus popup / push / email alerts.

## Settings

| Input | Default | Description |
|---|---|---|
| Bar Count | 1000 | Number of candles analysed |
| Buy Side Of The Curve | true | Enable bullish setups |
| Sell Side Of The Curve | true | Enable bearish setups |
| 3 Point Strategy | true | Triple (3-bar) pivot strategy |
| 5 Point Strategy | true | Quintuple (5-bar) pivot strategy |
| Opposit Color | Black | Contrasting hue for structure lines |
| Bull/Bear zone color | Sandy brown | Reclaimed zone rectangle fill |
| Signal arrow color | Red | Buy/sell arrow color |
| Max live zones per side | 6 | Oldest zones are pruned |
| Signal on first return / reclaim | true / true | Signal triggers |
| Popup / Push / Email alerts | true / false / false | Alert channels |

## Installation

1. Copy `Reclaimed_Order_Block_ICT.mq5` into `MQL5/Indicators/` of your MT5 data folder.
2. Open MetaEditor and compile (F7), or restart MT5 — it compiles on attach.
3. Drag onto any chart. Multi-timeframe; works on Forex, crypto, and stocks.

## Notes

- Signals are evaluated on **completed bars** to avoid repainting.
- Consumed zones are frozen at the signal bar; live zones extend to the right until touched, broken, or pruned.
- This is a re-implementation of the TradingFinder "Reclaimed Order Block ICT" concept, not the original source code.

*For educational purposes — not financial advice.*
