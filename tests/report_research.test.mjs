// Synthetic report-calculation fixtures. These are NOT MT5 backtests or strategy tests.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, rmdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { decodeCsv, parseCsv, summarizeJournal, summarizeEquity, timestamp, parseArgs } from '../tools/report_research.mjs';

function closure(id, pnl, overrides = {}) {
  return {
    event: 'TRADE_CLOSED', rule_version: 'fixture', config_id: 'synthetic', symbol: 'FIXTURE_A',
    session_id: '2026-01-05_NY', position_id: String(id),
    event_time: `2026.01.05 15:${String(id).padStart(2, '0')}:00`,
    planned_risk_money: '10', net_pnl: String(pnl), net_R: String(pnl / 10), ...overrides,
  };
}

test('CSV parser handles MQL separators, quoted fields, escaped quotes, newlines and BOM', () => {
  assert.deepEqual(parseCsv('\uFEFFevent;reason\r\nREJECTED;"spread;too wide"\r\nOBSERVED;"a ""quote""\nnext"\r\n'), [
    { event: 'REJECTED', reason: 'spread;too wide' },
    { event: 'OBSERVED', reason: 'a "quote"\nnext' },
  ]);
  assert.deepEqual(parseCsv('event\tvalue\nA\t1\n'), [{ event: 'A', value: '1' }]);
  assert.deepEqual(parseCsv('event,value\nA,1'), [{ event: 'A', value: '1' }]);
});

test('CSV parser rejects structurally damaged exports instead of dropping rows', () => {
  for (const csv of ['event,event\nA,B', 'event,x\nA', 'event,x\nA,"oops', 'event,x\nA,"ok"bad', 'event,x\nA,un"quoted']) {
    assert.throws(() => parseCsv(csv));
  }
  assert.throws(() => parseCsv(''), /no header/);
});

test('MQL Unicode exports decode from UTF-16 LE and BE', () => {
  const plain = 'event,reason\nWAIT,£\n';
  const le = Buffer.from(plain, 'utf16le');
  assert.equal(decodeCsv(Buffer.concat([Buffer.from([0xff, 0xfe]), le])), plain);
  assert.equal(decodeCsv(Buffer.concat([Buffer.from([0xfe, 0xff]), Buffer.from(le).swap16()])), plain);
});

test('supplied native journal completeness footers are enforced even on audit-only rows', () => {
  assert.equal(summarizeJournal([closure(1, 10, { record_end: 'BEND' })]).overall.trade_count, 1);
  assert.throws(() => summarizeJournal([closure(1, 10, { record_end: '' })]), /incomplete journal footer/);
  assert.throws(() => summarizeJournal([{ event: 'DEAL', record_end: 'BROKEN' }]), /incomplete journal footer/);
});

test('only full-position closure rows affect net statistics', () => {
  const report = summarizeJournal([
    { event: 'DEAL', net_pnl: '999999', net_R: '999999' },
    closure(1, 20), closure(2, -10), closure(3, -5), closure(4, 0),
    { event: 'ORDER_PENDING' },
    closure(5, 10, { symbol: 'FIXTURE_B', session_id: '2026-01-05_LON' }),
  ], { label: 'development' });
  assert.equal(report.overall.trade_count, 5);
  assert.equal(report.overall.wins, 2);
  assert.equal(report.overall.losses, 2);
  assert.equal(report.overall.flat_trades, 1);
  assert.equal(report.overall.win_rate, 0.4);
  assert.equal(report.overall.average_net_win_R, 1.5);
  assert.equal(report.overall.average_net_loss_R, -0.75);
  assert.equal(report.overall.net_expectancy_R, 0.3);
  assert.equal(report.overall.net_pnl, 15);
  assert.equal(report.overall.profit_factor, 2);
  assert.equal(report.overall.longest_losing_streak, 2);
  assert.equal(report.ignored_non_closure_records, 2);
  assert.equal(report.by_instrument.FIXTURE_A.trade_count, 4);
  assert.equal(report.by_session['2026-01-05_LON'].trade_count, 1);
  assert.equal(report.research_label, 'development');
});

test('initial monetary risk defines each trade R, including unequal risks', () => {
  const report = summarizeJournal([
    closure(1, 20),
    closure(2, -10, { planned_risk_money: '20', net_R: '-0.5' }),
  ]);
  assert.equal(report.overall.net_expectancy_R, 0.75);
  assert.equal(report.overall.profit_factor, 2);
});

test('no trades is reported as no observations, not a made-up zero win rate', () => {
  const report = summarizeJournal([{ event: 'INVALIDATED' }]);
  assert.equal(report.overall.trade_count, 0);
  assert.equal(report.overall.win_rate, null);
  assert.equal(report.overall.net_expectancy_R, null);
  assert.equal(report.overall.profit_factor, null);
});

test('no losses reports undefined numeric PF without serializing Infinity', () => {
  const report = summarizeJournal([closure(1, 20)]);
  assert.equal(report.overall.profit_factor, null);
  assert.equal(report.overall.profit_factor_status, 'no_losing_trades');
  assert.equal(report.overall.average_net_loss_R, null);
});

test('chronological close ordering and flat trade streak reset are explicit', () => {
  const rows = [closure(5, -1), closure(1, -1), closure(4, -1), closure(3, 0), closure(2, -1)];
  assert.equal(summarizeJournal(rows).overall.longest_losing_streak, 2);
});

