#ifndef BILTECH_AMD_RISK_MQH
#define BILTECH_AMD_RISK_MQH
#include "Types.mqh"
#include "Time.mqh"

struct BRiskConfig
  {
   double percent;
   double daily_loss_percent;
   int max_fills_session;
   int max_losses_day;
   double commission_roundtrip_per_lot;
   int slippage_ticks_roundtrip;
   double max_spread_fraction;
   double max_spread_price;
  };

double BVolumeDown(const double raw,const double step,const double minimum,const double maximum)
  {
   if(!BFinitePositive(raw) || !BFinitePositive(step) || !BFinitePositive(minimum) || maximum<minimum)
      return 0;
   double volume=NormalizeDouble(MathFloor((MathMin(raw,maximum)+1e-12)/step)*step,8);
   if(volume<minimum-1e-10 || volume>raw+1e-10) return 0;
   return volume;
  }

bool BPlanPrices(BSetup &s,const double tick,const double spread,string &why)
  {
   if(!BFinitePositive(tick) || !MathIsValidNumber(spread) || spread<0 ||
      !BFinitePositive(s.atr_confirmation) || s.zone_high<=s.zone_low || s.direction==B_NONE)
     { why="Invalid tick, spread, ATR or FVG data"; return false; }
   double midpoint=(s.zone_low+s.zone_high)/2;
   double buffer=MathMax(2*tick,MathMax(spread,0.10*s.atr_confirmation));
   // A half-tick midpoint is rounded toward the passive side, by at most half a tick.
   s.entry=(s.direction==B_LONG ? BTickFloor(midpoint,tick) : BTickCeil(midpoint,tick));
   s.sl=(s.direction==B_LONG ? BTickFloor(s.extreme-buffer,tick) : BTickCeil(s.extreme+buffer,tick));
   double distance=MathAbs(s.entry-s.sl);
   s.tp=(s.direction==B_LONG ? BTickCeil(s.entry+2*distance,tick) : BTickFloor(s.entry-2*distance,tick));
   if(!BFinitePositive(s.sl) || !BFinitePositive(s.tp) || distance<tick ||
      (s.direction==B_LONG && (s.sl>=s.entry || s.tp>s.range_high+tick*1e-7)) ||
      (s.direction==B_SHORT && (s.sl<=s.entry || s.tp<s.range_low-tick*1e-7)))
     { why="Insufficient 2R room inside frozen range after tick normalization"; return false; }
   double reward=MathAbs(s.tp-s.entry);
   if(reward/distance<2.0-1e-8)
     { why="Normalized reward/risk below 2"; return false; }
   why="Prices frozen; actual normalized reward/risk="+DoubleToString(reward/distance,8);
   return true;
  }

bool BSpreadOK(const BRiskConfig &cfg,const double spread,const double stop_distance,string &why)
  {
   if(!MathIsValidNumber(spread) || spread<0 || !BFinitePositive(stop_distance))
     { why="Invalid live bid/ask spread or planned stop distance"; return false; }
   if(spread>cfg.max_spread_fraction*stop_distance+1e-12 ||
      (cfg.max_spread_price>0 && spread>cfg.max_spread_price+1e-12))
     { why="Submission spread exceeds configured cap"; return false; }
   return true;
  }

