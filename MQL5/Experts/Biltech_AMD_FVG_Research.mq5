#property strict
#property version "1.00"
#property description "Deterministic AMD ordinary-FVG research EA. VisualOnly by default."
#include "../Include/BiltechAMD/Signal.mqh"
#include "../Include/BiltechAMD/Time.mqh"
#include "../Include/BiltechAMD/News.mqh"
#include "../Include/BiltechAMD/Risk.mqh"
#include "../Include/BiltechAMD/Storage.mqh"
#include "../Include/BiltechAMD/Journal.mqh"
#include "../Include/BiltechAMD/Execution.mqh"
#include "../Include/BiltechAMD/Visuals.mqh"

input group "Safety - all order placement disabled by default"
input bool VisualOnly=true;
input bool AllowDemoTrading=false;
input bool AllowRealAccountTrading=false;
input ulong StrategyMagic=2601025001;
input group "Closed-candle ordinary FVG strategy"
input ENUM_TIMEFRAMES ExecutionTimeframe=PERIOD_M5;
input int RangeLookbackBars=20;
input int ATRPeriod=14;
input double MaxRangeATR=3.0;
input int RangeExpiryBars=20;
input int ReclaimDeadlineBars=3;
input int FVGDeadlineBars=3;
input double MinFVG_ATR=0.0;
input group "Risk and transaction-cost allowances"
input double RiskPercent=0.25;
input int MaxFilledTradesPerSession=2;
input int MaxLosingTradesPerDay=2;
input double DailyLossPercent=0.5;
input double RoundTripCommissionPerLot=0.0;
input int RoundTripSlippageTicks=0;
input double MaxSpreadStopFraction=0.10;
input double MaxAbsoluteSpreadPrice=0.0;
input long DayStartEquityOverrideDate=0; // YYYYMMDD; only this dated day
input double DayStartEquityOverride=0.0;
input group "Session and explicit historical broker clock"
input BSessionZone SessionTimezone=B_NEW_YORK;
input string SessionStart="09:45";
input string SessionEnd="11:00";
input bool WeekdaysOnly=true;
input int BrokerStandardUTCOffsetMinutes=9999; // REQUIRED; sentinel never inferred
input BBrokerDST BrokerDSTSchedule=B_FIXED;
input group "Optional reproducible UTC news calendar"
input bool UseNewsFilter=false;
input string NewsCSVFile="news_example_utc.csv";
input string NewsCurrencies="USD";
input int NewsMinutesBefore=15;
input int NewsMinutesAfter=15;
input string NewsCoverageStartUTC="";
input string NewsCoverageEndUTC="";
input group "Research output"
input int ChartHistoryLimit=100;
input bool ResetFilesAtTesterStart=true;
input string ResearchLabel="unclassified";

BSignalEngine g_signal;
BTimeRules g_clock;
BNewsFilter g_news;
BRiskLedger g_risk;
BStore g_store;
BJournal g_journal;
BExecution g_execution;
BVisuals g_visuals;
BRiskConfig g_risk_cfg;
int g_atr=INVALID_HANDLE;
datetime g_last_bar=0,g_last_reconcile=0,g_last_equity=0;
bool g_started=false,g_trade_dirty=true,g_storage_fault=false,g_ready=false;
string g_diagnostic="",g_config="";
string g_management_errors[];

bool ParseHM(const string text,int &minutes)
  {
   if(StringLen(text)!=5 || StringSubstr(text,2,1)!=":") return false;
   for(int i=0;i<5;i++) if(i!=2 && (StringGetCharacter(text,i)<'0' || StringGetCharacter(text,i)>'9')) return false;
   int hour=(int)StringToInteger(StringSubstr(text,0,2)),minute=(int)StringToInteger(StringSubstr(text,3,2));
   if(hour>23 || minute>59) return false; minutes=hour*60+minute; return true;
  }

bool ValidOverrideDay(const long day)
  {
   if(day==0) return true;
   if(day<20070101 || day>20991231) return false;
   int year=(int)(day/10000),month=(int)((day/100)%100),date=(int)(day%100);
   if(month<1 || month>12 || date<1 || date>31) return false;
   MqlDateTime parsed;
   return TimeToStruct(BDate(year,month,date),parsed) && parsed.year==year && parsed.mon==month && parsed.day==date;
  }