test('identical duplicate closure notifications are counted once and inconsistent ones fail', () => {
  const row = closure(1, -10, { position_id: '18446744073709551615' });
  const report = summarizeJournal([row, { ...row }]);
  assert.equal(report.overall.trade_count, 1);
  assert.equal(report.duplicate_closures_ignored, 1);
  assert.throws(() => summarizeJournal([row, { ...row, net_pnl: '-20', net_R: '-2' }]), /conflicting/);
  assert.throws(() => summarizeJournal([row, { ...row, config_id: 'other-config' }]), /conflicting/);
});

test('invalid risk, result, timestamp or missing session fails closed', () => {
  for (const override of [
    { planned_risk_money: '0' }, { planned_risk_money: '-1' }, { net_pnl: 'NaN' }, { net_pnl: '0x10' },
    { net_pnl: '' }, { net_R: '2' }, { net_R: '' }, { event_time: 'yesterday' },
    { session_id: '' }, { position_id: '0' }, { position_id: '1.5' },
  ]) assert.throws(() => summarizeJournal([closure(1, -10, override)]));
});

test('timestamp validation rejects invalid dates and refuses mixed time bases', () => {
  assert.throws(() => timestamp('2026.02.30 10:00:00', 'fixture'), /invalid calendar/);
  assert.throws(() => timestamp('2026.01.01 25:00:00', 'fixture'), /invalid calendar/);
  assert.equal(timestamp('2026-01-01T11:00:00+01:00', 'fixture').value, timestamp('2026-01-01T10:00:00Z', 'fixture').value);
  assert.throws(() => summarizeJournal([closure(1, 10), closure(2, -10, { event_time: '2026-01-05T15:02:00Z' })]), /mixes/);
});

test('equity drawdown uses snapshots and distinguishes monetary and percentage maxima', () => {
  const report = summarizeEquity([
    { time: '2026.01.01 00:00:00', equity: '100' },
    { time: '2026.01.02 00:00:00', equity: '80' },
    { time: '2026.01.03 00:00:00', equity: '200' },
    { time: '2026.01.04 00:00:00', equity: '170' },
  ]);
  assert.equal(report.maximum_observed_drawdown_money, 30);
  assert.equal(report.maximum_observed_drawdown_fraction, 0.2);
  assert.equal(report.maximum_money_drawdown_peak_time, '2026.01.03 00:00:00');
  assert.equal(report.maximum_fraction_drawdown_trough_time, '2026.01.02 00:00:00');
  assert.equal(report.status, 'observed_account_equity_snapshots');
});

test('negative equity is retained and invalid equity exports fail', () => {
  assert.equal(summarizeEquity([
    { time: '2026.01.01 00:00:00', equity: '100' },
    { time: '2026.01.02 00:00:00', equity: '-20' },
  ]).maximum_observed_drawdown_fraction, 1.2);
  assert.throws(() => summarizeEquity([]), /no snapshots/);
  assert.throws(() => summarizeEquity([{ time: '2026.01.01 00:00:00', equity: '0' }]), /positive/);
});

test('argument validation keeps validation and development runs separate', () => {
  assert.equal(parseArgs(['--journal', 'a.csv', '--label', 'validation']).label, 'validation');
  assert.equal(parseArgs(['--journal', 'a.csv', '--journal', 'b.csv']).journals.length, 2);
  assert.throws(() => parseArgs(['--journal', 'a.csv', '--label', 'optimised']), /Label/);
  assert.throws(() => parseArgs(['--journal']), /Missing/);
  assert.throws(() => parseArgs(['--unknown']), /Unknown/);
});

test('CLI reads file interfaces, validates headers, and requires snapshots for equity DD', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'biltech-report-fixture-'));
  const file = join(folder, 'synthetic.csv'), output = join(folder, 'report.json'), equity = join(folder, 'equity.csv');
  const tool = fileURLToPath(new URL('../tools/report_research.mjs', import.meta.url));
  try {
    const row = closure(1, -10), headers = Object.keys(row);
    await writeFile(file, `${headers.join(',')}\n${headers.map(key => row[key]).join(',')}\n`);
    const result = spawnSync(process.execPath, [tool, '--journal', file, '--output', output, '--label', 'validation'], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(await readFile(output, 'utf8'));
    assert.equal(report.overall.trade_count, 1);
    assert.equal(report.equity_drawdown.status, 'not_available');
    assert.equal(report.research_label, 'validation');
    assert.equal(result.stdout, '');
    await writeFile(equity, 'time,equity\n2026.01.01 00:00:00,100\n2026.01.02 00:00:00,90\n');
    const withEquity = spawnSync(process.execPath, [tool, '--journal', file, '--equity', equity], { encoding: 'utf8' });
    assert.equal(withEquity.status, 0, withEquity.stderr);
    assert.equal(JSON.parse(withEquity.stdout).equity_drawdown.maximum_observed_drawdown_fraction, 0.1);
    await writeFile(file, 'event\n');
    const missingHeaders = spawnSync(process.execPath, [tool, '--journal', file], { encoding: 'utf8' });
    assert.equal(missingHeaders.status, 1);
    assert.match(missingHeaders.stderr, /missing journal column/);
  } finally {
    await Promise.allSettled([rm(file, { force: true }), rm(output, { force: true }), rm(equity, { force: true })]);
    await rmdir(folder);
  }
});
