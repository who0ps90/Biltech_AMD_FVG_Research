Act as a senior MQL5 developer and quantitative strategy tester.

Build an MT5 Expert Advisor named **Biltech_AMD_FVG_Research**.

Implement a reproducible Accumulation → Failed Breakout → Reclaim → Fair Value Gap pullback strategy.

This is a research system, not a proven profitable strategy. Do not claim profitability, invent backtest results, or optimise settings merely to produce attractive results.

## 1. Working instructions

- Inspect the existing workspace and repository instructions first.
- Preserve unrelated files.
- Use native MQL5 and standard libraries wherever practical.
- Check current official MQL5 documentation for relevant APIs.
- Implement the EA, meaningful tests, documentation, and example configurations.
- Make routine engineering decisions independently and document them.
- Do not connect to a brokerage account, place real trades, or enable live trading.
- If compilation or MT5 testing is unavailable, explicitly report what remains unverified.
- Do not substitute a Python simulation for an actual MT5 Strategy Tester result.

## 2. Scope

Version 1 includes:

- Long and short trades.
- Ordinary FVG entries only.
- One chart symbol per EA instance.
- Configurable execution timeframe, default M5.
- Closed-candle signal detection.
- Percentage-risk position sizing.
- Pending limit entries with protective SL and TP.
- Session filters, optional news exclusions, and spread filters.
- Chart annotations, diagnostic logs, and CSV trade journals.
- Visual-only, demo-trading, and Strategy Tester operation.

Exclude:

- Inverse FVG entries.
- Grid, martingale, averaging down, pyramiding.
- AI-generated trade decisions.
- Automatic parameter optimisation.
- Breakeven, partial exits, and trailing stops.
- External paid APIs.

Keep the architecture modular so those features could be evaluated separately later.

## 3. Safety modes

Provide:

- VisualOnly: default true; detect and display setups without sending orders.
- AllowDemoTrading: default false.
- AllowRealAccountTrading: default false.

Require the relevant explicit permission input for demo or real-account order placement. In Strategy Tester, allow simulated orders when VisualOnly is false.

Refuse new entries if configuration, price data, time conversion, position sizing, or required filters are invalid.

Never alter or close manual trades or another EA’s orders.

## 4. Deterministic processing

Use completed candles only for setup decisions.

Process each newly completed signal-timeframe bar exactly once. Use chronological naming in the implementation and documentation to avoid MQL5 series-index confusion.

Every state transition must record:

- Symbol and timeframe.
- Setup ID.
- Event timestamp.
- Information available at that timestamp.
- Relevant prices.
- Acceptance or rejection reason.

No retrospective entries, future-bar references, or moving old signals to earlier timestamps.

## 5. Accumulation range

Default parameters:

- RangeLookbackBars = 20.
- ATRPeriod = 14.
- MaxRangeATR = 3.0.

While idle, evaluate the last 20 completed candles:

- RangeHigh = highest high.
- RangeLow = lowest low.
- RangeWidth = RangeHigh − RangeLow.
- Qualify when RangeWidth > 0 and RangeWidth <= 3 × ATR(14).
- Use ATR from the most recently completed candle.

At the first qualifying observation, freeze the range boundaries and qualification timestamp.

Only candles occurring after qualification can create the sweep. Do not count a candle used to define the range as a breakout of that same range.

Permit only one active range.

Expire an unswept range after 20 subsequent completed candles or at session end. This expiry is an engineering convention, not a proven strategy parameter.

## 6. Sweep and reclaim

A downside sweep occurs when a subsequent candle trades at least one symbol tick below RangeLow.

An upside sweep occurs when a subsequent candle trades at least one tick above RangeHigh.

- Downside sweep creates a potential long.
- Upside sweep creates a potential short.
- Wicks or bodies can breach the range.
- A wick sweep followed by a close inside on the same candle is valid.

Require a completed candle to close strictly inside the frozen range within three candles, counting the first sweep candle as candle one.

Track the most extreme price during the sweep/reclaim sequence.

Reject the setup when:

- No reclaim occurs within the allowed three candles.
- Both range boundaries are breached before confirmation.
- A single candle breaches both boundaries and tick ordering is not explicitly resolved.
- The session ends.

After the reclaim, invalidate the setup if a subsequent completed candle extends beyond the recorded sweep extreme before FVG confirmation.