string Configuration()
  {
   return "rule_version=" B_RULE_VERSION+"\nsymbol="+_Symbol+"\ntimeframe="+EnumToString(ExecutionTimeframe)+
      "\nVisualOnly="+(string)VisualOnly+"\nAllowDemoTrading="+(string)AllowDemoTrading+"\nAllowRealAccountTrading="+(string)AllowRealAccountTrading+
      "\nStrategyMagic="+(string)StrategyMagic+"\nRangeLookbackBars="+(string)RangeLookbackBars+"\nATRPeriod="+(string)ATRPeriod+
      "\nMaxRangeATR="+(string)MaxRangeATR+"\nRangeExpiryBars="+(string)RangeExpiryBars+"\nReclaimDeadlineBars="+(string)ReclaimDeadlineBars+
      "\nFVGDeadlineBars="+(string)FVGDeadlineBars+"\nMinFVG_ATR="+(string)MinFVG_ATR+"\nRiskPercent="+(string)RiskPercent+
      "\nMaxFilledTradesPerSession="+(string)MaxFilledTradesPerSession+"\nMaxLosingTradesPerDay="+(string)MaxLosingTradesPerDay+
      "\nDailyLossPercent="+(string)DailyLossPercent+"\nRoundTripCommissionPerLot="+(string)RoundTripCommissionPerLot+
      "\nRoundTripSlippageTicks="+(string)RoundTripSlippageTicks+"\nMaxSpreadStopFraction="+(string)MaxSpreadStopFraction+
      "\nMaxAbsoluteSpreadPrice="+(string)MaxAbsoluteSpreadPrice+"\nDayStartEquityOverrideDate="+(string)DayStartEquityOverrideDate+
      "\nDayStartEquityOverride="+(string)DayStartEquityOverride+"\nSessionTimezone="+EnumToString(SessionTimezone)+"\nSessionStart="+SessionStart+
      "\nSessionEnd="+SessionEnd+"\nWeekdaysOnly="+(string)WeekdaysOnly+"\nBrokerStandardUTCOffsetMinutes="+(string)BrokerStandardUTCOffsetMinutes+
      "\nBrokerDSTSchedule="+EnumToString(BrokerDSTSchedule)+"\nUseNewsFilter="+(string)UseNewsFilter+"\nNewsCSVFile="+NewsCSVFile+
      "\nNewsCurrencies="+NewsCurrencies+"\nNewsMinutesBefore="+(string)NewsMinutesBefore+"\nNewsMinutesAfter="+(string)NewsMinutesAfter+
      "\nNewsCoverageStartUTC="+NewsCoverageStartUTC+"\nNewsCoverageEndUTC="+NewsCoverageEndUTC+
      "\nChartHistoryLimit="+(string)ChartHistoryLimit+"\nResetFilesAtTesterStart="+(string)ResetFilesAtTesterStart+"\nResearchLabel="+ResearchLabel+"\n";
  }

bool SaveState()
  {
   if(g_store.Save(g_signal.setup,g_last_bar)) return true;
   g_storage_fault=true; g_diagnostic="Durable state write failed; entries disabled"; Print(g_diagnostic); return false;
  }

void Transition(const BState next,const datetime at,const string reason)
  {
   BState previous=g_signal.setup.state;
   g_signal.setup.state=next; g_signal.setup.reason=reason;
   if(!g_journal.Event(g_signal.setup,at,TimeCurrent(),"STATE",previous,reason)) g_storage_fault=true;
   g_visuals.Draw(g_signal.setup,at); SaveState();
  }

void LogEvents(BTransition &events[],const datetime observed,const long session_id)
  {
   for(int i=0;i<ArraySize(events);i++)
     {
      if(events[i].to_state==B_RANGE_READY) g_signal.setup.observed_qualification=observed;
      if(events[i].to_state==B_SWEPT) g_signal.setup.observed_sweep=observed;
      if(events[i].to_state==B_RECLAIMED) g_signal.setup.observed_reclaim=observed;
      if(events[i].to_state==B_FVG_CONFIRMED) g_signal.setup.observed_confirmation=observed;
      events[i].snapshot.observed_qualification=g_signal.setup.observed_qualification;
      events[i].snapshot.observed_sweep=g_signal.setup.observed_sweep;
      events[i].snapshot.observed_reclaim=g_signal.setup.observed_reclaim;
      events[i].snapshot.observed_confirmation=g_signal.setup.observed_confirmation;
      events[i].snapshot.symbol=_Symbol; events[i].snapshot.config_id=g_config; events[i].snapshot.session_id=session_id;
      if(!g_journal.Event(events[i].snapshot,events[i].at,observed,"STATE",events[i].from_state,events[i].reason)) g_storage_fault=true;
      g_visuals.Draw(events[i].snapshot,observed);
     }
   if(g_signal.setup.id>0) { g_signal.setup.symbol=_Symbol; g_signal.setup.config_id=g_config; g_signal.setup.session_id=session_id; }
  }

