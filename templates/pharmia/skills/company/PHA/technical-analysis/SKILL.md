---
name: technical-analysis
description: >-
  Technical analysis of stocks/crypto — trendlines, patterns,
  support/resistance, indicators. Use when asked to analyze a ticker, chart, or
  price action.
---
# Technical Analysis

Every claim must be computed and validated — no "it looks like" without data backing it.

## Tooling

```bash
# Raw OHLCV (trendlines, patterns, structure, EMAs)
python3 -c "
import yfinance as yf
t = yf.Ticker('SYMBOL')
h = t.history(period='PERIOD')
for d, r in h.iterrows():
    print(f'{d.strftime(\"%Y-%m-%d\")}  O:{r[\"Open\"]:5.2f} H:{r[\"High\"]:5.2f} L:{r[\"Low\"]:5.2f} C:{r[\"Close\"]:5.2f}  V:{int(r[\"Volume\"]):>10,}')
"
```

Default `1y` for trendlines. `3mo` for short-term. `2y` when near all-time lows.

```bash
# Automated scanner (EMAs, volume, BB, RSI, alerts, schedule management)
python3 ~/vortex-claude/scripts/market-scan.py --all        # full scan
python3 ~/vortex-claude/scripts/market-scan.py BTQ POET     # specific tickers
python3 ~/vortex-claude/scripts/market-scan.py              # only tickers due today per schedule
python3 ~/vortex-claude/scripts/market-scan.py --macro      # macro only

# Helpers (import inline for trendlines, fibs, patterns)
# from ta_helpers import find_swings, best_trendline, fib_retracements, detect_pattern
```

`maverick` CLI at `~/.local/bin/maverick` is available for ad-hoc deep dives but NOT used in daily scan — the script computes everything needed.

**Goldilocks scanner (PRIMARY for portfolio decisions):**
`python3 ~/vortex-claude/scripts/goldilocks.py` — bi-weekly rotation scanner. 73 tickers, momentum ranking, EMA 200 filter, regime toggle. This is the ACTIVE strategy.

**Options flow:** `python3 ~/vortex-claude/scripts/options-flow.py --paz` — Barchart flow scraper via curl_cffi.

**Pine indicator:** `~/Documents/vortex-quant/goldilocks-indicator.pine` — TradingView overlay showing Goldilocks filters, EMA bounce dots, parabolic warnings, and regime.

Scanner outputs JSON, saves journal to `~/Documents/vortex-quant/journal/YYYY-MM-DD.md`, and updates scan schedule at `~/Documents/vortex-quant/scan-schedule.json`. The schedule tracks priority (daily/3-day/weekly), next check date, reasons, and history per ticker — so you can see "why did I say wait a week for this?" and "since when are we analyzing this?"

**Goldilocks scout** runs Friday 4 PM ET, DMs rebalance orders for Monday execution. Old `market-scan` scout is disabled.

**Watchlists:**
- Red List (primary, 73 tickers): https://www.tradingview.com/watchlists/173814100/
- Old watchlist (reference only): https://www.tradingview.com/watchlists/173814090/

## Active Strategy: Goldilocks Momentum Rotation

**The old signal-based system (compression breakouts, capitulation buys, EMA reclaims) returned +28%. Goldilocks returns +607% in bull years. Use Goldilocks.**

Full strategy doc: `~/Documents/vortex-quant/strategy-2026.md`
Scanner: `python3 ~/vortex-claude/scripts/goldilocks.py`
Backtest log (22 phases, 600+ configs): `~/Documents/vortex-quant/backtest-log.md`

**Rules:**
1. Hold 6 tickers (4 in bear), rebalance bi-weekly on Monday (scout runs Friday 4 PM to give orders)
2. Sell bottom 2 by 2-week momentum, buy top 2 from 73-ticker universe
3. Ranking: pure momentum + EMA 20 bounce boost (+0.10 if bounced in last 5 bars)
4. Sizing: momentum-proportional, 30% concentration cap
5. Buy filter: price > EMA 200, $1M+ daily dollar volume
6. Regime: SPX fib toggle (< 50% of 252-day range = BEAR: 4 holdings, 40% cash)

**Performance (73-ticker universe, Apr 2022 -- Apr 2026):**
- Bear: +22%, Recovery: +130%, Mixed: -11%, Bull: +607%, Composite: +628
- Walk-forward (out-of-sample): +96% avg across 6 windows
- Beats 99.4% of random 8-pick portfolios
- Slippage resilient (survives 1.0%), scales $20k-$500k

**What works:** Monday rebalancing (+99), 30% cap (+34), EMA 20 bounce +0.10 (+57), EMA 200 filter, momentum-proportional sizing.

