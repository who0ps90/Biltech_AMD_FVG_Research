# Example settings

These are engineering examples, not recommended or optimized trading parameters. None enables demo or real-account permission. Settings use native UTF-16LE `.set` text.

| File | Purpose | Required adjustment |
|---|---|---|
| `NY_VisualOnly_REQUIRED_CLOCK.set` | Safe default New York 09:45–11:00, M5, visual only | **Will refuse initialization** until the explicit broker standard UTC offset and DST schedule are supplied. `9999` means unknown. |
| `NY_Tester_FIXED_UTC_EXAMPLE.set` | Simulated limit orders in Strategy Tester, New York session | Assumes broker timestamps are UTC with no DST, solely as an example. Replace with the actual tested broker's history convention. `VisualOnly=false`, both account permission inputs remain false. |
| `London_VisualOnly_FIXED_UTC_EXAMPLE.set` | Visual-only alternative FX research window, London 08:00–10:00 | Assumes a fixed UTC broker as an example. Replace with the actual broker convention. |

Load the entire file in EA Inputs. `ExecutionTimeframe=5` means M5. `SessionTimezone`: 0 New York, 1 London, 2 explicit server clock. `BrokerDSTSchedule`: 0 fixed, 1 US transition convention, 2 EU transition convention; the standard UTC offset is in minutes, east positive. For a broker confirmed to use UTC+2 standard / UTC+3 daylight on EU dates, use `120` and `2`. Do not infer this from today's terminal display.

`ResetFilesAtTesterStart=true` clears only the EA's identity-prefixed CSV files in that tester agent's local file sandbox at the beginning of a new test. Export results before another run. To exercise restart recovery within the same isolated environment, set it false after establishing the initial run. It never resets operational COMMON risk files.

Commission and slippage allowances default to zero, so unknown costs are omitted from sizing. Set measured account-currency round-trip commission per lot and round-trip adverse slippage ticks before interpreting results. Actual available deal costs are included in the journal regardless of the sizing allowance.

News is disabled in these examples. `examples/news_example_utc.csv` contains fictional events and does **not** establish historical coverage. To enable news filtering, supply a verified CSV, explicit currency list, and a declared UTC coverage interval. See `docs/CSV_SCHEMAS.md`.

For demo forward testing, work from a copied configuration, confirm the account is demo, then explicitly set `VisualOnly=false` and `AllowDemoTrading=true`. Keep `AllowRealAccountTrading=false`. No such enabled demo configuration is distributed.
