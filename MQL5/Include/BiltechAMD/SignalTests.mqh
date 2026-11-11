#ifndef BILTECH_AMD_SIGNAL_TESTS_MQH
#define BILTECH_AMD_SIGNAL_TESTS_MQH
#include "Signal.mqh"

// Deterministic native fixtures: no account, order, terminal data, or tick APIs.
// Each Add supplies one newly completed five-minute candle.
class BSignalFixture
  {
public:
   BSignalEngine engine;
   MqlRates bars[];
   BTransition events[];

   void Set(const int i,const double o,const double h,const double l,const double c)
     {
      ZeroMemory(bars[i]);
      bars[i].time=D'2024.01.08 09:00:00'+i*300;
      bars[i].open=o;
      bars[i].high=h;
      bars[i].low=l;
      bars[i].close=c;
     }

   void Prepare(const BSignalConfig &cfg)
     {
      engine.Init(cfg);
      ArrayResize(events,0);
      ArrayResize(bars,3);
      ArraySetAsSeries(bars,false);
      for(int i=0;i<3;i++)
         Set(i,104.0,110.0,100.0,105.0);
     }

   void Qualify()
     {
      engine.Process(bars,10.0,bars[2].time+300,0.1,events);
     }

   void Start(const BSignalConfig &cfg)
     {
      Prepare(cfg);
      Qualify();
     }

   bool Add(const double o,const double h,const double l,const double c,
            const double atr=10.0,const double tick=0.1)
     {
      int i=ArraySize(bars);
      ArrayResize(bars,i+1);
      Set(i,o,h,l,c);
      return engine.Process(bars,atr,bars[i].time+300,tick,events);
     }
  };

BSignalConfig BFixtureSignalConfig()
  {
   BSignalConfig cfg;
   cfg.lookback=3;
   cfg.atr_period=14;
   cfg.max_range_atr=3.0;
   cfg.range_expiry_bars=20;
   cfg.reclaim_bars=3;
   cfg.fvg_bars=3;
   cfg.min_fvg_atr=0.0;
   return cfg;
  }

void BSignalAssert(const bool condition,const string label,int &failed,int &checks)
  {
   checks++;
   if(!condition)
      failed++;
   PrintFormat("%s signal.%s",condition ? "PASS" : "FAIL",label);
  }

bool BSignalNear(const double a,const double b)
  {
   return MathAbs(a-b)<1e-8;
  }