void ManagementError(const BSetup &s,const datetime now,const string outcome)
  {
   if(outcome=="") return;
   g_diagnostic=outcome;
   for(int i=0;i<ArraySize(g_management_errors);i++) if(g_management_errors[i]==outcome) return;
   int n=ArraySize(g_management_errors); ArrayResize(g_management_errors,n+1); g_management_errors[n]=outcome;
   if(!g_journal.Event(s,now,now,"MANAGEMENT_DIAGNOSTIC",s.state,outcome)) g_storage_fault=true;
  }

void Reconcile(const datetime now,const MqlTick &quote,const long session_id)
  {
   if(!g_risk.Refresh(g_clock,now,session_id,DayStartEquityOverrideDate,DayStartEquityOverride))
     { g_diagnostic=g_risk.diagnostic; g_last_reconcile=now; g_trade_dirty=false; return; }
   // Recover a request accepted between durable intent and the synchronous response.
   // Ownership and the exact persisted setup comment must match; never resubmit it.
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || (ulong)OrderGetInteger(ORDER_MAGIC)!=StrategyMagic) continue;
      if(!BStrategyComment(OrderGetString(ORDER_COMMENT)))
        { g_storage_fault=true; g_diagnostic="Magic collision with an untagged order; no modification permitted"; continue; }
      if(g_signal.setup.attempted && g_signal.setup.id>0 &&
         OrderGetString(ORDER_COMMENT)=="BAMD:"+(string)g_signal.setup.id && OrderGetString(ORDER_SYMBOL)==g_signal.setup.symbol)
        {
         g_signal.setup.order_ticket=ticket;
         if(!g_store.SavePlan(g_signal.setup,g_last_bar)) g_storage_fault=true;
         if(g_signal.setup.state!=B_ORDER_PENDING && g_signal.setup.state!=B_POSITION_OPEN)
            Transition(B_ORDER_PENDING,now,"Recovered existing pending order from persisted one-attempt intent");
        }
     }
   for(int p=0;p<ArraySize(g_risk.positions);p++)
     {
      BPositionPerformance perf=g_risk.positions[p];
      if(!perf.owned || !g_risk.IsOpen(perf.id)) continue;
      BSetup plan; BClearSetup(plan);
      bool mapped=g_store.LoadPlan(perf.entry_order,plan);
      if(!mapped && g_signal.setup.attempted && g_signal.setup.id>0 && HistoryOrderSelect(perf.entry_order) &&
         HistoryOrderGetString(perf.entry_order,ORDER_COMMENT)=="BAMD:"+(string)g_signal.setup.id && perf.symbol==g_signal.setup.symbol)
        {
         g_signal.setup.order_ticket=perf.entry_order; g_signal.setup.position_id=perf.id;
         if(!g_store.SavePlan(g_signal.setup,g_last_bar)) g_storage_fault=true;
         plan=g_signal.setup; mapped=true;
        }
      if(mapped && (g_signal.setup.position_id!=perf.id || g_signal.setup.state!=B_POSITION_OPEN))
        {
         plan.position_id=perf.id; g_signal.setup=plan;
         if(g_signal.setup.state!=B_POSITION_OPEN) Transition(B_POSITION_OPEN,now,"Recovered exclusively owned open position from authoritative history");
        }
      else if(!mapped) { g_storage_fault=true; g_diagnostic="Open EA position lacks durable plan; entries disabled; original SL/TP retained"; }
     }
   // Re-scan authoritative deal history; receipts, not callback counts, determine uniqueness.
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0 || g_journal.SeenDeal(ticket)) continue;
      ulong pid=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID); int p=-1;
      for(int j=0;j<ArraySize(g_risk.positions);j++) if(g_risk.positions[j].id==pid && g_risk.positions[j].owned) p=j;
      if(p<0) continue;
      BSetup plan; BClearSetup(plan);
      if(!g_store.LoadPlan(g_risk.positions[p].entry_order,plan))
        {
         if(g_signal.setup.order_ticket==g_risk.positions[p].entry_order) plan=g_signal.setup;
         else continue; // Unknown historical monetary risk is never invented.
        }
      plan.position_id=pid;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
      double price=HistoryDealGetDouble(ticket,DEAL_PRICE),volume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
      double commission=HistoryDealGetDouble(ticket,DEAL_COMMISSION),swap=HistoryDealGetDouble(ticket,DEAL_SWAP);
      double fee=HistoryDealGetDouble(ticket,DEAL_FEE),profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      double slip=(entry==DEAL_ENTRY_IN ? (price-plan.entry)*(int)plan.direction:0);
      plan.state=(entry==DEAL_ENTRY_IN ? B_POSITION_OPEN:plan.state);
      datetime when=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      double observed_spread=(g_risk.positions[p].symbol==_Symbol && quote.time==when ? quote.ask-quote.bid:0);
      if(!g_journal.Event(plan,when,now,"DEAL",g_signal.setup.state,
         "Authoritative history deal; spread is notification-time sample when available (0=unknown)",
         g_risk.positions[p].symbol,ticket,price,volume,observed_spread,commission,swap,fee,profit,slip,profit+commission+swap+fee)) g_storage_fault=true;
      if(plan.id==g_signal.setup.id)
        {
         g_signal.setup.position_id=pid;
         if(entry==DEAL_ENTRY_IN && g_signal.setup.state!=B_POSITION_OPEN) Transition(B_POSITION_OPEN,when,"Authoritative entry deal, including partial fills");
        }
     }
   for(int p=0;p<ArraySize(g_risk.positions);p++)
     {
      BPositionPerformance perf=g_risk.positions[p];
      if(!perf.owned || perf.foreign_entry || perf.in_volume<=0 || perf.out_volume<perf.in_volume-1e-8 || g_risk.IsOpen(perf.id) || g_journal.SeenClosed(perf.id)) continue;
      BSetup plan; BClearSetup(plan);
      if(!g_store.LoadPlan(perf.entry_order,plan)) continue;
      plan.position_id=perf.id; plan.state=B_COMPLETED;
      if(!g_journal.Event(plan,perf.last_exit,now,"TRADE_CLOSED",B_POSITION_OPEN,"Full position closed; net includes available deal costs",
         perf.symbol,0,0,perf.out_volume,0,perf.commission,perf.swap,perf.fee,perf.profit,0,perf.net,true)) g_storage_fault=true;
     }
   bool order=false,position=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || (ulong)OrderGetInteger(ORDER_MAGIC)!=StrategyMagic) continue;
      if(!BStrategyComment(OrderGetString(ORDER_COMMENT))) continue;
      order=true;
      if(g_signal.setup.order_ticket==0 || ticket!=g_signal.setup.order_ticket)
        {
         BSetup plan; BClearSetup(plan);
         if(g_store.LoadPlan(ticket,plan)) g_signal.setup=plan;
         else if(g_signal.setup.attempted && g_signal.setup.id>0 && OrderGetString(ORDER_COMMENT)=="BAMD:"+(string)g_signal.setup.id)
           { g_signal.setup.order_ticket=ticket; if(!g_store.SavePlan(g_signal.setup,g_last_bar)) g_storage_fault=true; }
         else { g_storage_fault=true; g_diagnostic="Unmapped EA order; cancellation required before entry"; }
        }
     }
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_MAGIC)==StrategyMagic)
        {
         position=true;
         if(!g_risk.SafePosition((ulong)PositionGetInteger(POSITION_IDENTIFIER)))
           { g_storage_fault=true; g_diagnostic="Magic collision or mixed position ownership; no discretionary modification permitted"; }
        }
   if(!order && !position && (g_signal.setup.state==B_ORDER_PENDING || g_signal.setup.state==B_POSITION_OPEN))
     {
      if(g_signal.setup.order_ticket>0 && HistoryOrderSelect(g_signal.setup.order_ticket))
        {
         ENUM_ORDER_STATE status=(ENUM_ORDER_STATE)HistoryOrderGetInteger(g_signal.setup.order_ticket,ORDER_STATE);
         Transition(B_COMPLETED,now,"Exposure ended; historical order state="+EnumToString(status));
        }
      else { g_storage_fault=true; g_diagnostic="Exposure absent but order history unavailable; entries disabled"; }
     }
   g_trade_dirty=false; g_last_reconcile=now;
  }

