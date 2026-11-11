# CSV contracts

## Scheduled news input

File location: execution terminal or local test agent `MQL5/Files/<NewsCSVFile>`. UTF-8 text; exact header:

```csv
utc,currency,impact,event
2024.01.08 15:00:00,USD,HIGH,FICTIONAL example only
```

This row is a format example, not an assertion that an event occurred. `examples/news_example_utc.csv` is entirely fictional. Replace it with a documented research calendar before enabling exclusions.

| Field | Contract |
|---|---|
| `utc` | Explicit UTC timestamp, strict valid calendar date. `YYYY.MM.DD HH:MM[:SS]` and `YYYY-MM-DDTHH:MM[:SS]` with optional `Z` are accepted. No broker/local timestamps or numeric UTC offsets. |
| `currency` | Explicit uppercase three-letter currency code. Relevance is selected by `NewsCurrencies` (comma-separated), not guessed from symbol names. |
| `impact` | `LOW`, `MEDIUM`, or `HIGH`; only selected `HIGH` events create exclusions. |
| `event` | Nonempty descriptive text. Quoted fields/escaped double quotes are supported, but each record must occupy one physical line. |

The parser validates **all** rows, including unselected currencies and impacts, and fails initialization on any error. Empty selected-event calendars are accepted only with a valid declared coverage interval. That declaration is the researcher's assertion; the EA cannot verify historical completeness. Start is inclusive, end exclusive. New entries are blocked outside coverage. High-event windows include both endpoints; overlapping windows are merged. The EA shortens pending expiry to the next exclusion start or coverage end and attempts cancellation on the observed boundary tick.

`NewsCoverageStartUTC` and `NewsCoverageEndUTC` use the same strict UTC date syntax. Default before/after windows are each 15 minutes. Existing positions retain initial SL/TP across news; session-end and daily-risk exits still apply.

## Audit journal output

UTF-8, comma delimiter, decimal point. Textual output cells replace commas with semicolons, CR/LF with spaces, and double quotes with apostrophes because native MQL CSV primitives are delimiter-based. Native reads and restart receipts use the same contract. Each complete row ends in `BEND`; malformed/truncated journals block initialization instead of being silently appended to.

Exact column order:

```csv
rule_version,config_id,symbol,timeframe,setup_id,session_id,event_time,observed_time,event,from_state,to_state,reason,range_low,range_high,extreme,zone_low,zone_high,entry,sl,tp,volume,planned_risk_money,order_ticket,position_id,deal_ticket,actual_price,actual_volume,spread,commission,swap,fee,profit,slippage,net_pnl,net_R,record_end
```

| Fields | Meaning |
|---|---|
| `rule_version`, `config_id` | Frozen rule version and configuration hash. Full input snapshot is stored separately. Initial plan's config is retained when an older position closes. |
| `symbol`, `timeframe` | Exact broker symbol and configured signal timeframe. An identity is exclusive across local symbols. |
| `setup_id` | Qualification knowledge timestamp, numeric epoch seconds in broker timestamp convention; identity and symbol qualify this ID. Zero denotes no qualified range. |
| `session_id` | Original submission session's local start date, `YYYYMMDD`, including cross-midnight sessions. |
| `event_time` | Signal's completed-bar knowledge time, authoritative deal time, or observed management-action time as applicable. Broker-server wall time, `YYYY.MM.DD HH:MM:SS`. |
| `observed_time` | First processing/notification reconciliation time for that record, in the same server clock. A delayed observation is not backdated. |
| `event`, `from_state`, `to_state`, `reason` | Event type, explicit state change and acceptance/rejection/action diagnostic. |
| Range / extreme / zone fields | Prices known at the transition; later extremes/zones never overwrite prior journal records. |
| `entry`, `sl`, `tp` | Frozen normalized strategy prices when available; zero before planning. |
| `volume`, `planned_risk_money` | Requested volume and initial planned account-currency loss budget, including configured commission/slippage allowances. Actual filled volume can be smaller. |
| Order / position / deal tickets | Native integer identifiers; zero when unavailable. Preserve as strings/64-bit integers in external tools. |
| `actual_price`, `actual_volume` | Individual deal execution values on `DEAL` rows. Closure aggregate rows use aggregate out volume and no single average price (zero). |
| `spread` | Price units. Planned submission spread is captured in `PLAN`; fill/deal rows sample the current quote only when same symbol and server second are available. Zero in historical/unsampled execution rows means **unknown**, not proof of a zero spread. |
| `commission`, `swap`, `fee`, `profit` | Available broker deal values; in account currency. `TRADE_CLOSED` aggregates the entire position. Broker fees without a recoverable position/magic association may remain unattributable. |
| `slippage` | Entry deal minus planned entry for a long, planned entry minus deal for a short, in price units; positive is adverse. Zero on exit/aggregate records means not measured. |
| `net_pnl` | Deal net or full-position net, depending on event; do not sum both. Available profit + commission + swap + fee. |
| `net_R` | Present only on full-position closure with known original planned monetary risk: aggregate net / initial planned risk. Partial-fill closures retain the full original requested-risk denominator. |
| `record_end` | Literal `BEND`, to detect incomplete records. |

Events include `STATE`, `PLAN`, `DEAL`, `TRADE_CLOSED`, `CANCEL_REQUEST`, `CLOSE_REQUEST`, `MANAGEMENT_DIAGNOSTIC`, and `DATA_GAP`. `STATE` invalidation reasons record rejected/marketable/missed setups. Pending expiration is recorded through authoritative historical order state, including `ORDER_STATE_EXPIRED`. A successful cancel/close request is not a claim of a final broker fill/cancellation; history is reconciled afterward.

The reporter uses only full-position `TRADE_CLOSED` rows. Deals are independent audit rows and must not be added again. It rejects invalid monetary risk, inconsistent R, malformed timestamps, missing required fields and conflicting duplicate closures. Positions without a durable original plan are excluded from invented R reporting and block new entries if currently open; account history still drives available risk counters.

## Equity snapshots

```csv
time,equity
```

The supplied example has a header only because there is no actual account/test equity series to report. `time` uses broker-server wall time. `equity` is `ACCOUNT_EQUITY`, sampled on observed ticks no more often than once per minute. The file covers the account, including manual/other-EA exposure and cashflows; the reporter labels resulting drawdown sampled account drawdown. Export a higher-frequency tester equity series separately if tick-level maximum equity drawdown is required.

## Internal persistence

`_active.csv` and `_plan_<order>.csv` use private `BAMD_STATE_1` schema and `BEND` footer. All datetime values are stored as integer seconds. `_day_<date>.csv` uses `BAMD_DAY_1,date,day_start_equity,locked,BEND`. Temporary snapshots are flushed and renamed before new-order permission is used. Do not treat these private schemas as public trade exports or manually change them while an instance holds its lock.
