#ifndef BILTECH_AMD_JOURNAL_MQH
#define BILTECH_AMD_JOURNAL_MQH
#include "Types.mqh"

class BJournal
  {
private:
   int m_file;
   int m_equity;
   string m_symbol;
   string m_timeframe;
   string m_config;
   ulong m_deals[];
   ulong m_closed[];
   bool Has(const ulong &values[],const ulong id)
     { for(int i=0;i<ArraySize(values);i++) if(values[i]==id) return true; return false; }
public:
   BJournal() { m_file=INVALID_HANDLE; m_equity=INVALID_HANDLE; }
   bool Init(const string prefix,const string symbol,const ENUM_TIMEFRAMES tf,const string config,const bool tester)
     {
      m_symbol=symbol; m_timeframe=EnumToString(tf); m_config=config;
      int flags=(tester ? 0:FILE_COMMON);
      m_file=FileOpen(prefix+"_journal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|flags,',',CP_UTF8);
      if(m_file==INVALID_HANDLE) return false;
      if(FileSize(m_file)==0)
         FileWrite(m_file,"rule_version","config_id","symbol","timeframe","setup_id","session_id","event_time",
            "observed_time","event","from_state","to_state","reason","range_low","range_high","extreme",
            "zone_low","zone_high","entry","sl","tp","volume","planned_risk_money","order_ticket","position_id",
            "deal_ticket","actual_price","actual_volume","spread","commission","swap","fee","profit","slippage","net_pnl","net_R","record_end");
      else
        {
         // Recover idempotency receipts from the journal itself; no transaction count assumptions.
         while(!FileIsEnding(m_file))
           {
            string row[36];
            row[0]=FileReadString(m_file);
            if(row[0]=="" && FileIsEnding(m_file)) break;
            for(int j=1;j<36;j++) row[j]=FileReadString(m_file);
            if(row[0]=="rule_version")
              { if(row[35]!="record_end") { Close(); return false; } continue; }
            if(row[35]!="BEND") { Close(); return false; }
            if(row[8]=="DEAL") { int n=ArraySize(m_deals); ArrayResize(m_deals,n+1); m_deals[n]=(ulong)StringToInteger(row[24]); }
            if(row[8]=="TRADE_CLOSED") { int n=ArraySize(m_closed); ArrayResize(m_closed,n+1); m_closed[n]=(ulong)StringToInteger(row[23]); }
           }
        }
      FileSeek(m_file,0,SEEK_END);
      m_equity=FileOpen(prefix+"_equity.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|flags,',',CP_UTF8);
      if(m_equity==INVALID_HANDLE) return false;
      if(FileSize(m_equity)==0) FileWrite(m_equity,"time","equity");
      FileSeek(m_equity,0,SEEK_END);
      return true;
     }
   bool SeenDeal(const ulong id) { return Has(m_deals,id); }
   bool SeenClosed(const ulong id) { return Has(m_closed,id); }
   bool Event(const BSetup &s,const datetime at,const datetime observed,const string event,const BState from,
              const string why,const string symbol="",const ulong deal=0,const double actual_price=0,
              const double actual_volume=0,const double spread=0,const double commission=0,const double swap=0,
              const double fee=0,const double profit=0,const double slippage=0,const double net=0,
              const bool closed=false)
     {
      if(m_file==INVALID_HANDLE) return false;
      string net_r=(closed && s.planned_risk_money>0 ? DoubleToString(net/s.planned_risk_money,10):"");
      double recorded_spread=(event=="PLAN" ? s.spread_submission:spread);
      bool ok=FileWrite(m_file,B_RULE_VERSION,BCSVCell(s.config_id=="" ? m_config:s.config_id),BCSVCell(symbol=="" ? m_symbol:symbol),m_timeframe,s.id,s.session_id,
         TimeToString(at,TIME_DATE|TIME_SECONDS),TimeToString(observed,TIME_DATE|TIME_SECONDS),event,
         BStateName(from),BStateName(s.state),BCSVCell(why),s.range_low,s.range_high,s.extreme,s.zone_low,s.zone_high,
         s.entry,s.sl,s.tp,s.volume,s.planned_risk_money,s.order_ticket,s.position_id,deal,actual_price,actual_volume,
         recorded_spread,commission,swap,fee,profit,slippage,net,net_r,"BEND")>0;
      FileFlush(m_file);
      if(ok && event=="DEAL") { int n=ArraySize(m_deals); ArrayResize(m_deals,n+1); m_deals[n]=deal; }
      if(ok && closed) { int n=ArraySize(m_closed); ArrayResize(m_closed,n+1); m_closed[n]=s.position_id; }
      PrintFormat("BAMD %s %s setup=%I64d %s -> %s at=%s observed=%s reason=%s range=[%.10f,%.10f] extreme=%.10f FVG=[%.10f,%.10f] entry=%.10f SL=%.10f TP=%.10f",
         m_symbol,m_timeframe,s.id,BStateName(from),BStateName(s.state),TimeToString(at,TIME_DATE|TIME_SECONDS),
         TimeToString(observed,TIME_DATE|TIME_SECONDS),why,s.range_low,s.range_high,s.extreme,s.zone_low,s.zone_high,s.entry,s.sl,s.tp);
      return ok;
     }
   void Equity(const datetime now) { if(m_equity!=INVALID_HANDLE) { FileWrite(m_equity,TimeToString(now,TIME_DATE|TIME_SECONDS),AccountInfoDouble(ACCOUNT_EQUITY)); FileFlush(m_equity); } }
   void Close() { if(m_file!=INVALID_HANDLE) FileClose(m_file); if(m_equity!=INVALID_HANDLE) FileClose(m_equity); m_file=INVALID_HANDLE; m_equity=INVALID_HANDLE; }
  };
#endif
