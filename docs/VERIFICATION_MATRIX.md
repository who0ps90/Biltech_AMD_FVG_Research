# Verification and research evidence

This project is an implementation for research. No broker historical backtest, forward-demo run, profitability result, or real-order execution is asserted by this document. Source fixtures exercise deterministic logic; they do not establish broker execution behavior. A successful compilation alone is not a successful fixture run.

## Evidence actually obtained

| Check | Result | Evidence and limit |
| --- | --- | --- |
| Complete EA and fixture script compilation | **PASSED: 0 errors / 0 warnings each** | MetaEditor 5.0.0.6281; fresh logs `tests/compile_ea.log` and `tests/compile_fixtures.log`. Native fixture assertions were not executed. |
| Offline journal-report calculations | **PASSED: 16 tests** | `node --test tests/report_research.test.mjs`; synthetic report fixtures only. Tests exercise CSV decoding, position aggregates, risk-normalized results, duplicate closures, chronology, drawdown snapshots, input rejection, footer integrity, and the CLI file interface. |
| Static source contracts | **PASSED: 12 tests** | `tests/source_contract.test.mjs`; static inspection of safety defaults, ownership paths, timing call sites, schemas, persistence and examples. Does not establish runtime behavior. |
| Native signal/time/news/risk/execution fixture execution in MT5 | **NOT RUN** | Native fixture sources are provided for `MQL5/Scripts/Biltech_AMD_Tests.mq5`. Do not infer a pass from their presence or from compilation. |
| Broker Strategy Tester, real ticks | **NOT RUN** | No historical broker dataset or Strategy Tester report was supplied or generated. |
| Forward demo execution | **NOT RUN** | No connection, order placement, or live/demo trading was authorized or performed during implementation. |
| Real-account trading | **NOT RUN / DISABLED BY DEFAULT** | Keep real-account permission false. |

The delivery summary/compile log records native compiler checks. Compiler diagnostics and fixture execution are separate evidence. Fixture modules are `MQL5/Include/BiltechAMD/SignalTests.mqh`, `TimeNewsTests.mqh`, `RiskExecutionTests.mqh` and `JournalTests.mqh`; entry points are `BRunSignalTests()`, `BRunTimeNewsTests()`, `BRunRiskExecutionTests()` and `BRunJournalTests()`.

## Requested scenario coverage

“Native fixture” below means a deterministic MQL assertion is provided. Its execution status remains **NOT RUN** until the fixture script is run and its log retained. Broker/manual rows require observations in the intended broker environment; report-tool tests do not cover them.