void Manage(const datetime now,const MqlTick &quote,const bool time_valid,const bool in_session,
            const bool news_blocked,const string filter_reason)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || (ulong)OrderGetInteger(ORDER_MAGIC)!=StrategyMagic) continue;
      if(!BStrategyComment(OrderGetString(ORDER_COMMENT))) continue;
      BSetup plan; BClearSetup(plan); bool mapped=g_store.LoadPlan(ticket,plan);
      if(!mapped && ticket==g_signal.setup.order_ticket) { plan=g_signal.setup; mapped=true; }
      string reason="";
      bool has_fill=false;
      for(int p=0;p<ArraySize(g_risk.positions);p++)
         if(g_risk.positions[p].owned && g_risk.positions[p].entry_order==ticket && g_risk.positions[p].in_volume>0) has_fill=true;
      bool breached=false;
      if(mapped && OrderGetString(ORDER_SYMBOL)==_Symbol)
        {
         double price=(SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)==SYMBOL_CHART_MODE_LAST ? quote.last:quote.bid);
         breached=price>0 && (plan.direction==B_LONG ? price<plan.extreme:price>plan.extreme);
        }
      if(!mapped) reason="No durable order plan after restart";
      else if(!time_valid) reason="Time conversion invalid";
      else if(!in_session) reason="Session ended";
      else if(g_risk.locked) reason="Daily risk lock";
      else if(!g_risk.valid || g_storage_fault) reason="Risk or persistence unavailable";
      else if(news_blocked) reason=filter_reason;
      else if(has_fill) reason="Partial fill observed; cancel unfilled entry remainder";
      else if(BPendingExpired(now,plan.expires_at)) reason="Unfilled entry expired";
      else if(breached) reason="Observed tick breached frozen sweep extreme";
      if(reason!="")
        {
         string outcome="";
         if(g_execution.Cancel(ticket,now,outcome))
           {
            g_journal.Event(plan,now,now,"CANCEL_REQUEST",plan.state,reason+"; "+outcome);
            g_trade_dirty=true;
           }
         else if(outcome!="") ManagementError(plan,now,reason+"; "+outcome+"; management is bounded to 3 attempts per ticket/action");
        }
     }
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || (ulong)PositionGetInteger(POSITION_MAGIC)!=StrategyMagic) continue;
      bool unprotected=PositionGetDouble(POSITION_SL)<=0 || PositionGetDouble(POSITION_TP)<=0;
      if((time_valid && !in_session) || g_risk.locked || unprotected)
        {
         string outcome="";
         if(g_execution.ClosePosition(ticket,now,g_risk,outcome))
           { g_journal.Event(g_signal.setup,now,now,"CLOSE_REQUEST",g_signal.setup.state,outcome); g_trade_dirty=true; }
         else if(outcome!="") ManagementError(g_signal.setup,now,outcome+"; protective close limited to 3 attempts; inspect remaining exposure");
        }
     }
   if(g_signal.setup.state>=B_RANGE_READY && g_signal.setup.state<=B_FVG_CONFIRMED &&
      (!time_valid || !in_session || g_risk.locked))
      Transition(B_INVALIDATED,now,(!time_valid ? "Time conversion invalid":(!in_session ? "Session ended":"Daily risk lock")));
  }

