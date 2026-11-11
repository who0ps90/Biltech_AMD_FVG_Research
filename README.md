# Biltech_AMD_FVG_Research v1.0.0

Native MT5 research EA for a frozen accumulation range → failed breakout → reclaim → ordinary FVG limit pullback. Long and short signals use completed candles. The default mode is **visual only**; demo and real-account permissions are **false**. No profitability is asserted and no market backtest results exist for this delivery.

## Delivery and evidence

| Item | Location / status |
|---|---|
| EA source and compiled binary | `MQL5/Experts/Biltech_AMD_FVG_Research.mq5` and `.ex5` |
| Native modules | `MQL5/Include/BiltechAMD/` — signal, clock, calendar, risk, storage, journal, execution, visuals |
| Native fixture runner | `MQL5/Scripts/Biltech_AMD_Tests.mq5` and `.ex5`; **compiled, execution NOT RUN** |
| Native compilation | MetaEditor 5.0.0.6281, **0 errors / 0 warnings**; logs in `tests/compile_ea.log` and `tests/compile_fixtures.log` |
| Offline reporting and source checks | Run results in `tests/TEST_RESULTS.md`; synthetic calculation/source checks are separate from MT5 execution |
| Strategy Tester / forward demo | **NOT RUN**; no terminal or tester agent launched, brokerage connection made, or orders placed during implementation |
| Performance statistics | **Unavailable** until an actual broker test is run |

Start with [the exact strategy and parameter glossary](docs/STRATEGY_AND_PARAMETERS.md), [example settings](config/README.md), [CSV formats](docs/CSV_SCHEMAS.md), [verification matrix](docs/VERIFICATION_MATRIX.md), and [manual backtest/demo checklist](docs/MANUAL_CHECKLIST.md). Material limits are listed in [KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md).

## Install and compile

1. In MT5 use **File → Open Data Folder**. Copy the contents of this project's `MQL5` directory into that data folder's `MQL5`, preserving the `Experts`, `Include/BiltechAMD`, and `Scripts` structure. These are relative includes; keep the structure intact.
2. Compile `Experts/Biltech_AMD_FVG_Research.mq5` and `Scripts/Biltech_AMD_Tests.mq5` in MetaEditor. The supplied binaries were built locally; compiling against your terminal build is preferred. No DLL, Python, paid API, or third-party MQL library is needed.
3. For a workspace-only compilation, use `powershell -NoProfile -File tools/compile.ps1`. Supply `-MetaEditorPath "C:\path\MetaEditor64.exe"` if auto-detection does not match your installation. This helper compiles sources and never starts MT5 or a test agent.
4. Keep order permissions disabled. Attach the EA to the **exact intended broker instrument**, load a visual-only `.set`, and explicitly set the broker's historical standard UTC offset and documented DST convention. The default `9999` refuses initialization because the clock is unknown.
5. Read the chart diagnostic and Experts log. After attachment, the EA waits for the next completed signal bar. It does not trade signals that closed before attachment or replay missed bars.

The native fixture script only tests logic and local sandbox files; it never sends orders. Run it on a disconnected/isolated terminal chart and retain the `BILTECH NATIVE FIXTURES` summary plus every failed assertion. Its presence and successful compilation do not mean those assertions have passed.

## Operation

Visual mode performs detection, price planning, sizing validation and annotations without sending any order, cancellation or close request. A valid visual setup completes after display. A disabled account permission is an explicit rejected attempt if visual mode is off. Strategy Tester simulated requests are admitted only with `VisualOnly=false`; both account permission inputs can remain false in the tester.

The provided tester configuration has `VisualOnly=false`, `AllowDemoTrading=false` and `AllowRealAccountTrading=false`. It is an example with an explicitly hypothetical fixed-UTC broker clock. Replace that clock with verified broker information. For forward-demo operation, follow the checklist and explicitly enable demo permission in a copied configuration. Keep real permission false.

One pending limit request is allowed per range; its initial request includes both SL and TP. No market entry, inverse FVG, grid, martingale, averaging, pyramiding, trailing stop, breakeven, partial-exit strategy, automatic optimization or AI decision feature is included. Partial broker fills are reconciled; the remaining entry order is cancelled on the next observed tick once any fill is known.

Session end and daily risk rules attempt to cancel owned pending entries and close exclusively EA-owned positions. Operational actions run on observed symbol ticks. Broker-side exact expiry is used when supported; GTC is used with EA cancellation otherwise. **Cancellation can race execution**, including at session/news/expiry/extreme boundaries. Spread is checked at submission and sampled on fill notification when available; it cannot guarantee later fill spread. Protective SL/TP execution and daily loss limits cannot guarantee a maximum loss through gaps, slippage, outages or market closure.

An exclusive common-file handle refuses a second same-identity instance across local terminals. Account history rebuilds counters and identifies positions; duplicate callbacks do not increment counters. The identity is account login + server hash + magic, across symbols. Keep it fixed. Unsigned magic values must fit MQL's signed history magic representation for correct comparisons; use the supplied positive default. Cross-machine atomic coordination is outside this implementation: operate one identity on one Windows machine.

## Data and output files

Operational output uses MT5's shared **Common/Files** sandbox, not this source directory. The identity prefix is `BiltechAMD_<login>_<server-hash>_<magic>`. Strategy Tester output uses its agent-local `MQL5/Files` sandbox. Files include:

- `_journal.csv`: setup transitions, plans, rejected attempts, execution deals, full-position net results, management requests and diagnostics.
- `_equity.csv`: account-equity snapshots on observed ticks, at most once per minute; sampled account drawdown can miss intraminute extremes.
- `_config_<hash>.txt`: full inputs, symbol and rule version; referenced by journal `config_id`.
- `_active.csv`, `_plan_<order>.csv`, `_day_<YYYYMMDD>.csv`: restart state, initial order plan, day equity and persistent daily lock. Do not edit or delete these to bypass limits.
- `.lock`: exclusive file handle; an empty file can remain after exit, but a live open handle prevents another owner.

Export tester files before starting another test: `ResetFilesAtTesterStart=true` deliberately resets this identity's tester-local CSVs for a fresh run. It does not touch operational Common files. Missing/corrupt required persistence blocks new entries. Do not delete an invalid risk record as a workaround; investigate with trading disabled.

If news filtering is enabled, put the verified UTF-8 UTC calendar in the execution terminal/test agent's `MQL5/Files` and set its explicit coverage interval and currencies. The supplied calendar contains **fictional schema fixtures only**. Dynamic filenames are not automatically transferred to remote tester agents; use a local agent with the file installed, or add an appropriate compile-time `tester_file` property for a pinned calendar.

## Reproduce offline checks and research summaries

```powershell
powershell -NoProfile -File tools/compile.ps1
node --test tests/report_research.test.mjs tests/source_contract.test.mjs
node tools/report_research.mjs --journal "C:\exports\actual-journal.csv" --equity "C:\exports\actual-equity.csv" --label development --account-currency USD --output "development-report.json"
```

Use `--label validation` with a separately frozen, untouched validation period. The reporter calculates results only from actual `TRADE_CLOSED` journal aggregates supplied to it. Without an equity file, equity drawdown is explicitly unavailable. The report tool is not a strategy simulator or an MT5 backtest. See the verification document for metric definitions, input constraints and timestamp limitations.
