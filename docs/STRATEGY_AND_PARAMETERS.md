# Biltech AMD ordinary-FVG research specification

Rule version: **1.0.0**. EA: `Biltech_AMD_FVG_Research`.

This implements a research hypothesis: accumulation, failed breakout, reclaim, then an ordinary Fair Value Gap pullback. It has no demonstrated profitability. No trade count, expectancy, drawdown, or other strategy performance statistic is asserted by this specification. Compilation, deterministic fixtures, Strategy Tester runs, and forward-demo observations are different forms of evidence; consult the verification matrix for their actual status.

Version 1 handles long and short signals on the attached chart symbol. It excludes inverse FVGs, market-entry substitutions, grid trading, martingale, averaging down, pyramiding, AI trade decisions, automatic optimisation, breakeven moves, trailing stops, and partial profit-taking. Protective emergency closes may themselves fill partially because execution is controlled by the broker.

## Observation and processing contract

The execution timeframe is explicit, default M5. A candle's MQL5 `time` is its **opening** time. The implementation supplies completed candles to the signal engine in chronological order, oldest to newest. Signal knowledge time is the newest completed candle's open plus `PeriodSeconds(ExecutionTimeframe)`; the journal separately records the observed tick time that actually detected the event. Range boxes may extend backward across their constituent candles, but their detection labels identify when the EA observed the qualification.

The first observed tick after attachment or restart marks the currently completed candle as already handled. It does not trade that candle retrospectively. Thereafter, the EA processes each new completed candle at most once. If the latest completed candle is not exactly one execution period after the last handled candle, the EA skips the gap, invalidates an unfinished setup, and records that it did not replay missed bars. A blocked completed candle is also marked handled; lifting a session/news/risk filter does not replay it. Missing history or invalid completed-bar ATR invalidates that observation.

New setup processing requires the observed tick and the completed candle's nominal close to be inside the entry session. The lookback may contain pre-session candles; those candles can define the range observed during the session. Sweeps, confirmations, and submission must occur in session. News-blocked completed candles discard an unfinished setup as an engineering convention.

All broker order requests, EA-managed cancellations, risk checks, and session-end closes are driven by **observed chart-symbol ticks**. There is no timer-based guarantee of action at a clock boundary. `OnTradeTransaction` sets a reconciliation flag; the next observed tick rebuilds execution facts from account order/deal history. Duplicate callbacks do not increment counters. This accommodates the documented lack of guaranteed transaction arrival order. [MQL5 OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction)

## Signal rules

### Accumulation

While idle, the newest `RangeLookbackBars` completed candles define:

`RangeHigh = maximum high`, `RangeLow = minimum low`, `RangeWidth = RangeHigh - RangeLow`.

The first observation satisfying `0 < RangeWidth <= MaxRangeATR × ATR` freezes the range and qualification time. ATR is the native `iATR` value from the most recently completed candle. A setup ID is that qualification knowledge timestamp; symbol, timeframe, configuration ID, and session ID provide its journal context.

Only a later completed candle can sweep the range. The qualification candle is never recycled as its own breakout. There is one active range. An unswept range expires at the close of the `RangeExpiryBars`-th subsequent candle if that candle does not sweep; a sweep on that last permitted candle remains eligible. Session end invalidates an unfinished range. The default 20-bar expiry is an engineering convention, not an established optimum.

### Sweep and reclaim

A downside sweep is a low at least one symbol trade tick below `RangeLow`; it proposes a long. An upside sweep is a high at least one tick above `RangeHigh`; it proposes a short. A small tick-scaled floating-point tolerance is used in comparisons. Wicks and bodies both qualify.

The first sweep candle counts as candle one of `ReclaimDeadlineBars`. A reclaim requires a completed candle's close to be **strictly** between the frozen boundaries. A sweep and reclaim on the same candle is valid. The most adverse low/high through the reclaim sequence is tracked as the sweep extreme.

The setup is invalidated if the inclusive deadline ends without reclaim, if either candle breaches both range boundaries, or if the opposite range boundary is swept before FVG confirmation. Tick ordering inside a double-sweep candle is not resolved; it is rejected. After reclaim, a later completed candle extending beyond the recorded sweep extreme invalidates the setup before FVG evaluation. The reclaim candle may extend the extreme because it still belongs to the sweep/reclaim sequence.