void SubmitConfirmation(const datetime now,const MqlTick &quote,const datetime session_end,const long session_id)
  {
   BSetup s=g_signal.setup;
   if(s.attempted) return;
   g_signal.setup.attempted=true; g_signal.setup.session_id=session_id;
   if(!SaveState()) { Transition(B_INVALIDATED,now,"Cannot persist one-attempt marker"); return; }
   string why=""; double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   bool ok=BPlanPrices(g_signal.setup,tick,quote.ask-quote.bid,why);
   g_signal.setup.spread_submission=quote.ask-quote.bid;
   datetime confirmation_utc=0;
   if(ok && (!g_clock.ServerToUTC(g_signal.setup.confirmed_at,confirmation_utc,why) ||
      !g_clock.UTCToServer(confirmation_utc+3*PeriodSeconds(ExecutionTimeframe),g_signal.setup.expires_at,why))) ok=false;
   if(ok && session_end<g_signal.setup.expires_at) g_signal.setup.expires_at=session_end;
   datetime utc=0;
   if(ok && !g_clock.ServerToUTC(now,utc,why)) ok=false;
   datetime boundary=(ok ? g_news.NextBoundary(utc):0),server_boundary=0;
   if(ok && boundary>0)
     {
      if(!g_clock.UTCToServer(boundary,server_boundary,why)) ok=false;
      else if(server_boundary<g_signal.setup.expires_at) g_signal.setup.expires_at=server_boundary;
     }
   if(ok && (g_storage_fault || !g_risk.EntriesAllowed(why))) { ok=false; if(g_storage_fault) why="Persistence unavailable"; }
   if(ok && g_news.Blocked(utc,why)) ok=false;
   if(ok && !BSpreadOK(g_risk_cfg,quote.ask-quote.bid,MathAbs(g_signal.setup.entry-g_signal.setup.sl),why)) ok=false;
   if(ok && !g_execution.CheckLimit(_Symbol,g_signal.setup,quote,why)) ok=false;
   if(ok && g_execution.Exposure()>0) { ok=false; why="Existing strategy exposure"; }
   if(ok && !g_execution.SymbolUnmixed(_Symbol,why)) ok=false;
   if(ok && !BSizePosition(_Symbol,g_risk_cfg,g_signal.setup,why)) ok=false;
   if(ok && BPendingExpired(now,g_signal.setup.expires_at)) { ok=false; why="No remaining entry lifetime"; }
   if(!ok) { Transition(B_INVALIDATED,now,why); return; }
   if(!g_journal.Event(g_signal.setup,g_signal.setup.confirmed_at,now,"PLAN",B_FVG_CONFIRMED,"Frozen normalized prices and monetary risk; "+why)) g_storage_fault=true;
   g_visuals.Draw(g_signal.setup,now);
   if(VisualOnly) { Transition(B_COMPLETED,now,"VisualOnly: setup displayed; no order request"); return; }
   if(!SaveState() || g_storage_fault) { Transition(B_INVALIDATED,now,"Cannot persist execution plan"); return; }
   if(!g_execution.Submit(_Symbol,g_signal.setup,why))
     { Transition(B_INVALIDATED,now,why); g_trade_dirty=true; return; }
   if(!g_store.SavePlan(g_signal.setup,g_last_bar)) g_storage_fault=true;
   Transition(B_ORDER_PENDING,now,why); g_trade_dirty=true;
  }