## 7. FVG confirmation

Use three consecutive completed candles, labelled A, B, and C in chronological order.

Bullish FVG:

- Low(C) > High(A).
- Zone = High(A) to Low(C).
- Close(C) > High(B).

Bearish FVG:

- High(C) < Low(A).
- Zone = High(C) to Low(A).
- Close(C) < Low(B).

Require:

- C closes on or after the reclaim candle.
- B is not earlier than the first sweep candle.
- C closes strictly inside the frozen accumulation range.
- Gap width is at least one symbol tick.
- Direction matches the proposed reversal.
- The FVG is confirmed no later than the third candle counting the reclaim candle as candle one.

Use the first qualifying FVG only.

Provide optional MinFVG_ATR filtering, default 0.0, disabled. If enabled, use completed-bar ATR at confirmation.

Freeze the sweep extreme, FVG zone, entry, stop, and target at confirmation.

## 8. Entry and exit

Entry is the midpoint of the confirmed FVG:

- Bullish setup: Buy Limit.
- Bearish setup: Sell Limit.

Place the order only on the first available tick after C closes.

Never count a midpoint touch before C closes as an entry.

Reject the trade if:

- The midpoint is already marketable or cannot be placed as a valid limit order.
- Broker restrictions cannot be satisfied without changing the strategy prices materially.
- The target lacks sufficient room.
- Risk, margin, session, news, or spread filters fail.

Do not substitute a market order or chase a missed entry.

Stop buffer:

- Buffer = max(2 × tick size, current spread in price units, 0.10 × ATR at confirmation).
- Long SL = sweep low − buffer.
- Short SL = sweep high + buffer.

Target:

- Fixed 2R.
- Long TP = entry + 2 × (entry − SL).
- Short TP = entry − 2 × (SL − entry).

Require the long target to be no higher than RangeHigh and the short target no lower than RangeLow. Otherwise skip.

Normalise to tick size conservatively and recalculate actual risk and reward afterward.

Pending-order expiry:

- Three execution-timeframe periods after confirmation.
- Session end.
- Entry into an applicable news-exclusion window.
- A new breach of the sweep extreme.

Explain that EA-managed cancellation happens on observed ticks and may race with broker execution. Do not imply that cancellation guarantees no fill.

Use broker-side expiration when supported, plus EA-side cancellation.

One order attempt per range. A rejected, cancelled, expired, or completed setup must not generate repeated attempts.

Attach SL and TP to the initial order request. Never intentionally open an unprotected position.

No discretionary stop changes. Close EA-owned positions at session end and cancel its pending orders.

## 9. Risk and exposure

Defaults:

- RiskPercent = 0.25% of current equity.
- Maximum two filled trades per session.
- Stop after two losing trades during the trading day.
- Daily loss threshold = 0.5% of day-start equity.
- Maximum one EA-owned position or pending entry.

Use OrderCalcProfit or an equivalent official MQL5 calculation to determine the account-currency loss between entry and stop.

Respect:

- Tick size.
- Minimum and maximum volume.
- Volume step.
- Contract specifications.
- Account-currency conversion.
- Margin requirements.
- Broker stop and freeze levels.

Round volume down. Never round up to minimum volume if that exceeds the risk budget.

Allow configurable round-trip commission and slippage allowances in sizing. State clearly when unknown costs are omitted.

Skip if minimum volume cannot fit the budget.

Calculate daily EA performance using realised net P&L plus floating P&L, including available commission and swap information. The trading day follows the configured session timezone.

At the daily threshold:

- Cancel EA-owned pending entries.
- Attempt to close EA-owned positions.
- Lock entries until the next trading day.

Persist counters and reconcile them with account history after restarts. Actual losses can exceed thresholds due to gaps, slippage, or disconnection.

Prevent separate instances with the same strategy identity from bypassing shared risk limits.

On netting accounts, refuse new trades when an existing position on the symbol could mix ownership with another strategy.

## 10. Sessions and time conversion

Provide configurable session times and timezone modes:

- America/New_York convention.
- Europe/London convention.
- Explicit broker-server time.

Default research session:

- 09:45–11:00 New York local time.
- Monday–Friday.

Alternative FX research session:

- 08:00–10:00 London local time.

Implement and test applicable DST rules. Document the supported historical date range.

