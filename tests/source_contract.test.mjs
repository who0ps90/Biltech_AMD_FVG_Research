// Static source-contract checks only. These do not execute MQL5 or establish runtime safety.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decodeCsv } from '../tools/report_research.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const source = path => readFileSync(resolve(root, path), 'utf8');
const ea = source('MQL5/Experts/Biltech_AMD_FVG_Research.mq5');
const execution = source('MQL5/Include/BiltechAMD/Execution.mqh');
const signal = source('MQL5/Include/BiltechAMD/Signal.mqh');
const types = source('MQL5/Include/BiltechAMD/Types.mqh');
const storage = source('MQL5/Include/BiltechAMD/Storage.mqh');
const news = source('MQL5/Include/BiltechAMD/News.mqh');
const journal = source('MQL5/Include/BiltechAMD/Journal.mqh');

// Mask comments/string contents while retaining character positions and newlines.
function codeOnly(text) {
  return text.replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,
    token => token.replace(/[^\r\n]/g, ' '));
}

function body(text, name) {
  const masked = codeOnly(text);
  const start = new RegExp(`\\b${name}\\s*\\([^)]*\\)\\s*\\{`).exec(masked);
  assert.ok(start, `Missing function ${name}`);
  let depth = 1, index = start.index + start[0].length;
  const begin = index;
  for (; index < masked.length && depth; index++) {
    if (masked[index] === '{') depth++;
    else if (masked[index] === '}') depth--;
  }
  assert.equal(depth, 0, `Unbalanced body ${name}`);
  return text.slice(begin, index - 1);
}

function inputDeclarations() {
  return new Map([...ea.matchAll(/^input\s+(?!group\b)(\w+)\s+(\w+)\s*=\s*([^;]*);/gm)]
    .map(([, type, name, initial]) => [name, { type, initial: initial.trim() }]));
}

test('SOURCE CONTRACT: defaults and account permissions keep real/demo requests opt-in', () => {
  const inputs = inputDeclarations();
  assert.equal(inputs.get('VisualOnly')?.initial, 'true');
  assert.equal(inputs.get('AllowDemoTrading')?.initial, 'false');
  assert.equal(inputs.get('AllowRealAccountTrading')?.initial, 'false');
  const permission = codeOnly(body(execution, 'Permission'));
  assert.match(permission, /if\s*\(m_visual\)/);
  assert.match(permission, /!MQLInfoInteger\(MQL_TESTER\)/);
  assert.match(permission, /ACCOUNT_TRADE_MODE_REAL\s*&&\s*!m_real/);
  assert.match(permission, /ACCOUNT_TRADE_MODE_DEMO[\s\S]*!m_demo/);
});

test('SOURCE CONTRACT: each example set covers inputs, and only named tester examples allow simulation', () => {
  const directory = resolve(root, 'config');
  const files = readdirSync(directory).filter(name => name.toLowerCase().endsWith('.set'));
  assert.ok(files.length > 0, 'Example .set configurations must be supplied');
  const inputs = inputDeclarations();
  const truth = value => /^(true|1)$/i.test(value);
  const falsity = value => /^(false|0)$/i.test(value);
  for (const file of files) {
    const text = decodeCsv(readFileSync(resolve(directory, file)));
    const entries = text.split(/\r?\n/).filter(line => line.trim() && !/^\s*[;#]/.test(line)).map(line => {
      const match = /^\s*(\w+)=(.*)$/.exec(line);
      assert.ok(match, `${file}: invalid setting ${line}`);
      return [match[1], match[2].split('||')[0].trim()];
    });
    const values = new Map(entries);
    assert.equal(values.size, entries.length, `${file}: duplicate input`);
    assert.deepEqual([...values.keys()].sort(), [...inputs.keys()].sort(), `${file}: missing or unknown inputs`);
    assert.ok(falsity(values.get('AllowDemoTrading')), `${file}: demo permission must be false`);
    assert.ok(falsity(values.get('AllowRealAccountTrading')), `${file}: real permission must be false`);
    if (/tester/i.test(file)) assert.ok(truth(values.get('VisualOnly')) || falsity(values.get('VisualOnly')));
    else assert.ok(truth(values.get('VisualOnly')), `${file}: non-tester example must be visual only`);
  }
});

test('SOURCE CONTRACT: configuration snapshot references every declared input', () => {
  const configuration = codeOnly(body(ea, 'Configuration'));
  for (const name of inputDeclarations().keys()) assert.match(configuration, new RegExp(`\\b${name}\\b`), `Configuration omits ${name}`);
});