| Requested scenario | Deterministic coverage | Required MT5 / broker evidence, currently NOT RUN |
| --- | --- | --- |
| Valid long and valid short | Native signal fixtures: range → sweep → reclaim → qualifying directional FVG. | Visual-mode timestamps and actual broker limit admission/fill for both sides. |
| Same-candle sweep/reclaim | Native signal fixtures: one completed bar breaches one boundary and closes strictly inside. | Visual-mode comparison with candle closes. |
| Genuine breakout without reclaim | Native signal fixtures: reclaim deadline invalidates the setup. | Visual-mode rejection and journal transition. |
| Ambiguous double sweep | Native signal fixtures: one bar crosses both boundaries; opposite breaches on separate bars. | Confirm no order attempt on these ranges. No intrabar ordering is guessed. |
| FVG before permitted confirmation | Native signal fixtures: premature FVG and B-before-sweep rejection; confirmation deadline. | Inspect A/B/C closed-bar times in visuals/journal. |
| Midpoint touched before confirmation | Native signal fixtures preserve confirmation timing; a past midpoint touch does not enter a position. | Confirm order submission only on the first observed tick after C closes; a marketable limit is rejected. |
| Post-reclaim extension / opposite breach | Native signal fixtures reject a new extreme and opposing range breach. | Pending-order cancellation timing remains tick-observed and can race with fills. |
| Unfilled entry expiry | Native risk/execution fixtures cover the expiry predicate. | Wait three execution periods, test session/news/extreme cancellation, broker-supported expiration, disconnection and reconnect. |
| Insufficient reward space | Native risk/execution fixtures cover target-room rejection and tick normalization. | Use a setup whose frozen 2R target exceeds the opposing boundary and retain the rejection record. |
| Excessive spread | Native risk/execution fixtures cover spread boundaries. | Use intended broker symbol; compare bid/ask, planned stop distance and absolute cap. A later pending fill can have a different spread. |
| Minimum-volume risk violation | Native risk/execution fixtures cover volume rounding down and minimum risk-budget rejection. | Verify with the actual contract/account currency that minimum lot risk plus configured allowances exceeds the budget; no volume rounding upward. |
| DST and historical broker conversion | Native time fixtures cover New York/London and configured broker-offset schedules. | Compare session admission around transitions against broker history; the present server offset is not historical evidence. |
| Cross-midnight session and date rollover | Native time fixtures cover session boundaries and date attribution. | Observe counters/day-start equity around the configured local trading-day boundary. |
| Daily lockout | Native risk/execution fixtures cover pure threshold decisions. History reconciliation and account actions require runtime evidence. | Real-tick tester or demo: two session fills, two daily losers, net realised plus floating drawdown threshold; verify pending cancellation, position close attempt and lock until the next day. |
| Restart recovery / shared strategy identity | Native risk/execution fixtures cover snapshot storage and duplicate journal receipts. History reconciliation and inter-instance ownership require runtime evidence. | Restart with an active order and position; start two instances with the same identity; verify no duplicate order and shared exposure/counters. |
| Order rejection / unsupported expiration | Native risk/execution fixtures cover accepted-status decisions. Actual broker responses are not mocked as execution evidence. | Force a broker rejection/unsupported expiration in a controlled tester/demo case; verify one range attempt, bounded handling and unchanged strategy prices. |
| Partial fill / duplicate transaction | Execution reconciliation in source; report tests deduplicate final aggregate rows only. | Controlled execution evidence is required for authoritative `OnTradeTransaction` behavior, cumulative volume, initial-risk denominator, final-close aggregation and duplicate notifications. |
| Missing history, ATR, calendar or time conversion | Native invalid-input/time/news fixtures where applicable; entry guards in EA source. | Remove/limit a required data source and retain clear fail-closed diagnostics. |
| Scheduled news boundaries and CSV coverage | Native time/news fixtures cover explicit currencies/UTC coverage, irrelevant malformed rows, missing files, zero-event coverage, quoted CSV, overlapping exclusions and exact boundaries. | Supply the research calendar, verify coverage completeness separately, and observe pending cancellation on the first available tick at the boundary. |
| No ownership mixing | EA ownership checks in source. | On netting and hedging demo accounts, add another strategy/manual exposure and verify it is neither modified nor adopted. |

The first qualifying range and first valid FVG are frozen, ranges expire after the specified subsequent-bar count, and repeated completed-bar calls are covered by the native signal fixtures. These are logic checks, not claims that a broker has accepted or executed an order.

## Running the offline report tool

Use Node.js, from the project directory:

```powershell
node --test tests/report_research.test.mjs
node tools/report_research.mjs --journal "C:\path\actual-development-journal.csv" --label development --account-currency USD --output "development-report.json"
node tools/report_research.mjs --journal "C:\path\actual-validation-journal.csv" --equity "C:\path\actual-validation-equity.csv" --label validation --account-currency USD --output "validation-report.json"
```

Repeat `--journal` for rotated files from the **same account, currency and research partition**. Retain input hashes and the tester report with each research run. Keep development and untouched validation runs in separate invocations. The label records the researcher's designation; the tool cannot establish that a validation set remained untouched. Different configurations and rule versions are listed in the report, so inspect them before interpreting an aggregate.

