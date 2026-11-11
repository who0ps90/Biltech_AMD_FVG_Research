#ifndef BILTECH_AMD_SIGNAL_MQH
#define BILTECH_AMD_SIGNAL_MQH
#include "Types.mqh"

// Feed chronological completed bars. closed_at is the knowledge time of the
// newest candle (normally its open plus PeriodSeconds(signal timeframe)).
// Session admission and final order prices belong to the EA/execution layer.
class BSignalEngine
  {
private:
   BSignalConfig m_cfg;
   datetime m_last_bar_open;
   datetime m_last_closed_at;

   void Transition(const BState next,const datetime at,const string reason,
                   BTransition &events[])
     {
      BState previous=setup.state;
      setup.state=next;
      setup.reason=reason;
      int n=ArraySize(events);
      ArrayResize(events,n+1);
      events[n].from_state=previous;
      events[n].to_state=next;
      events[n].at=at;
      events[n].snapshot=setup;
      events[n].reason=reason;
     }

   bool Inside(const double close_price)
     {
      return close_price>setup.range_low && close_price<setup.range_high;
     }

   bool ConfigValid()
     {
      return m_cfg.lookback>=1 && m_cfg.atr_period>=1 &&
             BFinitePositive(m_cfg.max_range_atr) && m_cfg.range_expiry_bars>=1 &&
             m_cfg.reclaim_bars>=1 && m_cfg.fvg_bars>=1 &&
             MathIsValidNumber(m_cfg.min_fvg_atr) && m_cfg.min_fvg_atr>=0.0;
     }

   bool BarsValid(const MqlRates &bars[],const datetime closed_at)
     {
      int n=ArraySize(bars);
      if(n<1 || bars[n-1].time<=0 || closed_at<=bars[n-1].time)
         return false;
      for(int i=0;i<n;i++)
        {
         if((i>0 && bars[i].time<=bars[i-1].time) ||
            !MathIsValidNumber(bars[i].open) || !MathIsValidNumber(bars[i].high) ||
            !MathIsValidNumber(bars[i].low) || !MathIsValidNumber(bars[i].close) ||
            bars[i].high<bars[i].low || bars[i].open>bars[i].high ||
            bars[i].open<bars[i].low || bars[i].close>bars[i].high ||
            bars[i].close<bars[i].low)
            return false;
        }
      return true;
     }

   bool TryFVG(const MqlRates &bars[],const double atr,const datetime closed_at,
               const double tick_size,BTransition &events[])
     {
      int n=ArraySize(bars);
      if(n<3 || setup.state!=B_RECLAIMED)
         return false;
      MqlRates a=bars[n-3],b=bars[n-2],c=bars[n-1];
      if(b.time<setup.sweep_bar_open || closed_at<setup.reclaim_at || !Inside(c.close))
         return false;

      double lower=0.0,upper=0.0;
      if(setup.direction==B_LONG)
        {
         if(c.low<=a.high || c.close<=b.high)
            return false;
         lower=a.high;
         upper=c.low;
        }
      else if(setup.direction==B_SHORT)
        {
         if(c.high>=a.low || c.close>=b.low)
            return false;
         lower=c.high;
         upper=a.low;
        }
      else
         return false;

      double gap=upper-lower;
      double epsilon=tick_size*1e-7;
      if(gap+epsilon<tick_size ||
         (m_cfg.min_fvg_atr>0.0 && gap+epsilon<m_cfg.min_fvg_atr*atr))
         return false;
      setup.zone_low=lower;
      setup.zone_high=upper;
      setup.atr_confirmation=atr;
      setup.confirmed_at=closed_at;
      Transition(B_FVG_CONFIRMED,closed_at,
                 setup.direction==B_LONG ? "First qualifying bullish FVG confirmed" :
                                           "First qualifying bearish FVG confirmed",events);
      return true;
     }

   void AfterReclaim(const MqlRates &bars[],const double atr,const datetime closed_at,
                     const double tick_size,BTransition &events[])
     {
      if(TryFVG(bars,atr,closed_at,tick_size,events))
         return;
      // Inclusive deadline: evaluate the third candle, then invalidate if absent.
      if(setup.reclaim_age>=m_cfg.fvg_bars)
         Invalidate(closed_at,"No qualifying FVG within the inclusive reclaim deadline",events);
     }

   void Reclaim(const MqlRates &bars[],const double atr,const datetime closed_at,
                const double tick_size,BTransition &events[])
     {
      setup.reclaim_at=closed_at;
      setup.reclaim_age=1;
      Transition(B_RECLAIMED,closed_at,"Completed candle closed strictly inside frozen range",events);
      AfterReclaim(bars,atr,closed_at,tick_size,events);
     }

public:
   BSetup setup;

   void Init(const BSignalConfig &cfg)
     {
      m_cfg=cfg;
      m_last_bar_open=0;
      m_last_closed_at=0;
      BClearSetup(setup);
     }

   // Preserve the once-per-bar guard across a final-state reset. The caller
   // resets only on a later completed bar; never re-use a rejected range bar.
   void Reset()
     {
      BClearSetup(setup);
     }

   void Invalidate(const datetime at,const string reason,BTransition &events[])
     {
      if(setup.state==B_INVALIDATED || setup.state==B_COMPLETED)
         return;
      Transition(B_INVALIDATED,at,reason,events);
     }

   // Returns true exactly when one or more events were appended. It does not
   // clear events. Final states remain frozen for the owner's reconciliation.
   bool Process(const MqlRates &bars[],const double atr,const datetime closed_at,
                const double tick_size,BTransition &events[])
     {
      int before=ArraySize(events);
      int n=ArraySize(bars);
      if(n>0 && (bars[n-1].time<=m_last_bar_open || closed_at<=m_last_closed_at))
         return false;
      if(n>0)
        {
         m_last_bar_open=bars[n-1].time;
         m_last_closed_at=closed_at;
        }
      if(setup.state==B_FVG_CONFIRMED || setup.state==B_ORDER_PENDING ||
         setup.state==B_POSITION_OPEN || setup.state==B_COMPLETED || setup.state==B_INVALIDATED)
         return false;
      if(!ConfigValid() || !BFinitePositive(atr) || !BFinitePositive(tick_size) ||
         !BarsValid(bars,closed_at) || (setup.state==B_IDLE && n<m_cfg.lookback))
        {
         Invalidate(closed_at,"Invalid configuration, chronological price history, ATR, or tick size",events);
         return ArraySize(events)>before;
        }

      MqlRates current=bars[n-1];
      if(setup.state==B_IDLE)
        {
         double hi=bars[n-m_cfg.lookback].high;
         double lo=bars[n-m_cfg.lookback].low;
         for(int i=n-m_cfg.lookback+1;i<n;i++)
           {
            hi=MathMax(hi,bars[i].high);
            lo=MathMin(lo,bars[i].low);
           }
         double width=hi-lo;
         if(width>0.0 && width<=m_cfg.max_range_atr*atr)
           {
            setup.id=(long)closed_at;
            setup.range_start=bars[n-m_cfg.lookback].time;
            setup.qualified_at=closed_at;
            setup.range_high=hi;
            setup.range_low=lo;
            Transition(B_RANGE_READY,closed_at,"First qualifying accumulation range frozen",events);
           }
         // The qualification candle can never be used as its own sweep.
         return ArraySize(events)>before;
        }

      double epsilon=tick_size*1e-7;
      bool down=current.low<=setup.range_low-tick_size+epsilon;
      bool up=current.high>=setup.range_high+tick_size-epsilon;
      if(setup.state==B_RANGE_READY)
        {
         setup.range_age++;
         if(down && up)
            Invalidate(closed_at,"Ambiguous candle breached both frozen range boundaries",events);
         else if(down || up)
           {
            setup.direction=down ? B_LONG : B_SHORT;
            setup.extreme=down ? current.low : current.high;
            setup.sweep_bar_open=current.time;
            setup.swept_at=closed_at;
            setup.sweep_age=1;
            Transition(B_SWEPT,closed_at,down ? "Downside sweep: potential long" :
                                               "Upside sweep: potential short",events);
            if(Inside(current.close))
               Reclaim(bars,atr,closed_at,tick_size,events);
            else if(setup.sweep_age>=m_cfg.reclaim_bars)
               Invalidate(closed_at,"No reclaim within the inclusive sweep deadline",events);
           }
         // Convention: permit a sweep on bar 20. Expire at its close if unswept.
         else if(setup.range_age>=m_cfg.range_expiry_bars)
            Invalidate(closed_at,"Unswept range expired after subsequent completed candles",events);
         return ArraySize(events)>before;
        }

      if((setup.direction==B_LONG && up) || (setup.direction==B_SHORT && down))
        {
         Invalidate(closed_at,"Both frozen range boundaries breached before FVG confirmation",events);
         return ArraySize(events)>before;
        }
      if(setup.state==B_SWEPT)
        {
         setup.sweep_age++;
         setup.extreme=setup.direction==B_LONG ? MathMin(setup.extreme,current.low) :
                                                MathMax(setup.extreme,current.high);
         if(Inside(current.close))
            Reclaim(bars,atr,closed_at,tick_size,events);
         else if(setup.sweep_age>=m_cfg.reclaim_bars)
            Invalidate(closed_at,"No reclaim within the inclusive sweep deadline",events);
         return ArraySize(events)>before;
        }

      if(setup.state==B_RECLAIMED)
        {
         setup.reclaim_age++;
         if((setup.direction==B_LONG && current.low<setup.extreme-epsilon) ||
            (setup.direction==B_SHORT && current.high>setup.extreme+epsilon))
           {
            Invalidate(closed_at,"A subsequent completed candle extended the frozen sweep extreme",events);
            return ArraySize(events)>before;
           }
         AfterReclaim(bars,atr,closed_at,tick_size,events);
        }
      return ArraySize(events)>before;
     }
  };
#endif