Do not assume the broker server timezone equals New York, London, UTC, or the computer timezone.

Require explicit broker UTC-offset configuration for historical testing, supporting fixed offsets and a documented DST schedule. Fail clearly if conversion cannot be determined.

Do not use the present live-server offset to convert all historical timestamps.

Handle sessions crossing midnight and date changes correctly.

Allow pre-session candles to form the range, but require the sweep, confirmation, and order submission to occur within the configured entry session.

Display broker time and converted session-local time on the chart.

## 11. Spread and news filters

Spread filter:

- Use live bid/ask.
- Default maximum spread = 10% of planned stop distance.
- Provide an optional symbol-specific absolute cap.
- Log spread at submission and fill.

Clarify that submission-time filtering cannot guarantee the spread at a later pending-order fill.

News filter:

- Make optional and configurable.
- Provide CSV-based scheduled-event exclusions for reproducible testing.
- Explicitly identify the CSV timezone, preferably UTC.
- Allow relevant currencies to be specified rather than inferred blindly from broker symbol names.
- Default exclusion interval: 15 minutes before and after selected high-impact events.
- Cancel pending entries at the exclusion boundary.
- Existing positions keep their original SL/TP unless daily-risk or session-end rules intervene.

If a required calendar is missing or invalid, disable new entries and show a clear diagnostic.

Do not silently imply that historical calendar coverage is complete.

## 12. State machine and visuals

Use explicit states such as:

IDLE → RANGE_READY → SWEPT → RECLAIMED → FVG_CONFIRMED → ORDER_PENDING → POSITION_OPEN → COMPLETED / INVALIDATED.

Draw:

- Frozen range box.
- Sweep marker.
- Reclaim marker.
- Confirmed FVG zone.
- Entry, SL, and TP.
- Current state and invalidation reason.

Do not erase failed setups merely to make the chart look cleaner. Permit a configurable history limit.

Annotate the actual detection time, even when a box visually extends backward to cover its constituent candles.

## 13. Restart and execution resilience

Handle:

- Terminal restarts and lost connections.
- Missing history and invalid ATR.
- Market closure.
- Order rejection and unsupported expiration.
- Partial fills.
- Duplicate transaction notifications.
- Broker price and volume precision.
- Pending-order expiry while disconnected.

Use OnTradeTransaction for authoritative execution reconciliation.

Persist or reconstruct active setup state safely. Never duplicate an existing order after restart.

Bound retries; never loop indefinitely or silently alter entry, SL, TP, or risk to force acceptance.

## 14. Testing and research outputs

Provide meaningful tests or deterministic fixtures covering:

- Valid long and short.
- Same-candle sweep and reclaim.
- Genuine breakout with no reclaim.
- Ambiguous double sweep.
- FVG appearing before permitted confirmation.
- Midpoint touched before confirmation.
- Unfilled entry expiry.
- Insufficient reward space.
- Excessive spread.
- Minimum-volume risk violation.
- DST transitions and broker conversion.
- Daily lockout and restart recovery.
- Order rejection, partial fill, and duplicate events.

Document MT5 testing using “Every tick based on real ticks,” where available.

Use the actual broker instrument intended for execution. Do not assume futures and similarly named CFDs share prices or contract economics.

Journal:

- All qualified setups and rejection reasons.
- Signal and execution timestamps.
- Planned and actual prices.
- Volume, spread, fees, slippage, and net P&L.
- Net result in R using initial planned monetary risk.
- Missed and expired orders.
- Rule version and configuration.

Report, when actual test data is available:

- Trade count.
- Win rate.
- Average net win/loss in R.
- Net expectancy.
- Profit factor.
- Maximum equity drawdown.
- Longest losing streak.
- Results by instrument and session.
- Development versus untouched validation results.

Do not fabricate these statistics when no test has run.

## 15. Deliverables and completion

Deliver:

1. EA source and supporting modules.
2. Clearly labelled example configurations.
3. Installation and operating instructions.
4. Exact strategy specification and parameter glossary.
5. CSV schemas and sample input formats.
6. Test results with a clear passed/failed/not-run distinction.
7. Known limitations.
8. A manual backtest and forward-demo checklist.

Proceed with implementation and verification. Finish by explaining what was built, what was actually compiled and tested, and what still requires MT5 verification.

Keep real-account trading disabled.