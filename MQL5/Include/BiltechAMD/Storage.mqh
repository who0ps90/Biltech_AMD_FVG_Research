#ifndef BILTECH_AMD_STORAGE_MQH
#define BILTECH_AMD_STORAGE_MQH
#include "Types.mqh"

uint BHash(const string text)
  {
   uint hash=2166136261;
   for(int i=0;i<StringLen(text);i++) { hash^=(uint)StringGetCharacter(text,i); hash*=16777619; }
   return hash;
  }

// Exclusive FILE_COMMON handle is retained for the lifetime of one strategy identity.
// This refuses second instances, including another terminal on the same Windows machine.
class BStore
  {
private:
   string m_prefix;
   int m_flags;
   int m_lock;
   bool WriteSnapshot(const string filename,const BSetup &s,const datetime last_bar)
     {
      string tmp=filename+".tmp";
      int h=FileOpen(tmp,FILE_WRITE|FILE_CSV|FILE_ANSI|m_flags,',',CP_UTF8);
      if(h==INVALID_HANDLE) return false;
      bool ok=FileWrite(h,"BAMD_STATE_1",(long)last_bar,(int)s.state,(int)s.direction,s.id,s.session_id,
         (long)s.range_start,(long)s.qualified_at,(long)s.sweep_bar_open,(long)s.swept_at,(long)s.reclaim_at,(long)s.confirmed_at,(long)s.expires_at,
         s.range_high,s.range_low,s.extreme,s.zone_low,s.zone_high,s.atr_confirmation,s.entry,s.sl,s.tp,
         s.volume,s.planned_risk_money,s.spread_submission,s.range_age,s.sweep_age,s.reclaim_age,
         (int)s.attempted,s.order_ticket,s.position_id,BCSVCell(s.reason),BCSVCell(s.symbol),BCSVCell(s.config_id),
         (long)s.observed_qualification,(long)s.observed_sweep,(long)s.observed_reclaim,(long)s.observed_confirmation,"BEND")>0;
      FileFlush(h); FileClose(h);
      if(!ok) return false;
      return FileMove(tmp,m_flags,filename,FILE_REWRITE|m_flags);
     }
   bool ReadSnapshot(const string filename,BSetup &s,datetime &last_bar)
     {
      int h=FileOpen(filename,FILE_READ|FILE_CSV|FILE_ANSI|m_flags,',',CP_UTF8);
      if(h==INVALID_HANDLE) return false;
      string schema=FileReadString(h);
      last_bar=(datetime)FileReadNumber(h);
      s.state=(BState)(int)FileReadNumber(h); s.direction=(BDirection)(int)FileReadNumber(h);
      s.id=(long)FileReadNumber(h); s.session_id=(long)FileReadNumber(h);
      s.range_start=(datetime)FileReadNumber(h); s.qualified_at=(datetime)FileReadNumber(h);
      s.sweep_bar_open=(datetime)FileReadNumber(h); s.swept_at=(datetime)FileReadNumber(h);
      s.reclaim_at=(datetime)FileReadNumber(h); s.confirmed_at=(datetime)FileReadNumber(h);
      s.expires_at=(datetime)FileReadNumber(h);
      s.range_high=FileReadNumber(h); s.range_low=FileReadNumber(h); s.extreme=FileReadNumber(h);
      s.zone_low=FileReadNumber(h); s.zone_high=FileReadNumber(h); s.atr_confirmation=FileReadNumber(h);
      s.entry=FileReadNumber(h); s.sl=FileReadNumber(h); s.tp=FileReadNumber(h);
      s.volume=FileReadNumber(h); s.planned_risk_money=FileReadNumber(h); s.spread_submission=FileReadNumber(h);
      s.range_age=(int)FileReadNumber(h); s.sweep_age=(int)FileReadNumber(h); s.reclaim_age=(int)FileReadNumber(h);
      s.attempted=(FileReadNumber(h)>0);
      // Tickets are read as strings to preserve all 64 bits (FileReadNumber uses double).
      s.order_ticket=(ulong)StringToInteger(FileReadString(h));
      s.position_id=(ulong)StringToInteger(FileReadString(h));
      s.reason=FileReadString(h); s.symbol=FileReadString(h); s.config_id=FileReadString(h);
      s.observed_qualification=(datetime)FileReadNumber(h); s.observed_sweep=(datetime)FileReadNumber(h);
      s.observed_reclaim=(datetime)FileReadNumber(h); s.observed_confirmation=(datetime)FileReadNumber(h);
      string footer=FileReadString(h); FileClose(h);
      return schema=="BAMD_STATE_1" && footer=="BEND" && s.state>=B_IDLE && s.state<=B_INVALIDATED;
     }
public:
   BStore() { m_lock=INVALID_HANDLE; }
   string Prefix() { return m_prefix; }
   bool Init(const ulong magic,const bool tester,string &why)
     {
      m_flags=(tester ? 0:FILE_COMMON);
      m_prefix="BiltechAMD_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
         (string)BHash(AccountInfoString(ACCOUNT_SERVER))+"_"+(string)magic;
      m_lock=FileOpen(m_prefix+".lock",FILE_READ|FILE_WRITE|FILE_BIN|m_flags);
      if(m_lock==INVALID_HANDLE) { why="Strategy identity already active, or exclusive risk store unavailable"; return false; }
      return true;
     }
   void Close() { if(m_lock!=INVALID_HANDLE) FileClose(m_lock); m_lock=INVALID_HANDLE; }
   bool ResetTesterFiles()
     {
      if(m_flags!=0) return false;
      string name=""; long search=FileFindFirst(m_prefix+"_*.csv",name,0);
      if(search==INVALID_HANDLE) return true;
      bool ok=true;
      do { if(!FileDelete(name,0)) ok=false; } while(FileFindNext(search,name));
      FileFindClose(search); return ok;
     }
   bool Load(BSetup &s,datetime &last_bar,bool &exists)
     {
      exists=FileIsExist(m_prefix+"_active.csv",m_flags);
      if(!exists) return false;
      return ReadSnapshot(m_prefix+"_active.csv",s,last_bar);
     }
   bool Save(const BSetup &s,const datetime last_bar)
     {
      return WriteSnapshot(m_prefix+"_active.csv",s,last_bar);
     }
   bool SavePlan(const BSetup &s,const datetime last_bar)
     {
      if(s.order_ticket==0) return false;
      return WriteSnapshot(m_prefix+"_plan_"+(string)s.order_ticket+".csv",s,last_bar);
     }
   bool LoadPlan(const ulong ticket,BSetup &s)
     {
      datetime unused=0;
      return ReadSnapshot(m_prefix+"_plan_"+(string)ticket+".csv",s,unused);
     }
  };
#endif