void ProcessBar(const datetime now,const MqlTick &quote,const long session_id,const datetime session_end)
  {
   datetime latest=iTime(_Symbol,ExecutionTimeframe,1);
   if(latest<=0 || latest<=g_last_bar) return;
   bool missed=(g_last_bar>0 && latest!=g_last_bar+PeriodSeconds(ExecutionTimeframe));
   g_last_bar=latest;
   if(missed)
     {
      if(g_signal.setup.state>=B_RANGE_READY && g_signal.setup.state<=B_FVG_CONFIRMED) Transition(B_INVALIDATED,now,"Missing completed bars/disconnection; no retrospective replay");
      else g_journal.Event(g_signal.setup,now,now,"DATA_GAP",g_signal.setup.state,"Missed bars skipped; no retrospective entries");
      SaveState(); return;
     }
   if(g_execution.Exposure()>0) { SaveState(); return; }
   if(g_signal.setup.state==B_COMPLETED || g_signal.setup.state==B_INVALIDATED)
     { Transition(B_IDLE,now,"Final setup released on a later completed candle"); g_signal.Reset(); }
   datetime closed_at=latest+PeriodSeconds(ExecutionTimeframe),end=0; bool inside=false; long sid=0; string why="";
   if(!g_clock.Session(closed_at,inside,end,sid,why) || !inside) { SaveState(); return; }
   MqlRates bars[]; ArraySetAsSeries(bars,false);
   int count=MathMax(RangeLookbackBars,3); double atr[1];
   if(CopyRates(_Symbol,ExecutionTimeframe,1,count,bars)!=count || bars[count-1].time!=latest ||
      BarsCalculated(g_atr)<ATRPeriod+1 || CopyBuffer(g_atr,0,1,1,atr)!=1 || !BFinitePositive(atr[0]))
     { Transition(B_INVALIDATED,now,"Missing completed price history or invalid completed-bar ATR; skipped"); return; }
   BTransition events[];
   g_signal.Process(bars,atr[0],closed_at,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),events);
   LogEvents(events,now,session_id); SaveState();
   if(g_signal.setup.state==B_FVG_CONFIRMED) SubmitConfirmation(now,quote,session_end,session_id);
  }

