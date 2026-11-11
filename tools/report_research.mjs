#!/usr/bin/env node
// Offline analysis of genuine MT5 journal exports. This never runs a strategy.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function decodeCsv(buffer) {
  if (buffer[0] === 0xff && buffer[1] === 0xfe) return buffer.subarray(2).toString('utf16le');
  if (buffer[0] === 0xfe && buffer[1] === 0xff) {
    const swapped = Buffer.from(buffer.subarray(2));
    if (swapped.length % 2) throw new Error('Invalid UTF-16 CSV length');
    swapped.swap16();
    return swapped.toString('utf16le');
  }
  return buffer.toString('utf8').replace(/^\uFEFF/, '');
}

// RFC-style quoted cells, including escaped quotes and embedded newlines.
export function parseCsv(text, delimiter) {
  text = text.replace(/^\uFEFF/, '');
  if (!delimiter) {
    const firstLine = text.split(/\r?\n/, 1)[0];
    delimiter = [';', '\t', ','].sort((a, b) => firstLine.split(b).length - firstLine.split(a).length)[0];
  }
  if (![';', '\t', ','].includes(delimiter)) throw new Error('Delimiter must be comma, semicolon, or tab');
  const rows = [];
  let row = [], cell = '', quoted = false, afterQuote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; }
        else { quoted = false; afterQuote = true; }
      } else cell += ch;
    } else if (ch === delimiter) {
      row.push(cell); cell = ''; afterQuote = false;
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(cell);
      if (row.some(value => value !== '')) rows.push(row);
      row = []; cell = ''; afterQuote = false;
    } else if (ch === '"') {
      if (cell || afterQuote) throw new Error('Unexpected quote in unquoted CSV cell');
      quoted = true;
    } else {
      if (afterQuote) throw new Error('Unexpected characters after quoted CSV cell');
      cell += ch;
    }
  }
  if (quoted) throw new Error('Unterminated quoted CSV cell');
  if (row.length || cell || afterQuote) {
    row.push(cell);
    if (row.some(value => value !== '')) rows.push(row);
  }
  if (!rows.length) throw new Error('CSV has no header');
  const header = rows.shift().map(value => value.trim());
  if (header.some(value => !value) || new Set(header).size !== header.length) throw new Error('CSV has blank or duplicate column names');
  const records = rows.map((values, index) => {
    if (values.length !== header.length) throw new Error(`CSV record ${index + 2}: expected ${header.length} fields, found ${values.length}`);
    return Object.fromEntries(header.map((name, field) => [name, values[field]]));
  });
  Object.defineProperty(records, 'columns', { value: header });
  return records;
}

function number(value, name, record) {
  if (value === undefined || !/^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i.test(String(value).trim()) || !Number.isFinite(Number(value))) {
    throw new Error(`${record}: invalid ${name}`);
  }
  return Number(value);
}