### Ordinary FVG confirmation

Three consecutive completed candles are A, B, C in chronological order.

| Rule | Bullish / long | Bearish / short |
| --- | --- | --- |
| Gap | `Low(C) > High(A)` | `High(C) < Low(A)` |
| Zone | `High(A)` through `Low(C)` | `High(C)` through `Low(A)` |
| Displacement close | `Close(C) > High(B)` | `Close(C) < Low(B)` |

C's close must be strictly inside the frozen accumulation range. C must close on or after reclaim, and B's opening time must be no earlier than the first sweep candle's opening time. Thus A may precede the sweep, while B cannot. The FVG must match the proposed reversal, have width at least one trade tick, and, when enabled, have width at least `MinFVG_ATR × completed-bar ATR at C`.

The reclaim candle counts as candle one of `FVGDeadlineBars`; the last permitted candle is evaluated before an absent FVG causes invalidation. The first qualifying FVG is used. An earlier gap that fails the timing conditions is never moved to a later timestamp or retrospectively entered.

## Price plan, submission, and lifetime

The nominal entry is the confirmed FVG midpoint. A long uses a Buy Limit; a short uses a Sell Limit. The only submission attempt occurs in the tick handler that first detects C's completed confirmation. A midpoint touch before that confirmation is not an entry.

The plan uses the spread from that observed tick:

`Buffer = max(2 × tick size, ask - bid, 0.10 × ATR at confirmation)`.

For a long, SL is the sweep low minus buffer; for a short, SL is the sweep high plus buffer. The midpoint is rounded toward the passive side: down for buys, up for sells. SL is rounded away from entry. A half-tick midpoint can therefore move by at most half a tick. Distance is recalculated after rounding. TP is two actual normalized stop distances from entry, rounded outward. It must remain no higher than `RangeHigh` for a long, or no lower than `RangeLow` for a short. The normalized price reward/risk must be at least 2; this is a price ratio, not a promise of net 2R after costs.

Entry, SL, TP, FVG zone, sweep extreme, ATR, volume, and monetary-risk plan are then frozen. The EA rejects a marketable/missed midpoint, unsupported initial limit/SL/TP, disallowed instrument direction, insufficient reward space, spread/risk/margin failures, or insufficient remaining lifetime. It conservatively checks entry-to-market and protective distances against the greater of broker stop and freeze levels, then uses `OrderCheck`. It does not shift strategy prices to force acceptance. Trade tick size, point size, allowed order/filling/expiration modes, and volume constraints come from the actual attached instrument. A similarly named future and CFD are not assumed interchangeable. [MQL5 symbol properties](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants)

The one-attempt marker is persisted **before** submission checks. Rejection, uncertain response, expiry, cancellation, completion, or VisualOnly processing consumes that range's attempt. A later bar may qualify a new range under a new observation ID. An entry request is never automatically retried or replaced by a market order. The initial request includes both SL and TP.

Pending entry lifetime ends at the earliest of:

1. C's confirmation time plus three execution-timeframe periods;
2. the current session end;
3. the next selected HIGH-impact news exclusion start, or the declared calendar coverage end.

Exact broker-side specified expiration is used if available. Otherwise GTC is used with EA-side management; instruments supporting neither are rejected. EA-side cancellation also responds to a tick beyond the frozen sweep extreme, daily lock, unusable time/risk/persistence, or an unmapped order after restart. The extreme check uses the instrument's chart price convention: Last for Last-built bars, otherwise Bid.

Cancellation happens after a tick is observed and can race with execution. GTC orders can remain working while the EA is disconnected. Submission-time spread filtering cannot guarantee the spread at a later fill. Existing positions retain their original SL/TP during news exclusions. At session end or daily lock, the EA attempts to cancel its pending entries and close its positions; it also attempts an emergency close if an owned position is observed without SL or TP. The close request has a fixed 20-point deviation allowance; this is not the risk-model slippage input.

Each cancel action and close action is limited to three management attempts per ticket, at least five observed server-time seconds apart, during that EA run. Cancel and close counters are separate. Partial closes may leave residual exposure after the bound is exhausted; the diagnostic calls for inspection. No infinite retry loop or discretionary stop adjustment is implemented.