The tool accepts comma, semicolon or tab delimiters, detects common MQL exports, and decodes UTF-8 or BOM-marked UTF-16. Use `--delimiter comma`, `semicolon`, or `tab` to override detection. Numeric cells use a decimal point; malformed rows fail the report instead of being silently discarded. No external packages, prices, strategy simulation, broker connection or order APIs are used.

Only `event=TRADE_CLOSED` contributes trade statistics. Required columns are `event,rule_version,config_id,symbol,session_id,position_id,event_time,planned_risk_money,net_pnl,net_R`. Other journal columns remain available for audit. Each closure must represent one **fully closed position**, with aggregate net P&L including entry/exit costs and its original planned monetary risk. The reporter does not add `DEAL` records to a closure again. Exact repeated aggregates are counted once; conflicting aggregates for a symbol/position ID stop the report. Account identity cannot be inferred, so do not merge separate accounts.

Win rate is wins divided by all closed positions, including flat results. Average net loss in R is negative. Expectancy is the arithmetic mean of per-position net R, recomputed from net P&L / initial planned risk and checked against recorded `net_R`. Profit factor uses sum of positive net position P&L / absolute sum of negative net position P&L. When no losing trades exist, numeric profit factor is `null` with an explicit status. No-trade rates and expectancy are `null`. A flat result resets a losing streak.

Trades are ordered by final close `event_time`; ties retain input order. Accepted timestamps are `YYYY.MM.DD HH:MM:SS`, `YYYY-MM-DD HH:MM:SS`, or ISO 8601 with seconds and explicit UTC/offset. Wall-clock broker times are not assigned an invented UTC offset. Repeated broker times during DST fallback can make losing-streak order ambiguous; preserve original append order and inspect such records. Mixed wall-clock and explicit-offset timestamp bases are rejected.

`session_id` must identify the entry session of the original position. Do not reassign a trade to the session or trading day in progress when its final close arrives. Results are supplied overall, by exact broker instrument symbol and by `session_id`.

## Account equity evidence

Without `--equity`, maximum equity drawdown is explicitly **not available**. A closed-trade balance curve is not substituted for account equity. Optional equity input has the form:

```csv
time,equity
2026.01.05 15:00:00,10000.00
2026.01.05 15:00:01,9999.00
```

Those values illustrate the input format only; they are not test results. Use genuine account snapshots covering the intended report period. The report calculates the largest observed peak-to-trough money decline and percentage decline; the two maxima can occur at different times. This is **sampled account equity drawdown**, which may miss intraperiod extremes. It includes every account position and cashflow and is not automatically an EA-only or cashflow-adjusted statistic. The EA trade journal alone does not establish adequate equity sampling or a tick-accurate maximum drawdown.

## Actual MT5 verification checklist

1. Keep real-account permission false. Install source and modules, compile the EA and native test script, retain compiler logs, and run the native fixture script; record every pass/fail and terminal build.
2. Select the exact intended broker instrument. Save its contract specification, tick size/value, volume step, stop/freeze levels, margin model, expiration capabilities, account currency and netting/hedging mode. A similarly named CFD/future is not interchangeable.
3. Pin the rule version, input file, broker UTC-offset/DST configuration, news CSV and history interval. Use **Every tick based on real ticks** where available, record the actual modelling mode and data gaps, and inspect every requested scenario above.
4. Retain the tester report, journal, terminal logs, actual equity samples and screenshots of representative valid/rejected setups. Confirm initial SL/TP, first-tick timing, actual fees/slippage and full-position aggregation.
5. Run development and untouched validation periods separately with the frozen research configuration. Do not tune settings on validation results or present synthetic fixture outcomes as market performance.
6. Complete a forward-demo run with explicit demo permission only after reviewing tester evidence. Include restart/disconnection, session/news boundaries, daily risk actions and ownership isolation. Record broker races and failures, not only fills.

No performance statistics should be published until actual test inputs and outputs exist. None of the synthetic reporter values are evidence of strategy profitability.