// Treat timestamps as sortable wall-clock values. No broker UTC offset is inferred.
export function timestamp(value, record) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${record}: missing time`);
  const normalized = value.trim().replace(/^(\d{4})\.(\d{2})\.(\d{2})/, '$1-$2-$3');
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})?$/.exec(normalized);
  if (!match) throw new Error(`${record}: time must be YYYY.MM.DD HH:MM:SS or ISO 8601 with seconds`);
  const [, y, m, d, h, min, sec, ms = '', zone = ''] = match;
  const parts = [+y, +m, +d, +h, +min, +sec];
  const check = new Date(Date.UTC(+y, +m - 1, +d, +h, +min, +sec));
  if (parts.some((part, i) => part !== [check.getUTCFullYear(), check.getUTCMonth() + 1, check.getUTCDate(), check.getUTCHours(), check.getUTCMinutes(), check.getUTCSeconds()][i])) throw new Error(`${record}: invalid calendar time`);
  const result = Date.parse(`${y}-${m}-${d}T${h}:${min}:${sec}.${ms.padEnd(3, '0')}${zone || 'Z'}`);
  if (!Number.isFinite(result)) throw new Error(`${record}: invalid time offset`);
  return { value: result, basis: zone ? 'explicit-offset' : 'broker-wall-clock' };
}

function metrics(trades) {
  const wins = trades.filter(t => t.pnl > 0);
  const losses = trades.filter(t => t.pnl < 0);
  const sum = (array, field) => array.reduce((total, item) => total + item[field], 0);
  let streak = 0, longest = 0;
  for (const trade of trades) {
    streak = trade.pnl < 0 ? streak + 1 : 0;
    longest = Math.max(longest, streak);
  }
  const grossProfit = sum(wins, 'pnl'), grossLoss = -sum(losses, 'pnl');
  return {
    trade_count: trades.length,
    wins: wins.length,
    losses: losses.length,
    flat_trades: trades.length - wins.length - losses.length,
    win_rate: trades.length ? wins.length / trades.length : null,
    average_net_win_R: wins.length ? sum(wins, 'r') / wins.length : null,
    average_net_loss_R: losses.length ? sum(losses, 'r') / losses.length : null,
    net_expectancy_R: trades.length ? sum(trades, 'r') / trades.length : null,
    net_pnl: sum(trades, 'pnl'),
    gross_net_winning_pnl: grossProfit,
    absolute_net_losing_pnl: grossLoss,
    profit_factor: grossLoss > 0 ? grossProfit / grossLoss : null,
    profit_factor_status: grossLoss > 0 ? 'finite' : grossProfit > 0 ? 'no_losing_trades' : 'undefined',
    longest_losing_streak: longest,
  };
}

export function summarizeJournal(records, { label = 'unclassified' } = {}) {
  if (!['development', 'validation', 'unclassified'].includes(label)) throw new Error('Label must be development, validation, or unclassified');
  const trades = [], seen = new Map(), bases = new Set();
  let duplicates = 0;
  for (let index = 0; index < records.length; index++) {
    const row = records[index], record = `Journal record ${index + 2}`;
    if (Object.hasOwn(row, 'record_end') && row.record_end !== 'BEND') throw new Error(`${record}: incomplete journal footer`);
    if (!Object.hasOwn(row, 'event')) throw new Error(`${record}: missing event column`);
    if (row.event !== 'TRADE_CLOSED') continue;
    for (const name of ['rule_version', 'config_id', 'symbol', 'session_id', 'position_id', 'event_time']) {
      if (!row[name]?.trim()) throw new Error(`${record}: missing ${name}`);
    }
    if (!/^\d+$/.test(row.position_id) || BigInt(row.position_id) <= 0n) throw new Error(`${record}: invalid position_id`);
    const risk = number(row.planned_risk_money, 'planned_risk_money', record);
    const pnl = number(row.net_pnl, 'net_pnl', record);
    const recordedR = number(row.net_R, 'net_R', record);
    if (risk <= 0) throw new Error(`${record}: planned_risk_money must be positive`);
    const r = pnl / risk;
    if (Math.abs(r - recordedR) > Math.max(0.00001, Math.abs(r) * 0.00001)) throw new Error(`${record}: net_R does not match net_pnl / initial planned_risk_money`);
    const time = timestamp(row.event_time, record);
    bases.add(time.basis);
    const key = JSON.stringify([row.symbol, String(BigInt(row.position_id))]);
    const identity = JSON.stringify([row.rule_version, row.config_id, row.session_id, row.event_time, risk, pnl, recordedR]);
    if (seen.has(key)) {
      if (seen.get(key) !== identity) throw new Error(`${record}: conflicting TRADE_CLOSED records for position ${row.position_id}`);
      duplicates++;
      continue;
    }
    seen.set(key, identity);
    trades.push({ row, pnl, r, time: time.value, ordinal: index });
  }
  if (bases.size > 1) throw new Error('Journal mixes broker-wall-clock and explicit-offset timestamps');
  trades.sort((a, b) => a.time - b.time || a.ordinal - b.ordinal);
  const groups = name => Object.fromEntries([...new Set(trades.map(t => t.row[name]))].sort().map(key => [key, metrics(trades.filter(t => t.row[name] === key))]));
  return {
    research_label: label,
    source: 'actual supplied TRADE_CLOSED journal records; provenance must be checked by the researcher',
    input_record_count: records.length,
    ignored_non_closure_records: records.filter(row => row.event !== 'TRADE_CLOSED').length,
    duplicate_closures_ignored: duplicates,
    rule_versions: [...new Set(trades.map(t => t.row.rule_version))].sort(),
    config_ids: [...new Set(trades.map(t => t.row.config_id))].sort(),
    timestamp_basis: [...bases][0] || null,
    overall: metrics(trades),
    by_instrument: groups('symbol'),
    by_session: groups('session_id'),
    warnings: [
      'This report does not run or certify an MT5 test. It only summarizes supplied records.',
      'Combine files only from the same account and account currency; account identity is not inferred.',
      'Trade counts are fully closed positions; open positions and partial exits are excluded until final closure.',
      'Losing streaks use close time; equal timestamps preserve input order. A flat trade resets a streak.',
      ...(bases.has('broker-wall-clock') ? ['Broker wall-clock timestamps are not converted to UTC. Repeated times at DST fallback can make close ordering ambiguous.'] : []),
      'A validation label records the supplied designation; it cannot prove that data remained untouched.',
    ],
  };
}

export function summarizeEquity(records) {
  if (!records.length) throw new Error('Equity CSV contains no snapshots');
  const bases = new Set();
  const snapshots = records.map((row, index) => {
    const record = `Equity record ${index + 2}`, time = timestamp(row.time, record);
    bases.add(time.basis);
    return { time: time.value, text: row.time, equity: number(row.equity, 'equity', record), ordinal: index };
  }).sort((a, b) => a.time - b.time || a.ordinal - b.ordinal);
  if (bases.size > 1) throw new Error('Equity CSV mixes broker-wall-clock and explicit-offset timestamps');
  if (snapshots[0].equity <= 0) throw new Error('First equity snapshot must be positive');
  let peak = snapshots[0], maxMoney = 0, maxPercent = 0, moneyPeak = null, moneyTrough = null, percentPeak = null, percentTrough = null;
  for (const snapshot of snapshots) {
    if (snapshot.equity > peak.equity) peak = snapshot;
    const money = peak.equity - snapshot.equity;
    const fraction = peak.equity > 0 ? money / peak.equity : 0;
    if (money > maxMoney) { maxMoney = money; moneyPeak = peak.text; moneyTrough = snapshot.text; }
    if (fraction > maxPercent) { maxPercent = fraction; percentPeak = peak.text; percentTrough = snapshot.text; }
  }
  return {
    status: 'observed_account_equity_snapshots',
    snapshot_count: snapshots.length,
    timestamp_basis: [...bases][0],
    maximum_observed_drawdown_money: maxMoney,
    maximum_observed_drawdown_fraction: maxPercent,
    maximum_money_drawdown_peak_time: moneyPeak,
    maximum_money_drawdown_trough_time: moneyTrough,
    maximum_fraction_drawdown_peak_time: percentPeak,
    maximum_fraction_drawdown_trough_time: percentTrough,
    warning: 'Sampled account equity drawdown only. Intraperiod peaks/troughs may be missed. Includes all account activity and cashflows; no EA attribution or cashflow adjustment is inferred.',
  };
}

export function parseArgs(args) {
  const options = { journals: [], label: 'unclassified' };
  for (let index = 0; index < args.length; index++) {
    const name = args[index];
    if (name === '--help' || name === '-h') { options.help = true; continue; }
    if (!['--journal', '--equity', '--label', '--output', '--account-currency', '--delimiter'].includes(name)) throw new Error(`Unknown option ${name}`);
    const value = args[++index];
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${name}`);
    if (name === '--journal') options.journals.push(value);
    else if (name === '--account-currency') options.accountCurrency = value;
    else options[name.slice(2)] = value;
  }
  if (options.delimiter) {
    options.delimiter = { comma: ',', semicolon: ';', tab: '\t' }[options.delimiter] || options.delimiter;
    if (![',', ';', '\t'].includes(options.delimiter)) throw new Error('Invalid --delimiter');
  }
  if (!['development', 'validation', 'unclassified'].includes(options.label)) throw new Error('Label must be development, validation, or unclassified');
  if (!options.help && !options.journals.length) throw new Error('At least one --journal is required');
  return options;
}

