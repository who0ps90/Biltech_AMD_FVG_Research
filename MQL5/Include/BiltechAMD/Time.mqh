#ifndef BILTECH_AMD_TIME_MQH
#define BILTECH_AMD_TIME_MQH
#include "Types.mqh"

// Supported rule years are 2007..2099. These are explicit conventions,
// not a claim that any broker follows US or European clock changes.
struct BTimeConfig
  {
   BSessionZone zone;
   BBrokerDST broker_dst;
   int broker_standard_utc_minutes;
   int session_start_minutes;
   int session_end_minutes;
   bool weekdays_only;
  };

datetime BDate(const int year,const int month,const int day,const int hour=0,const int minute=0,const int second=0)
  {
   MqlDateTime p;
   ZeroMemory(p);
   p.year=year; p.mon=month; p.day=day;
   p.hour=hour; p.min=minute; p.sec=second;
   return StructToTime(p);
  }

bool BSupportedTime(const datetime value)
  {
   return value>=D'2007.01.01 00:00:00' && value<D'2100.01.01 00:00:00';
  }

// Strict parsing avoids StringToTime's permissive/current-date behaviour.
// Accepted: YYYY.MM.DD HH:MM[:SS], YYYY-MM-DDTHH:MM[:SS], and an optional Z.
// There is no timezone inference: the caller must supply an explicitly UTC value.
bool BParseUTC(string text,datetime &value)
  {
   StringTrimLeft(text); StringTrimRight(text);
   int n=StringLen(text);
   if(n>0 && StringSubstr(text,n-1,1)=="Z")
     {
      text=StringSubstr(text,0,n-1);
      n--;
     }
   if(n!=16 && n!=19) return false;
   string sep=StringSubstr(text,4,1);
   if((sep!="." && sep!="-") || StringSubstr(text,7,1)!=sep) return false;
   string middle=StringSubstr(text,10,1);
   if((middle!=" " && middle!="T") || StringSubstr(text,13,1)!=":") return false;
   if(n==19 && StringSubstr(text,16,1)!=":") return false;
   for(int i=0;i<n;i++)
     {
      if(i==4 || i==7 || i==10 || i==13 || i==16) continue;
      ushort ch=StringGetCharacter(text,i);
      if(ch<'0' || ch>'9') return false;
     }
   int y=(int)StringToInteger(StringSubstr(text,0,4));
   int mo=(int)StringToInteger(StringSubstr(text,5,2));
   int d=(int)StringToInteger(StringSubstr(text,8,2));
   int h=(int)StringToInteger(StringSubstr(text,11,2));
   int mi=(int)StringToInteger(StringSubstr(text,14,2));
   int s=(n==19 ? (int)StringToInteger(StringSubstr(text,17,2)) : 0);
   if(y<2007 || y>2099 || mo<1 || mo>12 || d<1 || d>31 || h>23 || mi>59 || s>59) return false;
   datetime candidate=BDate(y,mo,d,h,mi,s);
   MqlDateTime p;
   if(!TimeToStruct(candidate,p)) return false;
   if(p.year!=y || p.mon!=mo || p.day!=d || p.hour!=h || p.min!=mi || p.sec!=s) return false;
   value=candidate;
   return true;
  }

int BSunday(const int year,const int month,const int ordinal)
  {
   MqlDateTime p;
   TimeToStruct(BDate(year,month,1),p);
   return 1+(7-p.day_of_week)%7+7*(ordinal-1);
  }

int BLastSunday(const int year,const int month)
  {
   datetime following=(month==12 ? BDate(year+1,1,1) : BDate(year,month+1,1));
   MqlDateTime p;
   TimeToStruct(following-86400,p);
   return p.day-p.day_of_week;
  }

bool BOffsetAtUTC(const datetime utc,const int standard_minutes,const BBrokerDST schedule,int &minutes,string &reason)
  {
   if(!BSupportedTime(utc)) { reason="Time outside supported UTC years 2007..2099"; return false; }
   MqlDateTime p;
   if(!TimeToStruct(utc,p)) { reason="Cannot decompose UTC timestamp"; return false; }
   minutes=standard_minutes;
   if(schedule==B_FIXED) return true;
   datetime begin=0,finish=0;
   if(schedule==B_US_DST)
     {
      // 02:00 standard local, second Sunday March; 02:00 daylight local,
      // first Sunday November. For New York standard_minutes=-300.
      begin=BDate(p.year,3,BSunday(p.year,3,2),2)-standard_minutes*60;
      finish=BDate(p.year,11,BSunday(p.year,11,1),2)-(standard_minutes+60)*60;
     }
   else if(schedule==B_EU_DST)
     {
      // European convention: transitions at 01:00 UTC, last Sundays.
      begin=BDate(p.year,3,BLastSunday(p.year,3),1);
      finish=BDate(p.year,10,BLastSunday(p.year,10),1);
     }
   else { reason="Unsupported DST schedule"; return false; }
   if(utc>=begin && utc<finish) minutes+=60;
   return true;
  }

bool BWallToUTC(const datetime wall,const int standard_minutes,const BBrokerDST schedule,datetime &utc,string &reason)
  {
   if(!BSupportedTime(wall)) { reason="Local timestamp outside supported years 2007..2099"; return false; }
   int hits=0;
   datetime result=0;
   for(int i=0;i<(schedule==B_FIXED ? 1 : 2);i++)
     {
      datetime candidate=wall-(standard_minutes+i*60)*60;
      int actual_offset=0;
      string candidate_reason;
      if(!BOffsetAtUTC(candidate,standard_minutes,schedule,actual_offset,candidate_reason)) continue;
      if(candidate+actual_offset*60==wall)
        {
         result=candidate;
         hits++;
        }
     }
   if(hits!=1)
     {
      reason=(hits>1 ? "Ambiguous clock during autumn DST overlap" : "Nonexistent clock or unsupported conversion boundary");
      return false;
     }
   utc=result;
   return true;
  }

