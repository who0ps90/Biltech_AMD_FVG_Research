# Verification results — 2026-10-25

This records engineering checks actually performed during implementation. No MT5 market test, demo connection, trade, or profitability result is represented here.

| Check | Passed | Failed | Not run | Evidence |
|---|---:|---:|---:|---|
| Complete EA native compilation | 1 | 0 | 0 | MetaEditor 5.0.0.6281; `compile_ea.log`: **0 errors, 0 warnings**, X64 Regular |
| Complete native fixture script compilation | 1 | 0 | 0 | Same compiler; `compile_fixtures.log`: **0 errors, 0 warnings**, X64 Regular |
| Offline report calculation / CSV / CLI tests | 16 | 0 | 0 | Node test runner, `report_research.test.mjs`; synthetic arithmetic/file fixtures only |
| Static source-contract checks | 12 | 0 | 0 | Node test runner, `source_contract.test.mjs`; these inspect source, inputs, schemas and call placement, not MQL runtime behavior |
| Native MQL fixture runtime | 0 | 0 | 4 suites | Runner compiled; **not executed**. Approximately 199 assertion sites supplied across signal, time/news, risk/execution/storage, and journal suites. A compiled assertion is not a passed assertion. |
| MT5 Strategy Tester on broker historical ticks | 0 | 0 | 1 | Installed terminal/test agent was not launched; no isolated broker-free execution environment or intended instrument/history configuration was established |
| Forward-demo execution | 0 | 0 | 1 | No brokerage connection or order placement performed |
| Real-account execution | 0 | 0 | 1 | Disabled in defaults and every example; never enabled or run |

Commands actually completed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/compile.ps1
node --test tests/report_research.test.mjs tests/source_contract.test.mjs
```

Final Node summary: **28 tests, 28 pass, 0 fail, 0 cancelled, 0 skipped**. Final compiler summaries: **0 errors, 0 warnings** for each source target. Supplied `.ex5` binaries were regenerated from the reviewed source in this workspace. Native compilation does not establish that initialization, file-lock behavior, broker preflight, order lifetime, transaction reconciliation, risk flattening, or fixtures work correctly in MT5 runtime.

Native entry points: `BRunSignalTests()`, `BRunTimeNewsTests()`, `BRunRiskExecutionTests()`, and `BRunJournalTests()`. All are invoked by `MQL5/Scripts/Biltech_AMD_Tests.mq5`. They do not send orders; their local-file fixtures use isolated test names and clean up their exact files. Run them manually in an isolated/disconnected MT5 terminal and save results before claiming a native pass.

The requested market statistics — trade count, win rate, average win/loss R, expectancy, profit factor, maximum equity drawdown, longest losing streak, instrument/session breakdown and development-versus-validation results — remain **unavailable**, because no actual market test was run. Synthetic reporter fixture values are tests of calculations, never trading results.

Use `docs/VERIFICATION_MATRIX.md` for scenario coverage and `docs/MANUAL_CHECKLIST.md` for outstanding MT5 work. Keep real-account permission false.