test('SOURCE CONTRACT: signal reads completed bars, completed ATR and chronological A/B/C', () => {
  const process = codeOnly(body(ea, 'ProcessBar'));
  assert.match(process, /iTime\(_Symbol,ExecutionTimeframe,1\)/);
  assert.match(process, /ArraySetAsSeries\(bars,false\)/);
  assert.match(process, /CopyRates\(_Symbol,ExecutionTimeframe,1,count,bars\)/);
  assert.match(process, /CopyBuffer\(g_atr,0,1,1,atr\)/);
  assert.doesNotMatch(codeOnly(ea), /CopyRates\([^;]*ExecutionTimeframe\s*,\s*0\s*,/);
  assert.match(codeOnly(body(signal, 'TryFVG')), /a=bars\[n-3\],b=bars\[n-2\],c=bars\[n-1\]/);
  assert.match(codeOnly(body(signal, 'TryFVG')), /b\.time<setup\.sweep_bar_open/);
  assert.match(codeOnly(body(signal, 'TryFVG')), /closed_at<setup\.reclaim_at/);
});

test('SOURCE CONTRACT: completed-bar and durable one-attempt guards precede order send', () => {
  const process = codeOnly(body(ea, 'ProcessBar'));
  assert.match(process, /latest<=g_last_bar/);
  assert.match(process, /if\(missed\)[\s\S]*return\s*;/);
  const submit = codeOnly(body(ea, 'SubmitConfirmation'));
  const attempted = submit.indexOf('g_signal.setup.attempted=true');
  const save = submit.indexOf('SaveState()', attempted);
  const send = submit.indexOf('g_execution.Submit(');
  assert.ok(attempted >= 0 && save > attempted && send > save, 'Attempt must be persisted before submission');
  assert.match(codeOnly(body(signal, 'Process')), /bars\[n-1\]\.time<=m_last_bar_open/);
});

test('SOURCE CONTRACT: initial entries are protected limit requests and market deals are close-only', () => {
  const submit = codeOnly(body(execution, 'Submit'));
  assert.match(submit, /request\.action=TRADE_ACTION_PENDING/);
  assert.match(submit, /ORDER_TYPE_BUY_LIMIT\s*:\s*ORDER_TYPE_SELL_LIMIT/);
  assert.match(submit, /request\.sl=s\.sl/);
  assert.match(submit, /request\.tp=s\.tp/);
  assert.ok(submit.indexOf('request.sl=s.sl') < submit.indexOf('OrderSend('));
  assert.ok(submit.indexOf('request.tp=s.tp') < submit.indexOf('OrderSend('));
  assert.doesNotMatch(submit, /TRADE_ACTION_DEAL|ORDER_TYPE_BUY\b|ORDER_TYPE_SELL\b/);
  const close = codeOnly(body(execution, 'ClosePosition'));
  assert.match(close, /request\.action=TRADE_ACTION_DEAL/);
  assert.match(close, /request\.position=ticket/);
  assert.match(close, /ledger\.SafePosition/);
  assert.equal([...codeOnly(execution).matchAll(/TRADE_ACTION_DEAL/g)].length, 1, 'Market request must remain confined to position closure');
  const moduleFiles = readdirSync(resolve(root, 'MQL5/Include/BiltechAMD')).filter(name => name.endsWith('.mqh') && !name.endsWith('Tests.mqh'));
  for (const file of moduleFiles) {
    if (file === 'Execution.mqh') continue;
    assert.doesNotMatch(codeOnly(source(`MQL5/Include/BiltechAMD/${file}`)), /\bOrderSend\s*\(|\.Buy\s*\(|\.Sell\s*\(/, `${file}: unexpected alternate market/order path`);
  }
  assert.doesNotMatch(codeOnly(ea), /\bOrderSend\s*\(|\.Buy\s*\(|\.Sell\s*\(/);
});

test('SOURCE CONTRACT: cancel and position ownership require original strategy tags and authoritative history', () => {
  assert.match(codeOnly(body(execution, 'Cancel')), /BStrategyComment\(OrderGetString\(ORDER_COMMENT\)\)/);
  const risk = source('MQL5/Include/BiltechAMD/Risk.mqh');
  assert.match(risk, /BStrategyComment\(original_comment\)/);
  assert.match(risk, /DEAL_MAGIC\)==m_magic && tagged/);
  assert.match(codeOnly(body(risk, 'SafePosition')), /!m_history_valid/);
  assert.match(codeOnly(body(risk, 'SafePosition')), /!positions\[p\]\.foreign_entry/);
});

test('SOURCE CONTRACT: journal header contains the complete audit schema and reporter requirements', () => {
  const header = /FileWrite\(m_file,([\s\S]*?)\);/.exec(journal);
  assert.ok(header, 'Missing journal header');
  const columns = [...header[1].matchAll(/"([^"]+)"/g)].map(match => match[1]);
  const expected = 'rule_version,config_id,symbol,timeframe,setup_id,session_id,event_time,observed_time,event,from_state,to_state,reason,range_low,range_high,extreme,zone_low,zone_high,entry,sl,tp,volume,planned_risk_money,order_ticket,position_id,deal_ticket,actual_price,actual_volume,spread,commission,swap,fee,profit,slippage,net_pnl,net_R,record_end'.split(',');
  assert.deepEqual(columns, expected);
  const reporter = source('tools/report_research.mjs');
  const required = /for \(const column of (\[[^\]]+\])\)/.exec(reporter);
  assert.ok(required, 'Missing reporter required-column validation');
  for (const [, column] of required[1].matchAll(/'([^']+)'/g)) assert.ok(columns.includes(column), `Journal omits reporter field ${column}`);
  assert.match(journal, /net\/s\.planned_risk_money/);
  assert.match(journal, /CP_UTF8/);
});

test('SOURCE CONTRACT: native fixture runner includes and calls all four suites', () => {
  const runnerPath = 'MQL5/Scripts/Biltech_AMD_Tests.mq5';
  const runner = source(runnerPath);
  for (const suite of ['Signal', 'TimeNews', 'RiskExecution', 'Journal']) {
    assert.match(runner, new RegExp(`#include\\s+"[^"\\n]*${suite}Tests\\.mqh"`));
    assert.match(codeOnly(body(runner, 'OnStart')), new RegExp(`\\bBRun${suite}Tests\\(\\)`));
  }
  for (const [, included] of runner.matchAll(/#include\s+"([^"]+)"/g)) assert.ok(existsSync(resolve(dirname(resolve(root, runnerPath)), included)), `Missing fixture include ${included}`);
  assert.doesNotMatch(codeOnly(runner), /OrderSend\s*\(|BExecution\s+\w+/);
});

test('SOURCE CONTRACT: persistence writes numeric timestamps, text cells and completeness footer', () => {
  const write = body(storage, 'WriteSnapshot');
  assert.match(write, /\(long\)last_bar/);
  const setupFields = /struct\s+BSetup\s*\{([\s\S]*?)\};/.exec(types);
  assert.ok(setupFields, 'Missing BSetup structure');
  for (const [, name] of setupFields[1].matchAll(/^\s*datetime\s+(\w+)\s*;/gm)) assert.match(write, new RegExp(`\\(long\\)s\\.${name}\\b`), `Uncast datetime ${name}`);
  for (const name of ['reason', 'symbol', 'config_id']) assert.match(write, new RegExp(`BCSVCell\\(s\\.${name}\\)`));
  assert.match(write, /"BEND"/);
  assert.match(write, /FileMove\(tmp,m_flags,filename,FILE_REWRITE\|m_flags\)/);
  const read = body(storage, 'ReadSnapshot');
  assert.match(read, /footer=="BEND"/);
  for (const name of ['order_ticket', 'position_id']) assert.match(read, new RegExp(`s\\.${name}=\\(ulong\\)StringToInteger\\(FileReadString\\(h\\)\\)`), `${name} must avoid double precision conversion`);
});

test('SOURCE CONTRACT: required news data has explicit UTC coverage and fails closed outside it', () => {
  const init = body(news, 'Init');
  assert.match(init, /coverage_end_utc<=cfg\.coverage_start_utc/);
  assert.match(init, /file==INVALID_HANDLE/);
  assert.match(init, /header!="utc,currency,impact,event"/);
  assert.match(init, /CP_UTF8/);
  const blocked = body(news, 'Blocked');
  assert.match(codeOnly(blocked), /!m_valid/);
  assert.match(codeOnly(blocked), /utc<m_cfg\.coverage_start_utc\s*\|\|\s*utc>=m_cfg\.coverage_end_utc/);
  assert.match(codeOnly(blocked), /return true/);
  assert.match(body(news, 'NextBoundary'), /m_cfg\.coverage_end_utc/);
});

test('SOURCE CONTRACT: compilation helper invokes only hidden MetaEditor with fresh validated logs', () => {
  const helper = source('tools/compile.ps1');
  assert.match(helper, /Start-Process[^\r\n]*-WindowStyle Hidden/);
  assert.match(helper, /MetaEditor64\.exe/);
  assert.match(helper, /Remove-Item -LiteralPath \$logPath/);
  assert.match(helper, /compile_ea\.log/);
  assert.match(helper, /compile_fixtures\.log/);
  assert.match(helper, /0 errors and 0 warnings/);
  assert.doesNotMatch(helper, /terminal64\.exe|metatester64\.exe|Get-ChildItem[^\r\n]*-Recurse/i);
});
