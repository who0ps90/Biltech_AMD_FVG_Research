#ifndef BILTECH_AMD_JOURNAL_TESTS_MQH
#define BILTECH_AMD_JOURNAL_TESTS_MQH
#include "Journal.mqh"

// Local file fixtures only. Event does not suppress duplicates: callers must
// consult SeenDeal/SeenClosed before writing repeated transaction receipts.
void BJournalAssert(const bool condition,const string label,int &failed,int &checks)
  {
   checks++;
   if(!condition) failed++;
   PrintFormat("%s journal.%s",condition ? "PASS" : "FAIL",label);
  }

bool BJournalReadRows(const string filename,string &cells[],int &rows)
  {
   rows=0;
   ArrayResize(cells,0);
   int h=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h==INVALID_HANDLE) return false;
   bool ok=true;
   while(!FileIsEnding(h))
     {
      string line=FileReadString(h);
      if(line=="" && FileIsEnding(h)) break;
      string columns[];
      int count=StringSplit(line,',',columns);
      if(count!=36) { ok=false; break; }
      int start=rows*36;
      ArrayResize(cells,start+36);
      for(int i=0;i<36;i++) cells[start+i]=columns[i];
      rows++;
     }
   FileClose(h);
   return ok;
  }

int BRunJournalTests()
  {
   int failed=0,checks=0;
   string prefix="BiltechAMD_JournalFixture_"+(string)GetTickCount64()+"_"+(string)GetMicrosecondCount();
   bool fresh=!FileIsExist(prefix+"_journal.csv") && !FileIsExist(prefix+"_equity.csv");
   BJournalAssert(fresh,"fresh_local_test_namespace",failed,checks);
   if(!fresh) return failed;

   const ulong deal=9007199254740997;
   const ulong position=9007199254740995;
   const ulong order=9007199254740993;
   datetime event_at=D'2024.01.08 09:30:00';
   datetime observed_at=event_at+2;
   BSetup s;
   BClearSetup(s);
   s.id=1704704400;
   s.session_id=20240108;
   s.state=B_POSITION_OPEN;
   s.direction=B_LONG;
   s.config_id="fixture, config\nsecond line";
   s.symbol="UNIT,TEST\nSYMBOL";
   s.range_low=90; s.range_high=120; s.extreme=98;
   s.zone_low=100; s.zone_high=101;
   s.entry=100.5; s.sl=98; s.tp=105.5;
   s.volume=0.1; s.planned_risk_money=25;
   s.order_ticket=order; s.position_id=position;
   string reason="receipt, with \"quotes\"\r\nsecond line";
   string sanitized=BCSVCell(reason);
   BJournalAssert(StringFind(sanitized,",")==-1 && StringFind(sanitized,"\r")==-1 &&
                  StringFind(sanitized,"\n")==-1 && StringFind(sanitized,"\"")==-1,
                  "csv_text_stays_one_cell_and_line",failed,checks);

   BJournal journal;
   bool initialized=journal.Init(prefix,s.symbol,PERIOD_M5,"fallback-config",true);
   BJournalAssert(initialized,"initialize_fresh_journal",failed,checks);
   if(!initialized)
     {
      journal.Close();
      if(FileIsExist(prefix+"_journal.csv")) FileDelete(prefix+"_journal.csv");
      if(FileIsExist(prefix+"_equity.csv")) FileDelete(prefix+"_equity.csv");
      return failed;
     }
   BJournalAssert(!journal.SeenDeal(deal) && !journal.SeenClosed(position),"fresh_receipts_absent",failed,checks);
   bool written=journal.Event(s,event_at,observed_at,"DEAL",B_ORDER_PENDING,reason,s.symbol,
                             deal,100.5,0.1,0.05,-1,-0.1,-0.2,0,0.01,-1.3);
   BJournalAssert(written,"write_authoritative_deal_receipt",failed,checks);
   BJournalAssert(journal.SeenDeal(deal) && !journal.SeenDeal(deal+2),"large_deal_receipt_exact_in_memory",failed,checks);
   bool skipped_duplicate=false;
   if(!journal.SeenDeal(deal)) journal.Event(s,event_at,observed_at,"DEAL",B_ORDER_PENDING,reason,s.symbol,deal);
   else skipped_duplicate=true;
   BJournalAssert(skipped_duplicate,"caller_seen_guard_skips_duplicate",failed,checks);
   s.state=B_COMPLETED;
   written=journal.Event(s,event_at+300,observed_at+301,"TRADE_CLOSED",B_POSITION_OPEN,"closed receipt",s.symbol,
                         0,105.5,0.1,0,0,0,0,50,0,50,true);
   BJournalAssert(written && journal.SeenClosed(position) && !journal.SeenClosed(position+2),
                  "large_closed_position_receipt_exact_in_memory",failed,checks);
   journal.Close();

   string cells[];
   int rows=0;
   bool parsed=BJournalReadRows(prefix+"_journal.csv",cells,rows);
   BJournalAssert(parsed && rows==3,"header_plus_two_rows_each_have_36_cells",failed,checks);
   if(parsed && rows==3)
     {
      BJournalAssert(cells[0]=="rule_version" && cells[35]=="record_end" &&
                     cells[36+35]=="BEND" && cells[72+35]=="BEND","schema_and_data_footers",failed,checks);
      BJournalAssert(StringToTime(cells[36+6])==event_at && StringToTime(cells[36+7])==observed_at,
                     "event_and_observed_timestamps_are_distinct_and_exact",failed,checks);
      BJournalAssert((ulong)StringToInteger(cells[36+22])==order &&
                     (ulong)StringToInteger(cells[36+23])==position &&
                     (ulong)StringToInteger(cells[36+24])==deal,"all_large_ticket_columns_exact",failed,checks);
      BJournalAssert(cells[36+1]==BCSVCell(s.config_id) && cells[36+2]==BCSVCell(s.symbol) &&
                     cells[36+11]==sanitized,"sanitized_csv_text_preserves_column_alignment",failed,checks);
      BJournalAssert(cells[36+8]=="DEAL" && cells[72+8]=="TRADE_CLOSED" &&
                     cells[36+34]=="" && MathAbs(StringToDouble(cells[72+34])-2.0)<1e-9,
                     "net_r_written_only_for_closed_trade",failed,checks);
     }

   BJournal restored;
   bool restarted=restored.Init(prefix,s.symbol,PERIOD_M5,"fallback-config",true);
   BJournalAssert(restarted,"reopen_journal_after_restart",failed,checks);
   if(restarted)
     {
      BJournalAssert(restored.SeenDeal(deal) && !restored.SeenDeal(deal+2),"deal_receipt_persists_after_restart",failed,checks);
      BJournalAssert(restored.SeenClosed(position) && !restored.SeenClosed(position+2),"closed_receipt_persists_after_restart",failed,checks);
      bool guarded=restored.SeenDeal(deal) && restored.SeenClosed(position);
      if(!restored.SeenDeal(deal)) restored.Event(s,event_at,observed_at,"DEAL",B_ORDER_PENDING,reason,s.symbol,deal);
      if(!restored.SeenClosed(position)) restored.Event(s,event_at,observed_at,"TRADE_CLOSED",B_POSITION_OPEN,reason,s.symbol,0,0,0,0,0,0,0,0,0,0,true);
      BJournalAssert(guarded,"caller_seen_guards_remain_effective_after_restart",failed,checks);
     }
   restored.Close();
   parsed=BJournalReadRows(prefix+"_journal.csv",cells,rows);
   BJournalAssert(parsed && rows==3,"guarded_restart_does_not_append_duplicate_rows",failed,checks);

   // A complete-width record with a bad footer must refuse receipt recovery.
   int h=FileOpen(prefix+"_journal.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   bool corrupted=(h!=INVALID_HANDLE);
   if(corrupted)
     {
      FileSeek(h,0,SEEK_END);
      string corrupt_row="";
      for(int i=0;i<36;i++)
        {
         if(i>0) corrupt_row+=",";
         if(i==0) corrupt_row+=B_RULE_VERSION;
         if(i==35) corrupt_row+="CORRUPT_FOOTER";
        }
      corrupted=FileWriteString(h,corrupt_row+"\r\n")>0;
      FileFlush(h); FileClose(h);
     }
   BJournalAssert(corrupted,"create_invalid_footer_fixture",failed,checks);
   BJournal rejected;
   BJournalAssert(!rejected.Init(prefix,s.symbol,PERIOD_M5,"fallback-config",true),"corrupt_footer_refuses_initialization",failed,checks);
   rejected.Close();

   bool cleaned=true;
   if(FileIsExist(prefix+"_journal.csv") && !FileDelete(prefix+"_journal.csv")) cleaned=false;
   if(FileIsExist(prefix+"_equity.csv") && !FileDelete(prefix+"_equity.csv")) cleaned=false;
   BJournalAssert(cleaned,"cleanup_only_exact_test_files",failed,checks);
   PrintFormat("JOURNAL TEST SUMMARY: checks=%d passed=%d failed=%d",checks,checks-failed,failed);
   return failed;
  }
#endif