bool BSizePosition(const string symbol,const BRiskConfig &cfg,BSetup &s,string &why)
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double reference=minimum;
   double loss=0,slip=0;
   ENUM_ORDER_TYPE direction=(s.direction==B_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double adverse=s.sl+(s.direction==B_LONG ? -1:1)*cfg.slippage_ticks_roundtrip*tick;
   if(!BFinitePositive(equity) || !BFinitePositive(reference) || !BFinitePositive(tick) ||
      !OrderCalcProfit(direction,symbol,reference,s.entry,s.sl,loss) || loss>=0 ||
      !OrderCalcProfit(direction,symbol,reference,s.sl,adverse,slip))
     { why="OrderCalcProfit/account-currency conversion unavailable or invalid"; return false; }
   double per_lot=(-loss+MathAbs(slip))/reference+cfg.commission_roundtrip_per_lot;
   double budget=equity*cfg.percent/100;
   if(!BFinitePositive(per_lot) || !BFinitePositive(budget))
     { why="Invalid risk budget"; return false; }
   s.volume=BVolumeDown(budget/per_lot,step,minimum,maximum);
   s.planned_risk_money=s.volume*per_lot;
   if(s.volume<=0 || s.planned_risk_money>budget+1e-7)
     { why="Minimum volume exceeds risk budget; no rounding up"; return false; }
   double margin=0;
   if(!OrderCalcMargin(direction,symbol,s.volume,s.entry,margin) ||
      !MathIsValidNumber(margin) || margin<0 || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     { why="Margin calculation failed or insufficient free margin"; return false; }
   return true;
  }

struct BPositionPerformance
  {
   ulong id;
   ulong entry_order;
   datetime first_entry;
   datetime last_exit;
   string symbol;
   bool owned;
   bool foreign_entry;
   double in_volume;
   double out_volume;
   double net;
   double commission;
   double swap;
   double fee;
   double profit;
  };

// Rebuilt from authoritative history; repeated transaction notifications cannot increment counters.
class BRiskLedger
  {
private:
   ulong m_magic;
   BRiskConfig m_cfg;
   string m_prefix;
   int m_flags;
   bool m_history_valid;
   bool ReadDay(const long day)
     {
      string file=m_prefix+"_day_"+(string)day+".csv";
      if(!FileIsExist(file,m_flags)) return false;
      int h=FileOpen(file,FILE_READ|FILE_CSV|FILE_ANSI|m_flags,',');
      if(h==INVALID_HANDLE) return false;
      string schema=FileReadString(h);
      long stored=(long)FileReadNumber(h);
      day_equity=FileReadNumber(h);
      locked=(FileReadNumber(h)>0);
      string footer=FileReadString(h);
      FileClose(h);
      return schema=="BAMD_DAY_1" && stored==day && BFinitePositive(day_equity) && footer=="BEND";
     }
   bool WriteDay()
     {
      string path=m_prefix+"_day_"+(string)day_id+".csv";
      int h=FileOpen(path+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|m_flags,',');
      if(h==INVALID_HANDLE) return false;
      bool ok=FileWrite(h,"BAMD_DAY_1",day_id,day_equity,(int)locked,"BEND")>0;
      FileFlush(h); FileClose(h);
      return ok && FileMove(path+".tmp",m_flags,path,FILE_REWRITE|m_flags);
     }
public:
   BPositionPerformance positions[];
   double day_equity;
   double day_net;
   double floating;
   int session_fills;
   int day_losses;
   bool locked;
   bool valid;
   long day_id;
   string diagnostic;

   void Init(const ulong magic,const BRiskConfig &cfg,const string prefix,const bool tester)
     {
      m_magic=magic; m_cfg=cfg; m_prefix=prefix; m_flags=(tester ? 0:FILE_COMMON);
      day_id=0; day_equity=0; locked=false; valid=false; m_history_valid=false;
     }
   int Find(const ulong id)
     {
      for(int i=0;i<ArraySize(positions);i++) if(positions[i].id==id) return i;
      int n=ArraySize(positions); ArrayResize(positions,n+1); ZeroMemory(positions[n]); positions[n].id=id; return n;
     }
   bool IsOpen(const ulong id)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return true;
      return false;
     }
   bool Refresh(BTimeRules &clock,const datetime now,const long current_session,
                const long override_day,const double override_equity)
     {
      valid=false; m_history_valid=false; diagnostic="";
      datetime day_start=0; long today=0;
      if(!clock.DayBounds(now,day_start,today,diagnostic)) return false;
      if(!HistorySelect(0,now)) { diagnostic="Full account history unavailable"; return false; }
      ArrayResize(positions,0);
      double all_day_cash=0;
      int deals=HistoryDealsTotal();
      for(int i=0;i<deals;i++)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) { diagnostic="History deal read failed"; return false; }
         datetime when=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
         double net=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
                    HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
         if(when>=day_start) all_day_cash+=net;
         ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
         if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
         ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         int p=Find(id);
         positions[p].symbol=HistoryDealGetString(ticket,DEAL_SYMBOL);
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
           {
            ulong entry_order=(ulong)HistoryDealGetInteger(ticket,DEAL_ORDER);
            string original_comment=HistoryOrderGetString(entry_order,ORDER_COMMENT);
            if(original_comment=="" && OrderSelect(entry_order)) original_comment=OrderGetString(ORDER_COMMENT);
            bool tagged=BStrategyComment(original_comment) || BStrategyComment(HistoryDealGetString(ticket,DEAL_COMMENT));
            if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)==m_magic && tagged) positions[p].owned=true;
            else positions[p].foreign_entry=true;
            if(positions[p].first_entry==0 || when<positions[p].first_entry)
              { positions[p].first_entry=when; positions[p].entry_order=(ulong)HistoryDealGetInteger(ticket,DEAL_ORDER); }
            positions[p].in_volume+=HistoryDealGetDouble(ticket,DEAL_VOLUME);
           }
         if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
           { positions[p].out_volume+=HistoryDealGetDouble(ticket,DEAL_VOLUME); positions[p].last_exit=when; }
         positions[p].net+=net;
         positions[p].commission+=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
         positions[p].swap+=HistoryDealGetDouble(ticket,DEAL_SWAP);
         positions[p].fee+=HistoryDealGetDouble(ticket,DEAL_FEE);
         positions[p].profit+=HistoryDealGetDouble(ticket,DEAL_PROFIT);
        }
      bool midnight_exposure=false;
      // No historical floating-equity guess: establish baseline only with provably flat midnight.
      double inventory[]; ArrayResize(inventory,ArraySize(positions)); ArrayInitialize(inventory,0);
      for(int i=0;i<deals;i++)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if((datetime)HistoryDealGetInteger(ticket,DEAL_TIME)>=day_start) continue;
         ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
         if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
         ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         for(int p=0;p<ArraySize(positions);p++) if(positions[p].id==id)
            inventory[p]+=(type==DEAL_TYPE_BUY ? 1:-1)*HistoryDealGetDouble(ticket,DEAL_VOLUME);
        }
      for(int p=0;p<ArraySize(inventory);p++) if(MathAbs(inventory[p])>1e-8) midnight_exposure=true;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         if(PositionGetTicket(i)==0) continue;
         ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER); bool found=false;
         for(int p=0;p<ArraySize(positions);p++) if(positions[p].id==id && positions[p].first_entry>0) found=true;
         if(!found) { diagnostic="Current position entry history missing; cannot establish ownership or day equity"; return false; }
         if((datetime)PositionGetInteger(POSITION_TIME)<day_start) midnight_exposure=true;
        }
      m_history_valid=true;
      if(day_id!=today)
        {
         day_id=today; locked=false; day_equity=0;
         if(!ReadDay(today))
           {
            if(FileIsExist(m_prefix+"_day_"+(string)today+".csv",m_flags))
              { diagnostic="Persisted day record invalid; refuse to reset risk lock"; day_id=0; return false; }
            if(override_day==today && BFinitePositive(override_equity)) day_equity=override_equity;
            else if(!midnight_exposure)
               day_equity=AccountInfoDouble(ACCOUNT_BALANCE)+AccountInfoDouble(ACCOUNT_CREDIT)-all_day_cash;
            if(!BFinitePositive(day_equity))
              { diagnostic="No reliable day-start equity; provide dated override or wait for a flat midnight"; day_id=0; return false; }
            if(!WriteDay()) { diagnostic="Cannot persist day-start equity"; day_id=0; return false; }
           }
        }
      day_net=0; floating=0; day_losses=0; session_fills=0;
      for(int p=0;p<ArraySize(positions);p++)
        {
         if(!positions[p].owned) continue;
         if(positions[p].foreign_entry) { diagnostic="Mixed netting position ownership in history; entries locked"; locked=true; }
         bool inside=false; datetime end=0; long sid=0; string reason="";
         if(!clock.Session(positions[p].first_entry,inside,end,sid,reason)) { diagnostic=reason; return false; }
         if(sid==current_session && inside) session_fills++;
         if(positions[p].last_exit>=day_start && positions[p].out_volume>=positions[p].in_volume-1e-8 && positions[p].net<0) day_losses++;
        }
      // Include every available fee/swap/profit record linked to an EA-owned position, including manual exits.
      for(int i=0;i<deals;i++)
        {
         ulong t=HistoryDealGetTicket(i);
         if((datetime)HistoryDealGetInteger(t,DEAL_TIME)<day_start) continue;
         ulong id=(ulong)HistoryDealGetInteger(t,DEAL_POSITION_ID);
         bool owned=((ulong)HistoryDealGetInteger(t,DEAL_MAGIC)==m_magic);
         for(int p=0;p<ArraySize(positions);p++) if(positions[p].id==id && positions[p].owned) owned=true;
         if(owned) day_net+=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_COMMISSION)+
                            HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_FEE);
        }
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         if(PositionGetTicket(i)==0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
        }
      bool hit=day_losses>=m_cfg.max_losses_day || day_net+floating<=-day_equity*m_cfg.daily_loss_percent/100;
      if(hit && !locked) { locked=true; if(!WriteDay()) { diagnostic="Daily lock persistence failed"; return false; } }
      if(locked && diagnostic=="") diagnostic="Daily risk lock until next session-local trading day";
      valid=true;
      return true;
     }
   bool EntriesAllowed(string &why)
     {
      if(!valid || locked) { why=diagnostic; return false; }
      if(session_fills>=m_cfg.max_fills_session) { why="Maximum filled trades per session"; return false; }
      return true;
     }
   void ObserveFloating()
     {
      floating=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_MAGIC)==m_magic)
            floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(valid && !locked && day_net+floating<=-day_equity*m_cfg.daily_loss_percent/100)
        {
         locked=true; diagnostic="Daily equity loss threshold reached";
         if(!WriteDay()) { valid=false; diagnostic="Daily lock persistence failed"; }
        }
     }
   bool SafePosition(const ulong id)
     {
      if(!m_history_valid) return false;
      for(int p=0;p<ArraySize(positions);p++)
         if(positions[p].id==id) return positions[p].owned && !positions[p].foreign_entry;
      return false;
     }
  };
#endif