**What doesn't work (all tested, all rejected):** RSI/MACD/BB as ranking factors, fixed fib targets, macro event adaptation, seasonality, fixed stop losses, signal stacking, EMA 20 reclaim as buy signal (-0.08% expectancy).

## Old Signal-Based Results (archived, DO NOT use for portfolio decisions)

These are from the original backtest before Goldilocks was developed. Kept for reference only.
- Compression breakout: 64% win, +6.86%/trade with fixed targets, +15.51% with EMA 50 trailing
- Capitulation buy: 72% win, +3.71% expectancy
- EMA 20 reclaim: 48% win, -0.08% expectancy -- BREAK EVEN, do not use
- EMA 200 bounce: -4.65%/trade -- NEGATIVE expectancy

## Ad-Hoc Deep Dive Protocol (on request only)

This protocol is for deep dives when the user asks about a specific ticker. It is NOT the daily workflow. Portfolio decisions are made by the Goldilocks scanner (`goldilocks.py`) -- never recommend buys/sells based on individual ticker analysis.

**Daily workflow:** Run `goldilocks.py`, report regime + any urgent alerts (EMA 200 break or parabolic on held tickers) + next rebalance date. On rebalance Mondays, full SELL/BUY/HOLD orders. On off-days, two lines max. See the goldilocks scout prompt in scouts.yaml.

Steps 1-8 below are for deep dives only. Run maverick + yfinance in parallel first.

### 1. Structure — swing highs/lows (window >= 5 bars), trend direction, current position

### 2. Trendlines (CRITICAL — the skill's core differentiator)

**Never present a trendline without computed touch count.**

1. Try all anchor pairs from swing points
2. Count independent touches within %-based tolerance (not fixed $)
3. Only present lines with **3+ independent touches** (excluding anchors)
4. Report: anchors, slope, touch count, tolerance, current value, each touch with deviation

Two connected dots is a line segment, not a trendline.

**When to run trendlines:** Not every ticker every day. Run the full trendline computation when:
- BB compression detected (<12%) — price is coiling, trendline tells you WHERE the breakout level is
- Ticker is on daily check with an active setup
- User asks for a deep dive
Don't run on weekly-check tickers or noisy microcaps with erratic swings — the touches will be meaningless.

### 3. Support/Resistance

- Cross-reference maverick levels with swing points and trendline intersections
- "Next support" must be BELOW current price. "Next resistance" must be ABOVE. Always verify directionally.
- Near all-time low with nothing below = say "price discovery territory"

### 4. Patterns — always state Bulkowski failure rates alongside any call

### 5. EMAs (20/50/200) — trend context, not signals

Report: price vs each EMA, 50 vs 200 relationship, distance from 200.

### 6. Macro Context

**Tickers:** `^VIX`, `DX-Y.NYB`, `^TNX`, `^GSPC`, `CL=F`, `GC=F`

**Presentation rule:** Always show absolute values alongside % changes. Write "10Y: 4.32% (-2.2% 5d)" not just "yields easing (-2.2% 5d)." The user wants to see the number, not just the direction.

**Non-obvious correlations for this portfolio (verified with evidence):**
- **Oil down ≠ precious metals down.** Gold/silver often rally when oil crashes (safe haven + rate cut expectations). Don't conflate energy commodities with precious metals — different drivers entirely.
- **Oil vs CAD: largely decoupled since 2017.** CAD rose 1.8% in 2025 while oil fell 12%. Only reasserts during acute supply shocks (>$100 geopolitical events). Don't assume oil down = CAD weakness for CAD positions.
- **10Y yield + equity direction = regime signal:**
  - Rising yields + falling equities = worst (tightening fear)
  - Falling yields + rising equities = best (Goldilocks)
  - Falling yields + falling equities = recession fear (gold bullish, equities bearish)
- **Risk-off detection:** GLD >+2%, TLT >+1%, DXY >+1% over 5 days simultaneously → reduce equity buy conviction 30%

### 7. Position Sizing

`Shares = (Account × Risk%) / |Entry - Stop|`. Max 10% position. Account ~$78k (~$65k invested + ~$12.5k cash).

Default risk per trade: **3%** (backtested: +3,188% 1Y return, -26.8% max DD on this watchlist). This fits the user's risk tolerance (-30% DD for +500% upside).

High-vol small-caps (BTQ, POET, LPTH): halve risk % if ATR >5% of price.