class BTimeRules
  {
private:
   BTimeConfig m_cfg;
   bool m_valid;

   void SessionConvention(int &offset,BBrokerDST &schedule)
     {
      offset=m_cfg.broker_standard_utc_minutes;
      schedule=m_cfg.broker_dst;
      if(m_cfg.zone==B_NEW_YORK) { offset=-300; schedule=B_US_DST; }
      if(m_cfg.zone==B_LONDON) { offset=0; schedule=B_EU_DST; }
     }

   bool SessionWallToServer(const datetime wall,datetime &server,string &reason)
     {
      int offset;
      BBrokerDST schedule;
      SessionConvention(offset,schedule);
      datetime utc=0;
      if(!BWallToUTC(wall,offset,schedule,utc,reason)) return false;
      return UTCToServer(utc,server,reason);
     }

public:
   BTimeRules(void) { m_valid=false; }

   bool Init(const BTimeConfig &cfg,string &reason)
     {
      m_valid=false;
      if(cfg.zone<B_NEW_YORK || cfg.zone>B_BROKER_SERVER) { reason="Invalid session timezone"; return false; }
      if(cfg.broker_dst<B_FIXED || cfg.broker_dst>B_EU_DST) { reason="Invalid broker DST convention"; return false; }
      if(cfg.broker_standard_utc_minutes<-720 || cfg.broker_standard_utc_minutes>840)
        { reason="Explicit broker standard UTC offset is required (-720..840 minutes); 9999 is unset"; return false; }
      if(cfg.session_start_minutes<0 || cfg.session_start_minutes>=1440 || cfg.session_end_minutes<0 || cfg.session_end_minutes>=1440 || cfg.session_start_minutes==cfg.session_end_minutes)
        { reason="Session clock minutes must be 0..1439 with different start and end"; return false; }
      m_cfg=cfg;
      m_valid=true;
      reason="Time rules valid: explicit historical broker offset and DST convention";
      return true;
     }

   bool ServerToUTC(const datetime server,datetime &utc,string &reason)
     {
      if(!m_valid) { reason="Time rules not initialised"; return false; }
      return BWallToUTC(server,m_cfg.broker_standard_utc_minutes,m_cfg.broker_dst,utc,reason);
     }

   bool UTCToServer(const datetime utc,datetime &server,string &reason)
     {
      if(!m_valid) { reason="Time rules not initialised"; return false; }
      int offset=0;
      if(!BOffsetAtUTC(utc,m_cfg.broker_standard_utc_minutes,m_cfg.broker_dst,offset,reason)) return false;
      datetime result=utc+offset*60,roundtrip=0;
      if(!BWallToUTC(result,m_cfg.broker_standard_utc_minutes,m_cfg.broker_dst,roundtrip,reason)) return false;
      if(roundtrip!=utc) { reason="Broker clock failed UTC roundtrip"; return false; }
      server=result;
      return true;
     }

   bool LocalTime(const datetime server,datetime &local,string &reason)
     {
      datetime utc=0;
      if(!ServerToUTC(server,utc,reason)) return false;
      int standard_offset=0,offset=0;
      BBrokerDST schedule;
      SessionConvention(standard_offset,schedule);
      if(!BOffsetAtUTC(utc,standard_offset,schedule,offset,reason)) return false;
      local=utc+offset*60;
      if(!BSupportedTime(local)) { reason="Session local date outside supported years 2007..2099"; return false; }
      return true;
     }

   bool Session(const datetime server,bool &inside,datetime &end_server,long &session_id,string &reason)
     {
      inside=false; end_server=0; session_id=0;
      datetime local=0;
      if(!LocalTime(server,local,reason)) return false;
      MqlDateTime p;
      if(!TimeToStruct(local,p)) { reason="Cannot decompose session time"; return false; }
      datetime midnight=BDate(p.year,p.mon,p.day);
      datetime start=midnight+m_cfg.session_start_minutes*60;
      // Outside the session, identify the most recently begun session.
      // During a midnight crossing this preserves the preceding start date.
      if(local<start) start-=86400;
      datetime finish=start+(m_cfg.session_end_minutes-m_cfg.session_start_minutes)*60;
      if(m_cfg.session_end_minutes<m_cfg.session_start_minutes) finish+=86400;
      MqlDateTime start_parts;
      if(!TimeToStruct(start,start_parts)) { reason="Cannot decompose session start"; return false; }
      datetime start_server=0;
      if(!SessionWallToServer(start,start_server,reason)) return false;
      if(!SessionWallToServer(finish,end_server,reason)) return false;
      session_id=(long)start_parts.year*10000+start_parts.mon*100+start_parts.day;
      bool weekday=(start_parts.day_of_week>=1 && start_parts.day_of_week<=5);
      inside=local>=start && local<finish && (!m_cfg.weekdays_only || weekday);
      reason=(inside ? "Inside entry session" : "Outside entry session");
      return true;
     }

   bool DayBounds(const datetime server,datetime &start_server,long &day_id,string &reason)
     {
      start_server=0; day_id=0;
      datetime local=0;
      if(!LocalTime(server,local,reason)) return false;
      MqlDateTime p;
      if(!TimeToStruct(local,p)) { reason="Cannot decompose trading day"; return false; }
      if(!SessionWallToServer(BDate(p.year,p.mon,p.day),start_server,reason)) return false;
      day_id=(long)p.year*10000+p.mon*100+p.day;
      reason="Trading day begins at session-timezone midnight";
      return true;
     }
  };
#endif