int BRunSignalTests()
  {
   int failed=0,checks=0;
   BSignalConfig cfg=BFixtureSignalConfig();

   // The complete long path uses three distinct event candles after the range.
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,99.5);
    f.Add(100,105,99.5,102);
    f.Add(105,108,104,106,20.0);
    BSignalAssert(f.engine.setup.state==B_FVG_CONFIRMED,"valid_long.confirmed",failed,checks);
    BSignalAssert(f.engine.setup.direction==B_LONG,"valid_long.direction",failed,checks);
    BSignalAssert(BSignalNear(f.engine.setup.zone_low,103) && BSignalNear(f.engine.setup.zone_high,104),"valid_long.zone",failed,checks);
    BSignalAssert(BSignalNear(f.engine.setup.extreme,99) && BSignalNear(f.engine.setup.atr_confirmation,20),"valid_long.frozen_inputs",failed,checks);
    BSignalAssert(ArraySize(f.events)==4 && f.events[3].from_state==B_RECLAIMED && f.events[3].to_state==B_FVG_CONFIRMED,"valid_long.transition_sequence",failed,checks);
    BSignalAssert(f.events[3].at==f.bars[5].time+300 && f.events[3].snapshot.confirmed_at==f.events[3].at,"valid_long.knowledge_timestamp",failed,checks);
    BSignalAssert(BSignalNear(f.events[0].snapshot.zone_low,0) && f.events[0].snapshot.state==B_RANGE_READY,"valid_long.event_snapshot_not_mutated",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(109,111,107,110.5);
    f.Add(110,110.5,105,108);
    f.Add(105,106,102,104);
    BSignalAssert(f.engine.setup.state==B_FVG_CONFIRMED && f.engine.setup.direction==B_SHORT,"valid_short.confirmed",failed,checks);
    BSignalAssert(BSignalNear(f.engine.setup.zone_low,106) && BSignalNear(f.engine.setup.zone_high,107),"valid_short.zone",failed,checks);
    BSignalAssert(BSignalNear(f.engine.setup.extreme,111),"valid_short.extreme",failed,checks);
   }

   // The first sweep candle is candle one for reclaim; its close can reclaim.
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,102,99,101);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED && f.engine.setup.sweep_age==1,"same_candle_reclaim.accepted",failed,checks);
    BSignalAssert(f.events[1].at==f.events[2].at && f.events[1].to_state==B_SWEPT && f.events[2].to_state==B_RECLAIMED,"same_candle_reclaim.two_events",failed,checks);
    f.Add(103,106,103,105);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED,"same_candle_reclaim.waits_for_eligible_fvg",failed,checks);
    f.Add(106,108,104,107);
    BSignalAssert(f.engine.setup.state==B_FVG_CONFIRMED && f.engine.setup.reclaim_age==3,"fvg_deadline.third_candle_accepted",failed,checks);
   }

   // Reclaim and confirmation may share C. B already touched the future gap
   // midpoint (102.5), which cannot be a historical entry before C is known.
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(99.5,102,99,99.5);
    f.Add(99.5,104,99.2,99.6);
    BSignalAssert(f.engine.setup.state==B_SWEPT,"confirmation_on_reclaim.still_swept_before_c",failed,checks);
    f.Add(104,107,103,106);
    double midpoint=(f.engine.setup.zone_low+f.engine.setup.zone_high)/2.0;
    BSignalAssert(f.engine.setup.state==B_FVG_CONFIRMED && f.engine.setup.sweep_age==3,"reclaim_deadline.third_candle_accepted",failed,checks);
    BSignalAssert(f.engine.setup.reclaim_at==f.engine.setup.confirmed_at,"confirmation_on_reclaim.same_knowledge_time",failed,checks);
    BSignalAssert(f.bars[4].low<=midpoint && f.bars[4].high>=midpoint,"preconfirmation_midpoint.was_touched",failed,checks);
    BSignalAssert(!f.engine.setup.attempted && f.engine.setup.order_ticket==0 && f.engine.setup.state==B_FVG_CONFIRMED,"preconfirmation_midpoint.no_retrospective_order",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,109,99,99.5);
    f.Add(99,109,98.5,99);
    BSignalAssert(f.engine.setup.state==B_SWEPT && f.engine.setup.sweep_age==2,"no_reclaim.second_candle_waits",failed,checks);
    f.Add(99,109,98,99);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && f.engine.setup.sweep_age==3,"no_reclaim.third_candle_rejected",failed,checks);
    int events=ArraySize(f.events);
    f.Add(101,108,100.5,105);
    BSignalAssert(ArraySize(f.events)==events && f.engine.setup.state==B_INVALIDATED,"no_reclaim.fourth_candle_cannot_revive",failed,checks);
   }

   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(105,110.1,99.9,105);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && f.engine.setup.direction==B_NONE,"ambiguous_double_sweep.same_candle",failed,checks);
    BSignalAssert(ArraySize(f.events)==2 && f.events[1].from_state==B_RANGE_READY,"ambiguous_double_sweep.no_assumed_tick_order",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,99.5);
    f.Add(105,110.1,99.5,105);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED,"double_sweep.before_reclaim",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,101);
    f.Add(105,110.1,100.5,105);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED,"double_sweep.after_reclaim_before_fvg",failed,checks);
   }

   // A geometric bullish gap exists below the range, before any valid reclaim.
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(99.4,99.6,99,99.4);
    f.Add(99.5,99.8,99.3,99.7);
    f.Add(99.9,99.95,99.85,99.9);
    BSignalAssert(f.bars[5].low>f.bars[3].high && f.bars[5].close>f.bars[4].high,"premature_fvg.geometry_exists",failed,checks);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && f.engine.setup.confirmed_at==0,"premature_fvg.rejected_without_reclaim",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,101);
    f.Add(101,104,98.9,102);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && BSignalNear(f.engine.setup.extreme,99),"post_reclaim_extreme.long_rejected_and_frozen",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(109,111,107,109);
    f.Add(109,111.1,106,108);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && BSignalNear(f.engine.setup.extreme,111),"post_reclaim_extreme.short_rejected_and_frozen",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,99.5);
    f.Add(99.5,104,98.5,101);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED && BSignalNear(f.engine.setup.extreme,98.5),"sweep_sequence.extreme_extends_until_reclaim",failed,checks);
    f.Add(101,104,98.5,102);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED,"post_reclaim_extreme.equal_price_allowed",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,105,99,101);
    f.Add(101,105,100,101);
    f.Add(101,105,100,101);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && f.engine.setup.reclaim_age==3,"fvg_deadline.absent_on_third_candle_rejected",failed,checks);
   }

   {
    BSignalFixture f;
    f.Start(cfg);
    BSignalAssert(f.engine.setup.state==B_RANGE_READY && f.engine.setup.range_age==0 && f.engine.setup.swept_at==0,"qualification_bar.not_reused_as_sweep",failed,checks);
    datetime qualified=f.engine.setup.qualified_at;
    f.Add(105,109,101,105);
    BSignalAssert(BSignalNear(f.engine.setup.range_low,100) && BSignalNear(f.engine.setup.range_high,110) && f.engine.setup.qualified_at==qualified,"first_range.boundaries_and_time_frozen",failed,checks);
    BSignalAssert(ArraySize(f.events)==1,"first_range.no_repeated_qualification",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    for(int i=1;i<=19;i++)
       f.Add(105,109,101,105);
    BSignalAssert(f.engine.setup.state==B_RANGE_READY && f.engine.setup.range_age==19,"range_expiry.nineteenth_bar_active",failed,checks);
    f.Add(105,109,101,105);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED && f.engine.setup.range_age==20,"range_expiry.twentieth_unswept_bar_expires",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    for(int i=1;i<=19;i++)
       f.Add(105,109,101,105);
    f.Add(101,103,99,101);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED && f.engine.setup.range_age==20,"range_expiry.twentieth_bar_sweep_allowed",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,99.5);
    f.Add(100,105,99.5,102);
    f.Add(105,108,104,106);
    int events=ArraySize(f.events);
    double lower=f.engine.setup.zone_low,upper=f.engine.setup.zone_high;
    datetime confirmation=f.engine.setup.confirmed_at;
    f.Add(105,120,90,105);
    BSignalAssert(ArraySize(f.events)==events && f.engine.setup.state==B_FVG_CONFIRMED,"first_fvg.terminal_signal_not_reprocessed",failed,checks);
    BSignalAssert(BSignalNear(f.engine.setup.zone_low,lower) && BSignalNear(f.engine.setup.zone_high,upper) && f.engine.setup.confirmed_at==confirmation,"first_fvg.zone_and_time_frozen",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    int events=ArraySize(f.events);
    bool emitted=f.engine.Process(f.bars,10,f.bars[2].time+300,0.1,f.events);
    BSignalAssert(!emitted && ArraySize(f.events)==events && f.engine.setup.range_age==0,"duplicate_bar.ignored",failed,checks);
    f.engine.Reset();
    emitted=f.engine.Process(f.bars,10,f.bars[2].time+300,0.1,f.events);
    BSignalAssert(!emitted && f.engine.setup.state==B_IDLE,"duplicate_bar.reset_preserves_guard",failed,checks);
    f.Add(105,109,101,105);
    BSignalAssert(f.engine.setup.state==B_RANGE_READY && f.engine.setup.qualified_at==f.bars[3].time+300,"reset.next_bar_can_qualify",failed,checks);
   }

   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99.95,101);
    BSignalAssert(f.engine.setup.state==B_RANGE_READY,"sweep_threshold.sub_tick_breach_ignored",failed,checks);
    f.Add(101,103,99.9,101);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED,"sweep_threshold.exact_one_tick_accepted",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(101,103,99,99.5,10,1.0);
    f.Add(100,105,99.5,102,10,1.0);
    f.Add(105,108,103.5,106,10,1.0);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED && f.engine.setup.confirmed_at==0,"minimum_fvg.sub_tick_gap_rejected",failed,checks);
   }
   {
    BSignalConfig filtered=cfg;
    filtered.min_fvg_atr=0.2;
    BSignalFixture f;
    f.Start(filtered);
    f.Add(101,103,99,99.5);
    f.Add(100,105,99.5,102);
    f.Add(105,108,104,106);
    BSignalAssert(f.engine.setup.state==B_RECLAIMED && f.engine.setup.confirmed_at==0,"minimum_fvg.optional_atr_filter",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(105,109,101,105,0);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED,"invalid_input.zero_atr_fails_closed",failed,checks);
   }
   {
    BSignalFixture f;
    f.Prepare(cfg);
    f.bars[1].time=f.bars[0].time;
    f.Qualify();
    BSignalAssert(f.engine.setup.state==B_INVALIDATED,"invalid_input.nonchronological_history_fails_closed",failed,checks);
   }
   {
    BSignalFixture f;
    f.Start(cfg);
    f.Add(105,109,101,105,10,0);
    BSignalAssert(f.engine.setup.state==B_INVALIDATED,"invalid_input.zero_tick_fails_closed",failed,checks);
   }

   PrintFormat("SIGNAL TEST SUMMARY: checks=%d passed=%d failed=%d",checks,checks-failed,failed);
   return failed;
  }
#endif