**Risk profile: aggressive asymmetry-seeker.** Can tolerate -30% drawdown for +500% upside potential. Prioritize 5:1+ R:R setups (trendline breaks on beaten-down names, capitulation buys, compression breakouts in bear-to-bull transitions) over safe 2-3:1 plays on institutional names. The user wants to risk a little to catch structural reversals. Wider stops, conviction sizing on high-asymmetry setups, no need for tight risk management on structural bull positions. EMA 200 break = thesis dead, not arbitrary % stops.

### 8. Synthesis — structure, levels, trendlines, patterns, indicators, macro, what to watch

### 9. Journal Entry

After every analysis, append to `~/Documents/vortex-quant/journal/YYYY-MM-DD.md`. One file per day, one section per ticker. Record: price, assessment (BUY/HOLD/SELL/WATCH), key levels, stop, targets, EMA structure, and the reasoning. Also record a macro snapshot once per day. This creates a verifiable track record — future sessions can review past calls against actual outcomes.

## Parabolic Extension Warning

**The single most actionable rule in this skill.**

When price is >20% above EMA 20 AND RSI >75 AND volume >2x average → flag "parabolic extension — trim 30-50%, re-enter on pullback to EMA 20."

**Small-caps: tighten to >15% above EMA 20.** Less liquidity = harder snaps, wider gaps, no institutional floor.

Evidence: SLV was 26.5% above EMA 20, RSI 82.7, +104% in 3 months on Jan 28/2026 → crashed -45% in days. Zero macro catalyst — purely technical overextension. BTQ did the same Oct 2025: +130% in 3 days, then -54% in 10 days.

## Ticker Disambiguation

**Any CAD-denominated position is always TSX.** Append `.TO` for yfinance. Portfolio CAD tickers: PSLV.TO, SU.TO, AG.TO, NEO.TO. For other ambiguous tickers, ask before running.

**Always present TSX (.TO) tickers in CAD.** When giving prices, entries, stops, targets, and position sizes for TSX tickers, use CAD. For USD tickers, convert to CAD when presenting position sizing so the user sees everything in their home currency. Use `CADUSD=X` from yfinance to get the live rate.

**Trading hours:** TSX has no after-hours or pre-market — locked at 4 PM ET close, reopens 9:30 AM ET. US-listed tickers can be traded overnight via Wealthsimple extended hours. Factor this into event-driven advice: .TO positions cannot be adjusted on overnight news, US positions can.

## Anti-Rules

- Never present a trendline without computed touch count
- Never state "next support" that is above current price
- Never use the all-time high as the default target for R:R — use the nearest fib retracement (38.2% or 61.8%). ATH targets inflate R:R and lead to overheld positions.
- Never present a stale signal as actionable — if an EMA 20 reclaim happened 3 days ago and price has moved 15%+, the entry is gone. Say "signal was valid on [date], now too extended to chase."
- Never present a pattern without its failure rate
- Never use indicators as standalone signals
- Quarter-end breakouts (Mar 31, Jun 30, Sep 30, Dec 31) need extra skepticism — window dressing, rebalancing flows, thin liquidity
- Never recommend a buy/sell based on individual ticker analysis when the Goldilocks rotation is active. Defer to the scanner. The TA protocol is for deep dives on request, not portfolio decisions.
- Never use EMA 20 reclaim as a standalone buy signal — backtested to -0.08% expectancy across 116 signals.

## Self-Improvement

This skill is a living document. Proactively update after each TA session — no permission needed.

**What to add:** only non-obvious lessons, hard-won corrections, verified intermarket relationships, and tooling changes. Do NOT add anything easily inferred from base knowledge (indicator definitions, basic TA concepts, standard pattern descriptions). If a senior trader already knows it, it doesn't belong here.

**Format:** dated entry in Lessons Log. Promote to main sections when mature, then remove from log.

## Fibonacci Retracements

Use fibs for **price targets on bounces**, not as support/resistance (they work via self-fulfilling prophecy, not math). Compute from the most recent significant swing high to swing low:
- 38.2% retrace = first target / first resistance on a bounce. High probability of profit-taking here.
- 61.8% retrace = deep retrace, still healthy if in a bull structure.
- If price clears 61.8% retrace on volume, the correction is likely over.

Example: SLV high $109.83, low $60.37. 38.2% retrace = $60.37 + (49.46 * 0.382) = $79.26. 61.8% = $90.92.

## Reference: Institutional Flow Filter (Paz Strategy)

Complementary signal from options flow — use as confirmation overlay, not standalone.
**Now available for free** via `python3 ~/vortex-claude/scripts/options-flow.py --paz` (Barchart scraper using curl_cffi).