## Monetary risk, daily limits, and ownership

The risk budget is `current account equity × RiskPercent / 100`. The EA uses `OrderCalcProfit` at a valid reference volume to estimate account-currency loss between normalized entry and SL. It adds the account-currency value of `RoundTripSlippageTicks` adverse trade ticks beyond SL, plus `RoundTripCommissionPerLot` per lot. These are explicit modeling allowances, not broker fee forecasts. Zero inputs omit unknown costs. [MQL5 OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit)

Volume is rounded down to the symbol step, capped at its maximum, and checked against its minimum and the original monetary budget. It never rounds up to minimum volume. Margin is estimated with `OrderCalcMargin`, compared with available free margin, and checked again through the order request. `OrderCalcMargin` itself estimates the proposed order without incorporating existing orders/positions. [MQL5 OrderCalcMargin](https://www.mql5.com/en/docs/trading/ordercalcmargin)

The ledger groups fills by authoritative position identifier. A partially filled entry counts as one filled trade, rather than one trade per deal callback. Session fills are attributed to the position's first entry and its session-start date. A fully closed net losing position whose final exit is today contributes one losing trade for today. The net result includes available commission, swap, fee, and profit records; an EA-owned position's manually executed exit is included in its performance without authorizing the EA to manage unrelated manual entries.

The trading day begins at midnight in `SessionTimezone`, independently of a midnight-crossing entry session. The ledger uses a persisted day-start equity and daily lock when available. If there is no day record, it can reconstruct the baseline as current balance plus credit minus all account cash results since midnight **only when account history and current positions indicate the account was flat at midnight**. A current position lacking entry history invalidates the ledger. A corrupt existing day record is not silently replaced. Broker history availability remains an operational dependency; selecting history successfully cannot prove that a broker has retained every historical record.

When flat-midnight reconstruction is unavailable, `DayStartEquityOverrideDate` and `DayStartEquityOverride` provide an explicitly dated baseline. The operator must establish the actual equity at that midnight. The implemented daily measure is EA-realized net since midnight plus available current EA floating profit and swap. If an EA position is carried across midnight despite the session-end rule, this uses its whole current floating value rather than an independently reconstructed midnight mark-to-market difference; a dated equity override does not reconstruct that missing price history. Treat such a day as requiring manual reconciliation rather than claiming exact incremental daily performance.

New entries stop after `MaxFilledTradesPerSession`, after `MaxLosingTradesPerDay`, or when EA daily net plus floating reaches `-day-start equity × DailyLossPercent / 100`. The daily lock is sticky until the next session-local trading day. Floating P&L is observed each tick; history is reconciled on transaction notification or at least once per new observed server-time second. At a daily lock, cancellation/close requests are subject to permissions, quotes, connection, broker acceptance, and the bounded retry policy. Gaps, slippage, disconnection, and failed closes can make actual losses exceed any configured threshold.

One EA-owned position or pending entry is allowed for the strategy identity across symbols. Identity is account login, account-server hash, and `StrategyMagic`. An exclusive `FILE_COMMON` lock is retained for the lifetime of the running instance. Another instance with that identity in the same Windows common-files environment is refused, including another terminal. Different magic numbers are different risk identities and do not share these limits. There is no distributed atomic lock across separate machines, VPS hosts, or disconnected common-files environments; do not run one identity there concurrently. Tester files are isolated to the test agent instead of live common files. [MQL5 FileOpen and common-file sandbox](https://www.mql5.com/en/docs/files/fileopen)

On a netting account, any existing position or working order on the symbol blocks new entries, because ownership could mix. Ownership requires the strategy magic plus an original entry/order `BAMD:` comment. An untagged same-magic collision disables entries and is never cancelled or closed as if it were owned. Close requests additionally require history proving exclusive EA entry ownership. Manual trades and another EA's orders/positions are not intentionally altered or closed.

## Historical clocks and sessions

`BrokerStandardUTCOffsetMinutes` is mandatory even in VisualOnly mode. The default **9999 is an invalid unset sentinel**. Supply the broker's documented historical **standard** UTC offset, from -720 to +840 minutes, and its actual schedule. The EA never infers historical broker time from today's server offset, computer timezone, `TimeGMT`, or the session timezone.

| Mode | Standard offset | DST convention |
| --- | --- | --- |
| `B_NEW_YORK` / 0 | UTC-300 minutes | Second Sunday in March at 02:00 standard local; first Sunday in November at 02:00 daylight local. |
| `B_LONDON` / 1 | UTC+0 | Last Sunday in March and October, both transitions at 01:00 UTC. |
| `B_BROKER_SERVER` / 2 | Explicit broker offset | The explicitly selected broker schedule. |

The broker schedules are `B_FIXED` / 0 (no DST), `B_US_DST` / 1 (the US local-transition convention applied to the supplied standard offset), and `B_EU_DST` / 2 (the European 01:00 UTC transition convention). A broker following another schedule needs a separate reviewed implementation; choosing a similar label is not evidence that its timestamps match.

Supported rule years are **2007 through 2099**. Dates outside that range, and conversions crossing an unsupported boundary, fail closed. Historical US rules before 2007 are deliberately unsupported. Applying these conventions through 2099 is a rule extrapolation, not a prediction that future laws remain unchanged. The present US/Eastern convention is supported by [NIST's local-time FAQ](https://www.nist.gov/pml/time-and-frequency-division/local-time-faqs); the London convention is supported by [GOV.UK clock-change guidance](https://www.gov.uk/when-do-the-clocks-change).

Broker wall-clock conversion tries both standard and daylight offsets and accepts exactly one roundtrip match. Nonexistent spring times and repeated autumn times are rejected. UTC-to-broker conversion also requires a unique reverse mapping, so an ambiguous broker timestamp is not silently assigned one of two instants. Session start/end and day-midnight boundaries must also convert safely. Named local clocks may repeat during autumn; a session endpoint inside that overlap is rejected rather than guessed.

Session start is inclusive and end is exclusive. Equal start/end is invalid. If end is earlier than start, the session crosses midnight, and weekdays are tested on the **session start date**. A Friday session may therefore continue into early Saturday. Session ID is the local start date `YYYYMMDD`; outside an entry window it identifies the most recently begun candidate session. Day ID is the current local calendar date. Chart status shows the observed broker clock and converted session-local clock.

The default research window is 09:45–11:00 New York, Monday–Friday. The alternative FX research convention is 08:00–10:00 London, Monday–Friday. Neither window is represented as profitable.

## Optional calendar behavior

The reproducible news input is a terminal/test-agent file, not a live economic-calendar inference. Enabled filtering requires a valid UTF-8 CSV, explicitly selected uppercase three-letter currencies, and explicit UTC coverage `[start, end)`. All rows are validated, including unselected currencies and lower-impact rows. Selected HIGH events block their configured interval with both event-window endpoints included. Overlapping windows are merged. MEDIUM and LOW rows remain valid input but do not create exclusions.

Coverage is the operator's declaration, not a conclusion inferred from the first and last event. A timestamp outside it blocks entries and working entries expire at its end. A header-only zero-event file can be valid only with an explicit coverage declaration; it does not prove completeness. Missing/invalid required files prevent initialization. See the separate CSV schema documentation for the accepted timestamp and quoting formats.

## State, persistence, and research records

The main lifecycle is `IDLE → RANGE_READY → SWEPT → RECLAIMED → FVG_CONFIRMED → ORDER_PENDING → POSITION_OPEN → COMPLETED`, with `INVALIDATED` exits whenever a rule fails. Several transitions can occur on one completed candle, such as sweep plus reclaim, while each transition remains separately recorded. VisualOnly finishes a valid plan without an order request.

The active snapshot and per-order plans are flushed and replaced through temporary files. The one-attempt marker is durable before an order request. On restart, unsent `RANGE_READY` through `FVG_CONFIRMED` setups are abandoned; existing owned orders/positions are reconciled from history and saved plans. A request response is not treated as proof of a fill. Unmapped working orders are candidates for cancellation and disable new entries; unknown historical monetary risk is never invented. Deal and closed-position journal receipts support idempotent reconstruction after duplicate notifications or restart.

Range, sweep, reclaim, FVG, entry, SL, TP, current state, and reason remain on the chart, subject to `ChartHistoryLimit`. Failed setups remain until that history bound prunes the oldest setup. The journal contains event and observation timestamps, frozen prices, rejection reasons, planned risk, order/position/deal identifiers, available actual costs and execution prices. Fill spread is an observed notification-time sample when available; zero means unknown, not proof of a zero spread. Closed-trade `net_R` is net available position result divided by initial planned monetary risk, including configured sizing allowances in that denominator. Configuration and rule version are recorded. Sampled account equity output is distinct from an exact Strategy Tester equity curve.

## Complete input glossary

There are **38 EA inputs**, excluding the visual group labels. Defaults below are source defaults, not recommended broker-specific optimisations.

### Safety and strategy identity

| Input | Default | Meaning / validation |
| --- | --- | --- |
| `VisualOnly` | `true` | Disables all execution-layer order operations, including entry, cancel, and close requests. Signals and valid plans can still be displayed. Do not rely on a VisualOnly instance to manage existing live exposure. |
| `AllowDemoTrading` | `false` | Required for demo/contest account order operations when VisualOnly is false and the EA is outside Strategy Tester. Terminal, EA, and account permissions must also allow trading. |
| `AllowRealAccountTrading` | `false` | Real-account permission gate; keep false for this research delivery. Strategy Tester uses simulated orders when VisualOnly is false and tester permissions are available. |
| `StrategyMagic` | `2601025001` | Positive ownership/risk identity no greater than signed `LONG_MAX`. Shared across this strategy's symbols on the same account/server, with one permitted active instance per identity. Changing it creates a separate identity and risk ledger. |

### Completed-candle signal

| Input | Default | Meaning / validation |
| --- | --- | --- |
| `ExecutionTimeframe` | `PERIOD_M5` | Signal candles and the three-period pending lifetime. Must be an explicit fixed-duration MT5 timeframe with positive `PeriodSeconds`; `PERIOD_CURRENT` and variable-length `PERIOD_MN1` are refused. M5 is the intended default research cadence. |
| `RangeLookbackBars` | `20` | Number of completed candles in the candidate range; at least 3. |
| `ATRPeriod` | `14` | Native `iATR` period; at least 2. The most recently completed value is used. |
| `MaxRangeATR` | `3.0` | Positive maximum range width as a multiple of completed ATR. |
| `RangeExpiryBars` | `20` | At least 1. Subsequent candles permitted for an unswept range; the last candle may still sweep. |
| `ReclaimDeadlineBars` | `3` | At least 1. Inclusive sweep-to-reclaim window, first sweep candle counting as one. |
| `FVGDeadlineBars` | `3` | At least 1. Inclusive reclaim-to-confirmation window, reclaim candle counting as one. |
| `MinFVG_ATR` | `0.0` | Nonnegative optional minimum FVG width / confirmation ATR. Zero disables this additional width filter; one-tick minimum remains. |

### Risk and cost allowances

| Input | Default | Meaning / validation |
| --- | --- | --- |
| `RiskPercent` | `0.25` | Percentage of current equity budgeted per attempted trade, including explicit commission/slippage sizing allowances. Must be greater than 0 and at most 100. |
| `MaxFilledTradesPerSession` | `2` | At least 1. Maximum distinct filled positions attributed to the entry session; partial entry deals do not multiply this count. |
| `MaxLosingTradesPerDay` | `2` | At least 1. Closed net losing positions with final exit in the configured trading day trigger the day lock at this count. |
| `DailyLossPercent` | `0.5` | Positive daily EA net-plus-floating loss threshold as a percentage of persisted day-start account equity; at most 100. It is an action threshold, not a guaranteed loss cap. |
| `RoundTripCommissionPerLot` | `0.0` | Nonnegative account-currency allowance per lot, applied once to sizing for the whole round trip. Zero omits unknown commission in the model; actual available commission is still journaled. |
| `RoundTripSlippageTicks` | `0` | Nonnegative aggregate adverse trade-tick allowance for sizing, modeled as an additional move beyond SL. It does not change the actual stop, limit price, or pending-order execution policy. |
| `MaxSpreadStopFraction` | `0.10` | Positive maximum `live ask-bid / normalized stop distance` at submission. `0.10` means 10%, not 0.10 price units. |
| `MaxAbsoluteSpreadPrice` | `0.0` | Optional nonnegative absolute ask-bid cap in the symbol's price units. Zero disables this cap; the fractional cap remains. |
| `DayStartEquityOverrideDate` | `0` | Valid session-timezone calendar date `YYYYMMDD`, 2007–2099, for the accompanying baseline override. Zero means no override. It and the equity amount must both be zero or both nonzero; it applies only when establishing that dated day's missing record. |
| `DayStartEquityOverride` | `0.0` | Nonnegative account-currency account equity at that dated local midnight, supplied from verified records. Positive amount requires a nonzero date; it does not replace a valid persisted day record or reconstruct carried-position midnight floating P&L. |

### Session and historical broker clock

| Input | Default | Meaning / validation |
| --- | --- | --- |
| `SessionTimezone` | `B_NEW_YORK` / 0 | New York / 0, London / 1, or explicit broker server / 2. Determines session clocks, weekdays, and trading-day midnight. |
| `SessionStart` | `"09:45"` | Exact `HH:MM`, 00:00–23:59, inclusive start in the chosen session timezone. |
| `SessionEnd` | `"11:00"` | Exact `HH:MM`, exclusive end. Must differ from start; earlier clock time creates a midnight crossing. |
| `WeekdaysOnly` | `true` | Admit only sessions whose local start date is Monday–Friday. Set false only for a deliberately different research convention. |
| `BrokerStandardUTCOffsetMinutes` | `9999` | Required standard broker offset from UTC in minutes, -720..840. **9999 is invalid** and intentionally makes untouched defaults fail initialization. This value is independent of the session timezone. |
| `BrokerDSTSchedule` | `B_FIXED` / 0 | Fixed / 0, US local 02:00 transition convention / 1, or EU 01:00 UTC convention / 2. Must match documented historical broker behavior. |

### Reproducible UTC calendar

| Input | Default | Meaning / validation |
| --- | --- | --- |
| `UseNewsFilter` | `false` | Enables required calendar validation, coverage gates, selected-HIGH event exclusions, and pending-entry exclusion-boundary management. |
| `NewsCSVFile` | `"news_example_utc.csv"` | Nonempty sandbox-relative UTF-8 calendar path when filtering is enabled. Provision it separately in the terminal/test-agent Files location. |
| `NewsCurrencies` | `"USD"` | Explicit comma-separated uppercase three-letter currencies; spaces surrounding tokens are trimmed. Empty, invalid, and duplicate tokens are refused when enabled. Symbol suffixes do not drive inference. |
| `NewsMinutesBefore` | `15` | Inclusive minutes before each selected HIGH event; integer 0..10080. |
| `NewsMinutesAfter` | `15` | Inclusive minutes after each selected HIGH event; integer 0..10080. |
| `NewsCoverageStartUTC` | `""` | Required when enabled. Explicit UTC coverage start, inclusive, in the strict documented timestamp format and supported years. |
| `NewsCoverageEndUTC` | `""` | Required when enabled. Exclusive UTC end, later than start; no historical completeness is inferred from event rows. The default empty strings are invalid if the filter is enabled. |

### Research output

| Input | Default | Meaning / validation |
| --- | --- | --- |
| `ChartHistoryLimit` | `100` | At least 1. Maximum setup IDs retained by the running chart visual manager before oldest drawings are pruned. Does not remove journal history. |
| `ResetFilesAtTesterStart` | `true` | On tester initialization only, remove this isolated strategy-identity prefix's prior CSV snapshots, plans, journals, day records, and equity samples. Set false for a deliberate tester persistence/restart experiment. Live common files are not reset by this option. |
| `ResearchLabel` | `"unclassified"` | Free-text label persisted in the configuration, for example development versus untouched validation. It does not select/optimise parameters or itself create a statistical split. |

Automatic Strategy Tester optimisation mode is refused by initialization. The fixed 2R target, two-tick/10%-ATR buffer coefficients, three-period pending lifetime, management retry bound, and 20-point close deviation are implementation constants rather than additional inputs. Revisions to them require a rule-version review and fresh verification.