int OnInit()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) { Print("Automatic parameter optimisation is excluded"); return INIT_PARAMETERS_INCORRECT; }
   if(StrategyMagic==0 || StrategyMagic>LONG_MAX || ExecutionTimeframe==PERIOD_CURRENT || ExecutionTimeframe==PERIOD_MN1 || PeriodSeconds(ExecutionTimeframe)<=0 ||
      !MathIsValidNumber(MaxRangeATR) || !MathIsValidNumber(MinFVG_ATR) || !MathIsValidNumber(RiskPercent) ||
      !MathIsValidNumber(DailyLossPercent) || !MathIsValidNumber(RoundTripCommissionPerLot) ||
      !MathIsValidNumber(MaxSpreadStopFraction) || !MathIsValidNumber(MaxAbsoluteSpreadPrice) || !MathIsValidNumber(DayStartEquityOverride) ||
      RangeLookbackBars<3 || ATRPeriod<2 || MaxRangeATR<=0 || RangeExpiryBars<1 || ReclaimDeadlineBars<1 || FVGDeadlineBars<1 ||
      MinFVG_ATR<0 || RiskPercent<=0 || RiskPercent>100 || DailyLossPercent<=0 || DailyLossPercent>100 ||
      MaxFilledTradesPerSession<1 || MaxLosingTradesPerDay<1 || RoundTripCommissionPerLot<0 || RoundTripSlippageTicks<0 ||
      MaxSpreadStopFraction<=0 || MaxAbsoluteSpreadPrice<0 || ChartHistoryLimit<1 || DayStartEquityOverride<0 ||
      !ValidOverrideDay(DayStartEquityOverrideDate) || ((DayStartEquityOverrideDate==0)!=(DayStartEquityOverride==0)))
     { Print("Invalid strategy/risk configuration"); return INIT_PARAMETERS_INCORRECT; }
   BTimeConfig time_cfg;
   time_cfg.zone=SessionTimezone; time_cfg.broker_dst=BrokerDSTSchedule; time_cfg.broker_standard_utc_minutes=BrokerStandardUTCOffsetMinutes;
   time_cfg.weekdays_only=WeekdaysOnly;
   string why="";
   if(!ParseHM(SessionStart,time_cfg.session_start_minutes) || !ParseHM(SessionEnd,time_cfg.session_end_minutes) || !g_clock.Init(time_cfg,why))
     { Print("Invalid explicit time configuration: ",why); return INIT_PARAMETERS_INCORRECT; }
   BNewsConfig news_cfg;
   news_cfg.enabled=UseNewsFilter; news_cfg.filename=NewsCSVFile; news_cfg.currencies=NewsCurrencies;
   news_cfg.before_minutes=NewsMinutesBefore; news_cfg.after_minutes=NewsMinutesAfter;
   news_cfg.coverage_start_utc=0; news_cfg.coverage_end_utc=0;
   if(UseNewsFilter && (!BParseUTC(NewsCoverageStartUTC,news_cfg.coverage_start_utc) || !BParseUTC(NewsCoverageEndUTC,news_cfg.coverage_end_utc)))
     { Print("Enabled calendar requires explicit valid UTC coverage start and end"); return INIT_PARAMETERS_INCORRECT; }
   if(!g_news.Init(news_cfg,why)) { Print("Required calendar invalid: ",why); return INIT_FAILED; }
   BSignalConfig signal_cfg;
   signal_cfg.lookback=RangeLookbackBars; signal_cfg.atr_period=ATRPeriod; signal_cfg.max_range_atr=MaxRangeATR;
   signal_cfg.range_expiry_bars=RangeExpiryBars; signal_cfg.reclaim_bars=ReclaimDeadlineBars; signal_cfg.fvg_bars=FVGDeadlineBars; signal_cfg.min_fvg_atr=MinFVG_ATR;
   g_signal.Init(signal_cfg);
   g_risk_cfg.percent=RiskPercent; g_risk_cfg.daily_loss_percent=DailyLossPercent; g_risk_cfg.max_fills_session=MaxFilledTradesPerSession;
   g_risk_cfg.max_losses_day=MaxLosingTradesPerDay; g_risk_cfg.commission_roundtrip_per_lot=RoundTripCommissionPerLot;
   g_risk_cfg.slippage_ticks_roundtrip=RoundTripSlippageTicks; g_risk_cfg.max_spread_fraction=MaxSpreadStopFraction; g_risk_cfg.max_spread_price=MaxAbsoluteSpreadPrice;
   bool tester=(bool)MQLInfoInteger(MQL_TESTER);
   if(!g_store.Init(StrategyMagic,tester,why)) { Print(why); return INIT_FAILED; }
   if(tester && ResetFilesAtTesterStart && !g_store.ResetTesterFiles()) { Print("Cannot reset isolated tester research files"); return INIT_FAILED; }
   string config=Configuration(); g_config=(string)BHash(config);
   int h=FileOpen(g_store.Prefix()+"_config_"+g_config+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI|(tester ? 0:FILE_COMMON),0,CP_UTF8);
   if(h==INVALID_HANDLE) { Print("Cannot persist configuration"); return INIT_FAILED; }
   FileWriteString(h,config); FileClose(h);
   if(!g_journal.Init(g_store.Prefix(),_Symbol,ExecutionTimeframe,g_config,tester)) { Print("Cannot open journals"); return INIT_FAILED; }
   g_risk.Init(StrategyMagic,g_risk_cfg,g_store.Prefix(),tester);
   g_execution.Init(StrategyMagic,VisualOnly,AllowDemoTrading,AllowRealAccountTrading); g_visuals.Init(StrategyMagic,ChartHistoryLimit);
   bool exists=false;
   if(!g_store.Load(g_signal.setup,g_last_bar,exists) && exists) { g_storage_fault=true; g_diagnostic="Active snapshot corrupt; entries disabled"; BClearSetup(g_signal.setup); }
   g_atr=iATR(_Symbol,ExecutionTimeframe,ATRPeriod);
   if(g_atr==INVALID_HANDLE) { Print("Cannot create native ATR indicator"); return INIT_FAILED; }
   g_ready=true;
   Print("Biltech AMD rule ",B_RULE_VERSION," config=",g_config," VisualOnly=",VisualOnly," realPermission=",AllowRealAccountTrading,
      ". Unknown commission/slippage omitted when allowances are zero. No profitability claim.");
   Comment("Biltech AMD research initialized. Waiting for first observed tick. Broker clock explicitly configured.");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   if(!g_ready) return;
   MqlTick quote={}; if(!SymbolInfoTick(_Symbol,quote) || quote.time<=0 || quote.bid<=0 || quote.ask<quote.bid) return;
   datetime now=quote.time,utc=0,session_end=0,local=0; long session_id=0; bool in_session=false;
   string why=""; bool time_valid=g_clock.ServerToUTC(now,utc,why) && g_clock.Session(now,in_session,session_end,session_id,why) && g_clock.LocalTime(now,local,why);
   bool blocked=(!time_valid || g_news.Blocked(utc,why));
   if(g_trade_dirty || now-g_last_reconcile>=1) Reconcile(now,quote,session_id);
   g_risk.ObserveFloating();
   if(!g_started)
     {
      g_started=true;
      if(g_signal.setup.state>=B_RANGE_READY && g_signal.setup.state<=B_FVG_CONFIRMED)
         Transition(B_INVALIDATED,now,"Unsubmitted setup discarded on attachment/restart; no replay");
      g_last_bar=iTime(_Symbol,ExecutionTimeframe,1); SaveState();
     }
   Manage(now,quote,time_valid,in_session,blocked,why);
   if(time_valid && in_session && !blocked && !g_risk.locked && !g_storage_fault) ProcessBar(now,quote,session_id,session_end);
   else
     {
      // Mark unprocessed blocked bars as skipped, so lifting a filter cannot enter retrospectively.
      datetime latest=iTime(_Symbol,ExecutionTimeframe,1);
      if(latest>g_last_bar)
        {
         g_last_bar=latest;
         if(g_signal.setup.state>=B_RANGE_READY && g_signal.setup.state<=B_FVG_CONFIRMED)
            Transition(B_INVALIDATED,now,"Required session/news/risk filter blocked completed bar");
         SaveState();
        }
     }
   if(now-g_last_equity>=60) { g_journal.Equity(now); g_last_equity=now; }
   Comment("Biltech AMD FVG Research ",B_RULE_VERSION," | ",_Symbol," ",EnumToString(ExecutionTimeframe),
      "\nBroker: ",TimeToString(now,TIME_DATE|TIME_SECONDS)," | Session-local: ",(time_valid ? TimeToString(local,TIME_DATE|TIME_SECONDS):"INVALID: "+why),
      "\n",BStateName(g_signal.setup.state)," #",g_signal.setup.id," | ",g_signal.setup.reason,
      "\nVisualOnly=",VisualOnly," DemoPermission=",AllowDemoTrading," RealPermission=",AllowRealAccountTrading,
      "\nSession=",in_session," NewsBlocked=",blocked," DailyLocked=",g_risk.locked," RiskValid=",g_risk.valid,
      "\nFills=",g_risk.session_fills," Losses=",g_risk.day_losses," DayStartEquity=",DoubleToString(g_risk.day_equity,2),
      " EA day net+float=",DoubleToString(g_risk.day_net+g_risk.floating,2),
      "\n",g_risk.diagnostic," ",g_diagnostic);
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   // Keep the handler bounded: reconcile account/history on next observed tick.
   // Duplicate/out-of-order callbacks do not increment risk counters.
   g_trade_dirty=true;
  }

void OnDeinit(const int reason)
  {
   if(g_ready) SaveState();
   if(g_atr!=INVALID_HANDLE) IndicatorRelease(g_atr);
   g_journal.Close(); g_store.Close(); Comment("");
  }
