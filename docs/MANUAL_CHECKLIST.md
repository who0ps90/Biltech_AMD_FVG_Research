# Manual backtest and forward-demo checklist

All items below are **NOT RUN** for this delivery. Preserve positive and negative evidence; do not select only attractive examples. Keep `AllowRealAccountTrading=false` throughout.

## Build and native fixtures

- [ ] Record terminal/MetaEditor build, source hashes and rule version. Compile both targets with zero errors/warnings.
- [ ] In an isolated/disconnected MT5 environment run `Biltech_AMD_Tests`. Retain full terminal log and every suite summary. Confirm fixtures clean up only their test files and no trade requests occur.
- [ ] Record pass/fail per assertion. Investigate a failed fixture before any simulated or demo order run.

## Reproducible Strategy Tester run

- [ ] Select the exact intended **broker symbol**, account currency, deposit, leverage and netting/hedging mode. Save the actual contract specification, tick/point size, min/max/step volume, stop/freeze levels, supported order/expiry/filling modes and commission model. Do not interchange a future and similarly named CFD.
- [ ] Verify historical broker standard UTC offset and DST schedule independently. Check New York and London DST transition weeks, US/Europe mismatch weeks, local day rollover and any cross-midnight research session. Confirm invalid/ambiguous clocks block entries.
- [ ] Freeze the `.set`, rule source, broker symbol, verified calendar and data dates. Record news coverage/currency choices and cost allowances. Explain omitted costs explicitly.
- [ ] Reserve development and untouched validation intervals **before** looking at results. Keep validation inputs frozen; record any later change as a new research version.
- [ ] Choose **Every tick based on real ticks** where available. Record the actual mode, missing/replaced ticks, history synchronization and modelling limitations. Record tester delay/spread/commission settings. A Python or offline model is not a substitute.
- [ ] Use `VisualOnly=false` only for the simulated-order tester run. Keep demo/real permissions false. Export output files before a fresh run resets tester CSVs.
- [ ] Inspect valid long/short, same-bar sweep/reclaim, no reclaim, double sweep, premature FVG, reclaim/FVG inclusive deadlines, post-reclaim extreme, target-room rejection and range expiry. Compare annotations with close knowledge time and actual observed time.
- [ ] Inspect pre-confirmation midpoint touches. Verify no retrospective fill, no market chase, first observed tick submission, one attempt per range, initial attached SL/TP, and tick-normalized actual 2R/target room.
- [ ] Check excessive spread, minimum volume above budget, account-currency conversion failure, margin failure, stop/freeze rejection, unsupported expiration and market closure. Retain rejection codes and unchanged strategy prices.
- [ ] Test unfilled entry expiry at three periods, session end, news start and sweep extreme. Disconnect through a boundary and inspect reconnect/race outcomes. Verify broker-side expiry where supported and EA-side cancellation where not supported.
- [ ] Force/observe a partial fill; verify cancellation of unfilled remainder, protected position, no new setup exposure, one position trade count, and full original-risk denominator in R. Repeated/out-of-order trade notifications must not duplicate counters or closure rows.
- [ ] Trigger two session fills, two losing trades and the daily 0.5% threshold separately. Include floating loss, commission, fee and swap where available. Confirm pending cancellation and bounded close attempts; record overshoot and residual exposure. Confirm sticky lock despite recovery, surviving restart, released only on the next configured local day.
- [ ] Restart during range, reclaim, durable pre-send intent, pending order, partial fill, open position and disconnected expiration. Verify no duplicate order and conservative unsent-signal invalidation. Corrupt a **copied test sandbox** record and verify fail-closed behavior.
- [ ] Test two instances sharing the identity; the second must fail to acquire its common lock. On netting and hedging test accounts, verify manual/other-magic trades are never modified or adopted. Do not test coordinated deployment across machines; it is unsupported.
- [ ] Export tester report, terminal logs, journal, configurations, calendar, representative screenshots and equity series. Reconcile deal totals and original-risk R with the tester's actual transactions.
- [ ] Produce trade count, win rate, average net win/loss R, expectancy, profit factor, equity drawdown and longest losing streak by instrument/session. Use actual equity evidence for drawdown; label sampled data. Keep development and validation reports separate and disclose no-trade/undefined statistics.

## Forward demo after reviewing tester evidence

- [ ] Confirm the connected account is **demo**. Use a copied input file with `VisualOnly=false`, `AllowDemoTrading=true`, and `AllowRealAccountTrading=false`. Enable terminal/EA trading permission only in that controlled demo environment.
- [ ] First compare several sessions in visual-only mode with the written rules. Check broker/session-local clock, daily baseline and calendar diagnostics before changing demo permission.
- [ ] Repeat entry/protection, expiry/news/session boundary, spread, daily lock, partial fill, rejection, restart/disconnection and ownership scenarios under live demo quotes. Record actual request/fill slippage and races.
- [ ] Inspect any management retry-limit diagnostic and residual position/order directly in MT5. Do not assume a successful request or cancellation diagnostic is final execution evidence.
- [ ] Preserve all demo evidence with broker/account/build/configuration identifiers. Compare with development and validation results without claiming that demo performance establishes future profitability.