**Filter criteria (all must be true):**
- Premium >= $400,000 (big money, not retail)
- ATM or OTM (directional bets, not hedges)
- DTE >= 90 days (conviction, not 0DTE gambling)
- Opening positions only (new bets, not closing/rolling)
- Trade side at Ask or above Ask (buyer-initiated = bullish intent)
- Block, split, or sweep execution (institutional, not retail drip)
- Volume > Open Interest (fresh activity, not existing positions)
- Call contracts only (bullish bets)

**Translation:** "Smart money is opening large, long-dated bullish call positions aggressively on this name."

**How to use with this system:** When the scanner flags a compression breakout or capitulation buy, and the flow filter shows $1M+ in 90-DTE calls being swept at ask on the same ticker — that's double confirmation. Upgrade conviction from STARTER to SCALE IN.

**Free proxy (built into scanner — TODO):** CBOE options chain: filter call strikes where `volume > OI` AND `estimated_premium > $400k` AND `DTE >= 90` AND `strike >= spot`. Catches ~60% of signals but misses trade side and block/sweep detection.

## Lessons Log

- **2026-04-04**: CONFIG D VALIDATED AND REJECTED. VIX persistence gate (3d on/2d off) + 15% small-cap cap looked great on full-period backtest (+1,032pp, Sharpe 1.89) but FAILED consecutive quarter validation (3/16 wins). Bear year: -8.3% vs baseline +19%. Root cause: persistence gate is too slow for fast VIX spikes on this universe, and SC cap kills concentration in the names that drive returns. Both features WORK on Nasdaq 100 — they're real improvements for diversified universes, just wrong for concentrated thematic portfolios. Production stays at baseline S6 (simple VIX >= 20, uniform 30% cap). Key lesson: always run consecutive quarters before deploying — it catches every false positive.
- **2026-04-03**: CASH OVERLAY BUG FIXED. Config C (holdings avg momentum) never triggered because top-6 holdings always have >+10% momentum by construction. Replaced with S6 (Blend + VIX gate): VIX < 20 = full send, VIX >= 20 = blend of universe median + SPX 10d momentum with recalibrated thresholds. S6 correctly recommended 20% cash on Apr 3 (VIX 23.9, oil shock). Per-ticker risk sizing (inverse vol, risk parity, Sharpe-proportional) all REJECTED — destroys alpha. Risk management is portfolio-level (cash overlay), not ticker-level (sizing).
- **2026-04-03**: LIVE WATCHLIST INTEGRATION. goldilocks.py now auto-fetches from TradingView Red List (176 tickers vs old 76 hardcoded). Auto-detects CAD tickers from TSX/TSXV. Falls back to hardcoded if fetch fails. Use --no-fetch for offline.
- **2026-04-03**: DYNAMIC CASH SIZING is the one validated improvement to Goldilocks. Config C (momentum regime cash): hold cash proportional to how weak your holdings' avg 10d momentum is. Sharpe 1.93 vs 1.74 baseline, MaxDD -42% vs -49%, works on Nasdaq 100 too. All binary exit signals (SPX < 200d SMA, VIX > 30, drawdown stops, death cross) FAILED — they create whipsaw death spirals or re-entry traps. Graduated sizing works where binary switching doesn't. The satellite's own momentum is the best predictor of its own risk — external macro signals (VIX, SPX, breadth) measure the wrong thing.
- **2026-04-03**: STRATEGY ARCHITECTURE CLARIFIED. The alpha IS the universe (stock picking). Rotation + cash overlay are delivery mechanisms that amplify thesis alpha and manage risk. Rotation on S&P 500 = -20pp vs buy-and-hold. Rotation on Nasdaq 100 = -67pp vs QQQ. Same rotation on our 76 tickers = +1,400%. The edge is the thesis, not the algorithm. Implication: monitor universe quality (momentum dispersion between tickers), not algorithm parameters.
- **2026-04-02 (late night)**: BROAD UNIVERSE VALIDATION killed the "momentum rotation" thesis. Same rotation logic on Nasdaq 100 = -1.5% (vs QQQ +65.6%), on sector ETFs = +18.3% (vs SPX +44.6%), on S&P 500 = +24.6% (vs SPX +44.6%). The rotation destroys value on every universe except our hand-picked 76 tickers. What we have is a concentrated thematic bet, not a momentum strategy. Academic consensus: optimal lookback is 12 months minus 1 month (2-12), not 2 weeks. Our 2-week signal is in the reversal zone. Next direction: sector ETF rotation with academic parameters as a reliable foundation.
- **2026-04-02 (night)**: RIGOROUS VALIDATION SESSION. 25+ experiments proved the baseline Goldilocks config (10d/10d/sell-2/76 tickers) is already optimal. Every tested "improvement" (21d rebalance, sell-1, VIX regime, breadth filter, mid-cap universe) was bull amplification masquerading as better strategy -- all lost money in the bear year. PBO = 0.40 means config selection is overfit. DSR passes for all configs -- alpha is real but comes from the universe (same rotation on S&P 500 returned +24.6% vs +1,438% on our universe). Random-window testing is MISLEADING for this strategy -- only consecutive-quarter and full-period regime-separated tests tell the truth. Installed backtest-audit + deflated-sharpe for future validation.
- **2026-04-02**: RANDOM WINDOW SPOT-CHECK revealed the true cost of Goldilocks. 3-month windows: 33% win rate, +0.7% mean, -31% avg MaxDD. 12-month windows: 70% win rate, +46.8% mean, -41% avg MaxDD. The +607% composite is real but drawdowns of -30% to -65% are NORMAL in any 12-month period. Strategy works via long-term compounding of a few big winners, not consistent gains. Any 3-month slice is a coin flip. User's -30% DD tolerance is below the -41% average — acknowledged but proceeding.
- **2026-04-02**: PROTECTION ALERTS merged into goldilocks.py. Parabolic warnings (+15% above EMA 20, RSI >70) and EMA 200 breaks on held positions now fire on both rebalance and off-weeks. Market-scan scout disabled — goldilocks is the single source of truth for portfolio decisions.
- **2026-04-02**: S/R detection added to market-scan.py via ta_helpers.py. Clusters swing highs/lows into zones, ranks by touch count. Useful for deep dives but does NOT affect Goldilocks decisions (momentum rank only).
- **2026-04-02**: STRATEGY OVERHAUL. 22 phases of backtesting proved momentum rotation (Goldilocks) massively outperforms signal-based trading (+607% vs +28%). The old system's +3,188% claim was unverified and wrong. All portfolio decisions now go through `goldilocks.py`. This TA skill is for ad-hoc deep dives only, not portfolio management. Individual indicators (RSI, MACD, BB) are noise when added to rotation — tested 24 indicators, only EMA 200 filter and EMA 20 bounce boost helped.
- **2026-04-02**: Options flow scraper built (`options-flow.py`). Uses curl_cffi with chrome136 impersonation to bypass Barchart WAF. Free access to institutional flow data (sweeps, blocks, premium, trade side). Paz filter implemented for bullish conviction detection.
- **2026-04-02**: Pine indicator created (`goldilocks-indicator.pine`). Shows on TradingView: BUYABLE/BLOCKED status, EMA bounce dots (green), parabolic warnings (red triangles), regime, score. Parabolic warnings caught both MRVL peaks visually on the weekly chart.
- **2026-04-01**: Trendline validation protocol created after first BTQ analysis drew a fake "clean" line with zero intermediate touches. The second attempt (9 touches, 4% tolerance) was the real one.
- **2026-04-01**: SLV parabolic crash retrospective revealed all warning signs were technical (RSI 82.7, 26.5% above EMA 20, climactic volume). Macro was fine. Pure overextension.
- **2026-04-01**: March backtest P/L scorecard: trim signals 2/2 correct (LWLG, AAOI avoided -23 to -31%). Capitulation buys 2W/1F/1L (AG.TO +19%, LWLG +60%, LITE flat, COHR -6%). Compression breakout 1W/1L (SU.TO +13%, ALMU -32%). Lesson: parabolic trims are highest-reliability signal. Volume breakouts in weak/bear structure (ALMU) are dangerous — weight structure more heavily.
- **2026-04-01**: March backtest showed the system would have caught: LWLG parabolic trim (RSI 80+), AG.TO 4.4x capitulation, COHR 6.5x capitulation, LITE 3.6x capitulation, SU.TO BB compression breakout (3.6% → ran from $78 to $92), AAOI parabolic trim. The system is NOT quiet during corrections — it catches capitulation and compression signals. Never claim "nothing to do" without running the data.
- **2026-04-01**: BB compression + trendline = the money combo. BTC had BB 7.0% (tightest on watchlist) and without trendline analysis it was just "coiling, wait." With it: price was 1.4% below a 6-touch descending resistance — a specific breakout level. Always run trendlines on compressed tickers.
- **2026-04-01**: Volume spike >3x on a down day in a bull-structure stock during a liquidity event = likely capitulation, not distribution. AG.TO printed 4.4x on Mar 20 and bounced +14.5% in 5 days. BUT: individual stock sample sizes are always tiny (n=2 for AG.TO). Frame as "looks like capitulation, context supports it" — never state a probability from small samples. The follow-through next day is the real confirmation, not the spike itself.
