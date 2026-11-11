#ifndef BILTECH_AMD_TIME_NEWS_TESTS_MQH
#define BILTECH_AMD_TIME_NEWS_TESTS_MQH
#include "Time.mqh"
#include "News.mqh"

void BTimeNewsExpect(const bool result,const string label,int &passed,int &failed)
  {
   if(result) { passed++; Print("PASS time/news: ",label); }
   else { failed++; Print("FAIL time/news: ",label); }
  }

bool BWriteNewsFixture(const string filename,const string body)
  {
   int file=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(file==INVALID_HANDLE) return false;
   uint written=FileWriteString(file,body);
   FileClose(file);
   return written>0;
  }

// Native deterministic tests: no symbol, connection, account or trade API.
// Return the number of failed assertions. File fixtures are created only inside
// the terminal/test-agent Files sandbox and deleted by this test routine.
int BRunTimeNewsTests(void)
  {
   int passed=0,failed=0;
   string reason;
   datetime t=0,utc=0,local=0,server=0,finish=0,start_day=0;
   long session_id=0,day_id=0;
   bool inside=false;
   BTimeConfig cfg;
   cfg.zone=B_NEW_YORK; cfg.broker_dst=B_FIXED; cfg.broker_standard_utc_minutes=120;
   cfg.session_start_minutes=9*60+45; cfg.session_end_minutes=11*60; cfg.weekdays_only=true;
   BTimeRules clock;
   BTimeNewsExpect(clock.Init(cfg,reason),"valid explicit fixed broker convention",passed,failed);
   BTimeNewsExpect(BParseUTC("2026-10-25T12:34:56Z",t) && t==D'2026.10.25 12:34:56',"strict ISO UTC timestamp",passed,failed);
   BTimeNewsExpect(BParseUTC("2024.02.29 00:00",t),"valid leap day",passed,failed);
   BTimeNewsExpect(!BParseUTC("2026.02.29 00:00",t),"reject normalised invalid calendar date",passed,failed);
   BTimeNewsExpect(!BParseUTC("2026.01.01 24:00",t),"reject invalid hour",passed,failed);
   BTimeNewsExpect(!BParseUTC("2026.01.01 10:00+02:00",t),"reject unrecognised offset suffix",passed,failed);
   BTimeNewsExpect(!BParseUTC("2006.12.31 23:59",t),"reject unsupported historical year",passed,failed);

   BTimeNewsExpect(clock.ServerToUTC(D'2026.01.05 16:45',utc,reason) && utc==D'2026.01.05 14:45',"fixed broker server to historical UTC",passed,failed);
   BTimeNewsExpect(clock.UTCToServer(D'2026.07.06 13:45',server,reason) && server==D'2026.07.06 15:45',"fixed broker independent of New York DST",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2007.03.11 08:59:59',local,reason) && local==D'2007.03.11 01:59:59',"New York before 2007 spring transition",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2007.03.11 09:00',local,reason) && local==D'2007.03.11 03:00',"New York 2007 spring transition",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2026.11.01 07:59:59',local,reason) && local==D'2026.11.01 01:59:59',"New York before autumn transition",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2026.11.01 08:00',local,reason) && local==D'2026.11.01 01:00',"New York autumn repeated hour",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.01.05 16:45',inside,finish,session_id,reason) && inside && finish==D'2026.01.05 18:00' && session_id==20260105,"New York session starts inclusively",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.01.05 18:00',inside,finish,session_id,reason) && !inside,"New York session ends exclusively",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.07.06 15:45',inside,finish,session_id,reason) && inside && finish==D'2026.07.06 17:00',"summer session UTC conversion",passed,failed);
   BTimeNewsExpect(clock.DayBounds(D'2026.03.10 05:59',start_day,day_id,reason) && day_id==20260309 && start_day==D'2026.03.09 06:00',"trading day follows New York midnight",passed,failed);
   BTimeNewsExpect(clock.DayBounds(D'2026.03.10 06:00',start_day,day_id,reason) && day_id==20260310 && start_day==D'2026.03.10 06:00',"day changes at converted midnight",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.01.10 16:45',inside,finish,session_id,reason) && !inside,"weekend entry excluded",passed,failed);

   cfg.zone=B_LONDON;
   BTimeNewsExpect(clock.Init(cfg,reason),"London convention init",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2026.03.29 02:59:59',local,reason) && local==D'2026.03.29 00:59:59',"London before spring transition",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2026.03.29 03:00',local,reason) && local==D'2026.03.29 02:00',"London spring transition",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2026.10.25 02:59:59',local,reason) && local==D'2026.10.25 01:59:59',"London before autumn transition",passed,failed);
   BTimeNewsExpect(clock.LocalTime(D'2026.10.25 03:00',local,reason) && local==D'2026.10.25 01:00',"London autumn transition",passed,failed);

   cfg.zone=B_BROKER_SERVER; cfg.broker_standard_utc_minutes=0;
   cfg.session_start_minutes=22*60; cfg.session_end_minutes=2*60;
   BTimeNewsExpect(clock.Init(cfg,reason),"midnight-crossing session init",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.10.24 01:00',inside,finish,session_id,reason) && inside && session_id==20261023 && finish==D'2026.10.24 02:00',"Friday crossing into Saturday keeps Friday session",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.10.24 02:00',inside,finish,session_id,reason) && !inside,"cross-midnight session exact end",passed,failed);
   BTimeNewsExpect(clock.Session(D'2026.10.24 23:00',inside,finish,session_id,reason) && !inside,"Saturday session start rejected",passed,failed);
   BTimeNewsExpect(clock.DayBounds(D'2026.10.24 01:00',start_day,day_id,reason) && day_id==20261024 && start_day==D'2026.10.24 00:00',"crossing session and trading day have distinct identifiers",passed,failed);

   cfg.broker_standard_utc_minutes=120; cfg.broker_dst=B_US_DST;
   BTimeNewsExpect(clock.Init(cfg,reason),"explicit US broker clock init",passed,failed);
   BTimeNewsExpect(!clock.ServerToUTC(D'2026.03.08 02:30',utc,reason),"reject nonexistent broker spring clock",passed,failed);
   BTimeNewsExpect(!clock.ServerToUTC(D'2026.11.01 01:30',utc,reason),"reject ambiguous broker autumn clock",passed,failed);
   BTimeNewsExpect(clock.ServerToUTC(D'2026.03.08 03:00',utc,reason) && utc==D'2026.03.08 00:00',"US broker first valid daylight clock",passed,failed);
   BTimeNewsExpect(!clock.UTCToServer(D'2026.10.31 22:30',server,reason),"UTC-to-broker rejects nonroundtrippable overlap",passed,failed);
   cfg.broker_dst=B_EU_DST;
   BTimeNewsExpect(clock.Init(cfg,reason),"explicit EU broker clock init",passed,failed);
   BTimeNewsExpect(!clock.ServerToUTC(D'2026.03.29 03:30',utc,reason),"EU broker spring gap at configured offset",passed,failed);
   BTimeNewsExpect(!clock.ServerToUTC(D'2026.10.25 03:30',utc,reason),"EU broker autumn overlap at configured offset",passed,failed);
   BTimeNewsExpect(clock.ServerToUTC(D'2026.03.29 04:00',utc,reason) && utc==D'2026.03.29 01:00',"EU broker daylight conversion",passed,failed);
   cfg.broker_standard_utc_minutes=9999;
   BTimeNewsExpect(!clock.Init(cfg,reason),"unset explicit broker offset fails closed",passed,failed);
   cfg.broker_standard_utc_minutes=0; cfg.session_end_minutes=cfg.session_start_minutes;
   BTimeNewsExpect(!clock.Init(cfg,reason),"zero-length session configuration rejected",passed,failed);
   cfg.zone=B_NEW_YORK; cfg.broker_dst=B_FIXED; cfg.weekdays_only=false;
   cfg.session_start_minutes=150; cfg.session_end_minutes=240;
   BTimeNewsExpect(clock.Init(cfg,reason) && !clock.Session(D'2026.03.08 07:45',inside,finish,session_id,reason),"nonexistent session start fails closed",passed,failed);
   cfg.session_start_minutes=90; cfg.session_end_minutes=180;
   BTimeNewsExpect(clock.Init(cfg,reason) && !clock.Session(D'2026.11.01 07:00',inside,finish,session_id,reason),"ambiguous session start fails closed",passed,failed);

   string fields[];
   BTimeNewsExpect(BNewsCSVLine("2026.01.01 12:00,USD,HIGH,\"Payroll, \"\"preliminary\"\"\"",fields,reason) && fields[3]=="Payroll, \"preliminary\"","quoted CSV commas and escaped quotes",passed,failed);
   BTimeNewsExpect(!BNewsCSVLine("2026.01.01 12:00,USD,HIGH,\"broken",fields,reason),"unclosed CSV quote rejected",passed,failed);
   BTimeNewsExpect(!BNewsCSVLine("2026.01.01 12:00,USD,HIGH,event,extra",fields,reason),"extra CSV column rejected",passed,failed);
   string fixture="BiltechAMD_TimeNewsTests_"+(string)GetTickCount64()+".csv";
   string valid_csv="utc,currency,impact,event\r\n2026.01.01 12:20,USD,HIGH,Second\r\n2026.01.01 12:00,USD,HIGH,\"First, release\"\r\n2026.01.01 13:00,EUR,HIGH,Unselected\r\n2026.01.01 14:00,USD,LOW,Low impact\r\n";
   bool wrote=BWriteNewsFixture(fixture,valid_csv);
   BTimeNewsExpect(wrote,"create native CSV fixture in file sandbox",passed,failed);
   BNewsConfig news_cfg;
   news_cfg.enabled=true; news_cfg.filename=fixture; news_cfg.currencies="USD";
   news_cfg.before_minutes=15; news_cfg.after_minutes=15;
   news_cfg.coverage_start_utc=D'2026.01.01'; news_cfg.coverage_end_utc=D'2026.01.03';
   BNewsFilter news;
   BTimeNewsExpect(news.Init(news_cfg,reason) && news.Valid(),"load and validate complete unsorted calendar",passed,failed);
   BTimeNewsExpect(!news.Blocked(D'2026.01.01 11:44:59',reason),"outside before exclusion",passed,failed);
   BTimeNewsExpect(news.Blocked(D'2026.01.01 11:45',reason),"exact exclusion entry boundary",passed,failed);
   BTimeNewsExpect(news.Blocked(D'2026.01.01 12:35',reason),"merged windows include exact after boundary",passed,failed);
   BTimeNewsExpect(!news.Blocked(D'2026.01.01 12:35:01',reason),"merged exclusion ends after boundary second",passed,failed);
   BTimeNewsExpect(!news.Blocked(D'2026.01.01 13:00',reason),"unselected currency excluded from filtering",passed,failed);
   BTimeNewsExpect(!news.Blocked(D'2026.01.01 14:00',reason),"LOW impact excluded from filtering",passed,failed);
   BTimeNewsExpect(news.NextBoundary(D'2026.01.01 10:00')==D'2026.01.01 11:45',"next boundary supports pending-order expiration",passed,failed);
   BTimeNewsExpect(news.NextBoundary(D'2026.01.01 12:00')==D'2026.01.01 12:00',"already blocked boundary is immediate",passed,failed);
   BTimeNewsExpect(news.NextBoundary(D'2026.01.01 15:00')==D'2026.01.03',"declared coverage end is a cancellation boundary",passed,failed);
   BTimeNewsExpect(news.Blocked(D'2026.01.03',reason),"outside declared calendar coverage fails closed",passed,failed);
   news_cfg.currencies="";
   BTimeNewsExpect(!news.Init(news_cfg,reason) && news.Blocked(D'2026.01.01',reason),"explicit selected currencies required",passed,failed);
   news_cfg.currencies="USD";
   news_cfg.coverage_end_utc=0;
   BTimeNewsExpect(!news.Init(news_cfg,reason),"explicit coverage declaration required",passed,failed);
   news_cfg.coverage_end_utc=D'2026.01.03';
   BWriteNewsFixture(fixture,"utc,currency,impact,event\r\n2026.01.01 12:00,USD,HIGH,Valid\r\n2026.01.01 13:00,EUR,UNKNOWN,Bad irrelevant row\r\n");
   BTimeNewsExpect(!news.Init(news_cfg,reason) && !news.Valid(),"invalid irrelevant row invalidates whole calendar",passed,failed);
   BWriteNewsFixture(fixture,"utc,currency,impact,event\r\n2026.01.04 12:00,USD,HIGH,Outside coverage\r\n");
   BTimeNewsExpect(!news.Init(news_cfg,reason),"event outside declared coverage rejected",passed,failed);
   BWriteNewsFixture(fixture,"utc,currency,impact,event\r\n");
   BTimeNewsExpect(news.Init(news_cfg,reason) && !news.Blocked(D'2026.01.02',reason),"explicit coverage permits a zero-event calendar",passed,failed);
   FileDelete(fixture);
   BTimeNewsExpect(!news.Init(news_cfg,reason),"missing required calendar fails closed",passed,failed);
   news_cfg.enabled=false;
   BTimeNewsExpect(news.Init(news_cfg,reason) && !news.Blocked(D'2026.01.02',reason) && news.NextBoundary(D'2026.01.02')==0,"disabled news filter needs no file",passed,failed);
   PrintFormat("TIME_NEWS_TESTS passed=%d failed=%d",passed,failed);
   return failed;
  }
#endif