export async function main(args = process.argv.slice(2)) {
  const options = parseArgs(args);
  if (options.help) {
    process.stdout.write('Usage: node tools/report_research.mjs --journal JOURNAL.csv [--journal MORE.csv] [--equity EQUITY.csv] [--label development|validation|unclassified] [--account-currency USD] [--delimiter comma|semicolon|tab] [--output REPORT.json]\n');
    return;
  }
  const records = [];
  for (const path of options.journals) {
    const parsed = parseCsv(decodeCsv(await readFile(path)), options.delimiter);
    for (const column of ['event', 'rule_version', 'config_id', 'symbol', 'session_id', 'position_id', 'event_time', 'planned_risk_money', 'net_pnl', 'net_R']) {
      if (!parsed.columns.includes(column)) throw new Error(`${path}: missing journal column ${column}`);
    }
    records.push(...parsed);
  }
  const report = summarizeJournal(records, { label: options.label });
  report.journal_files = options.journals.map(path => resolve(path));
  report.account_currency = options.accountCurrency || 'not supplied';
  report.equity_drawdown = options.equity
    ? summarizeEquity(parseCsv(decodeCsv(await readFile(options.equity)), options.delimiter))
    : { status: 'not_available', reason: 'No account equity snapshots supplied. Closed-trade P&L is not account equity drawdown.' };
  const output = JSON.stringify(report, null, 2) + '\n';
  if (options.output) await writeFile(options.output, output, 'utf8');
  else process.stdout.write(output);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { process.stderr.write(`Research report failed: ${error.message}\n`); process.exitCode = 1; });
}
