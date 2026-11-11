#ifndef BILTECH_AMD_NEWS_MQH
#define BILTECH_AMD_NEWS_MQH
#include "Time.mqh"

struct BNewsConfig
  {
   bool enabled;
   string filename;
   string currencies; // Explicit comma-separated ISO-style currency codes.
   int before_minutes;
   int after_minutes;
   datetime coverage_start_utc; // Declared provider coverage, inclusive.
   datetime coverage_end_utc;   // Exclusive; no completeness inferred from rows.
  };

struct BNewsWindow
  {
   datetime begin;
   datetime end; // Inclusive, including the exact after-minute boundary.
   string label;
  };

string BTrim(string value)
  {
   StringTrimLeft(value); StringTrimRight(value);
   return value;
  }

bool BCurrencyCode(const string value)
  {
   if(StringLen(value)!=3) return false;
   for(int i=0;i<3;i++)
     {
      ushort c=StringGetCharacter(value,i);
      if(c<'A' || c>'Z') return false;
     }
   return true;
  }

// RFC4180-style quoted fields and escaped quotes, one physical line per record.
// Multiline event text is deliberately unsupported and rejected.
bool BNewsCSVLine(const string line,string &fields[],string &reason)
  {
   ArrayResize(fields,0);
   string field="";
   bool quoted=false,closed=false,started=false;
   int count=0,n=StringLen(line);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(line,i);
      if(quoted)
        {
         if(c=='"')
           {
            if(i+1<n && StringGetCharacter(line,i+1)=='"') { field+="\""; i++; }
            else { quoted=false; closed=true; }
           }
         else field+=StringSubstr(line,i,1);
         continue;
        }
      if(c==',')
        {
         ArrayResize(fields,++count);
         fields[count-1]=BTrim(field);
         field=""; closed=false; started=false;
         continue;
        }
      if(closed)
        {
         if(c!=' ' && c!='\t') { reason="Text after closing CSV quote"; return false; }
         continue;
        }
      if(c=='"')
        {
         if(started || StringLen(BTrim(field))>0) { reason="Quote inside unquoted CSV field"; return false; }
         field=""; quoted=true; started=true;
         continue;
        }
      field+=StringSubstr(line,i,1);
      if(c!=' ' && c!='\t') started=true;
     }
   if(quoted) { reason="Unclosed CSV quote or unsupported multiline field"; return false; }
   ArrayResize(fields,++count);
   fields[count-1]=BTrim(field);
   if(count!=4) { reason="News CSV requires exactly four fields per record"; return false; }
   return true;
  }

void BNewsSort(BNewsWindow &windows[],const int left,const int right)
  {
   int i=left,j=right;
   datetime pivot=windows[(left+right)/2].begin;
   while(i<=j)
     {
      while(windows[i].begin<pivot) i++;
      while(windows[j].begin>pivot) j--;
      if(i<=j)
        {
         BNewsWindow temporary=windows[i]; windows[i]=windows[j]; windows[j]=temporary;
         i++; j--;
        }
     }
   if(left<j) BNewsSort(windows,left,j);
   if(i<right) BNewsSort(windows,i,right);
  }

class BNewsFilter
  {
private:
   BNewsConfig m_cfg;
   bool m_valid;
   string m_error;
   string m_currencies[];
   BNewsWindow m_windows[];

   bool Fail(const string message,string &reason)
     {
      m_valid=false; m_error=message; reason=message;
      ArrayResize(m_windows,0);
      return false;
     }

   bool Selected(const string currency)
     {
      for(int i=0;i<ArraySize(m_currencies);i++)
         if(m_currencies[i]==currency) return true;
      return false;
     }

public:
   BNewsFilter(void) { m_valid=false; m_error="News filter not initialised"; }

   bool Init(const BNewsConfig &cfg,string &reason)
     {
      m_cfg=cfg; m_valid=false; m_error="News filter initialisation failed";
      ArrayResize(m_windows,0); ArrayResize(m_currencies,0);
      if(!cfg.enabled) { m_valid=true; m_error=""; reason="News exclusions disabled"; return true; }
      if(cfg.before_minutes<0 || cfg.after_minutes<0 || cfg.before_minutes>10080 || cfg.after_minutes>10080)
         return Fail("News exclusion minutes must be between 0 and 10080",reason);
      if(!BSupportedTime(cfg.coverage_start_utc) || cfg.coverage_end_utc<=cfg.coverage_start_utc || cfg.coverage_end_utc>D'2100.01.01 00:00:00')
         return Fail("News filter requires explicit valid UTC coverage start and exclusive end",reason);
      string currencies=BTrim(cfg.currencies);
      if(StringSplit(currencies,',',m_currencies)<1)
         return Fail("News filter requires explicitly selected currencies",reason);
      for(int i=0;i<ArraySize(m_currencies);i++)
        {
         m_currencies[i]=BTrim(m_currencies[i]);
         if(!BCurrencyCode(m_currencies[i]))
            return Fail("Selected news currencies must be uppercase three-letter codes",reason);
         for(int j=0;j<i;j++)
            if(m_currencies[j]==m_currencies[i]) return Fail("Duplicate selected news currency",reason);
        }
      if(StringLen(BTrim(cfg.filename))==0) return Fail("Required news calendar filename is empty",reason);
      // Sandbox-local UTF-8 text. A Strategy Tester run must provision this file
      // in the agent Files directory (or use #property tester_file in its EA).
      ResetLastError();
      int file=FileOpen(cfg.filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
      if(file==INVALID_HANDLE) return Fail(StringFormat("Cannot open required news calendar '%s' (error %d)",cfg.filename,GetLastError()),reason);
      if(FileSize(file)>33554432)
        { FileClose(file); return Fail("News calendar exceeds 32 MiB safety limit",reason); }
      if(FileIsEnding(file))
        { FileClose(file); return Fail("Required news calendar is empty",reason); }
      string header=FileReadString(file);
      if(StringLen(header)>0 && StringGetCharacter(header,0)==0xFEFF) header=StringSubstr(header,1);
      if(header!="utc,currency,impact,event")
        { FileClose(file); return Fail("News CSV header must be exactly utc,currency,impact,event",reason); }
      int line_number=1,rows=0;
      while(!FileIsEnding(file))
        {
         string line=FileReadString(file);
         line_number++;
         string fields[],parse_reason;
         if(!BNewsCSVLine(line,fields,parse_reason))
           { FileClose(file); return Fail(StringFormat("News CSV line %d: %s",line_number,parse_reason),reason); }
         datetime event_utc=0;
         if(!BParseUTC(fields[0],event_utc))
           { FileClose(file); return Fail(StringFormat("News CSV line %d: invalid explicit UTC timestamp",line_number),reason); }
         if(event_utc<cfg.coverage_start_utc || event_utc>=cfg.coverage_end_utc)
           { FileClose(file); return Fail(StringFormat("News CSV line %d: event outside declared coverage",line_number),reason); }
         if(!BCurrencyCode(fields[1]))
           { FileClose(file); return Fail(StringFormat("News CSV line %d: invalid currency",line_number),reason); }
         string impact=fields[2]; StringToUpper(impact);
         if(impact!="HIGH" && impact!="MEDIUM" && impact!="LOW")
           { FileClose(file); return Fail(StringFormat("News CSV line %d: impact must be HIGH, MEDIUM or LOW",line_number),reason); }
         if(StringLen(fields[3])==0)
           { FileClose(file); return Fail(StringFormat("News CSV line %d: event name is required",line_number),reason); }
         if(++rows>200000)
           { FileClose(file); return Fail("News calendar exceeds 200000 event safety limit",reason); }
         // All records, including irrelevant currencies and low impact, have
         // already been validated before selection. A bad row never gets hidden.
         if(impact=="HIGH" && Selected(fields[1]))
           {
            int n=ArraySize(m_windows);
            ArrayResize(m_windows,n+1);
            m_windows[n].begin=event_utc-cfg.before_minutes*60;
            m_windows[n].end=event_utc+cfg.after_minutes*60;
            m_windows[n].label=fields[1]+" "+fields[3];
           }
        }
      FileClose(file);
      // An empty events list is allowed only with the user's explicit coverage
      // declaration. It is never treated as evidence of calendar completeness.
      int count=ArraySize(m_windows);
      if(count>1) BNewsSort(m_windows,0,count-1);
      int merged=0;
      for(int i=0;i<count;i++)
        {
         if(merged>0 && m_windows[i].begin<=m_windows[merged-1].end+1)
           {
            if(m_windows[i].end>m_windows[merged-1].end) m_windows[merged-1].end=m_windows[i].end;
            m_windows[merged-1].label="Overlapping selected high-impact news";
           }
         else
           {
            m_windows[merged]=m_windows[i];
            merged++;
           }
        }
      ArrayResize(m_windows,merged);
      m_valid=true; m_error="";
      reason=StringFormat("News CSV valid: %d rows, %d merged selected-HIGH windows; coverage is user-declared",rows,merged);
      return true;
     }

   bool Valid(void) { return m_valid; }

   bool Blocked(const datetime utc,string &reason)
     {
      if(!m_valid) { reason=m_error; return true; }
      if(!m_cfg.enabled) { reason="News exclusions disabled"; return false; }
      if(utc<m_cfg.coverage_start_utc || utc>=m_cfg.coverage_end_utc)
        { reason="UTC timestamp outside declared historical news coverage"; return true; }
      // Sorted, non-overlapping intervals permit logarithmic lookup per tick.
      int left=0,right=ArraySize(m_windows)-1;
      while(left<=right)
        {
         int middle=(left+right)/2;
         if(utc<m_windows[middle].begin) right=middle-1;
         else if(utc>m_windows[middle].end) left=middle+1;
         else { reason="News exclusion: "+m_windows[middle].label; return true; }
        }
      reason="Outside selected high-impact news exclusion windows";
      return false;
     }

   datetime NextBoundary(const datetime utc)
     {
      if(!m_valid) return utc;
      if(!m_cfg.enabled) return 0;
      string reason;
      if(Blocked(utc,reason)) return utc;
      int left=0,right=ArraySize(m_windows)-1;
      datetime next=m_cfg.coverage_end_utc;
      while(left<=right)
        {
         int middle=(left+right)/2;
         if(m_windows[middle].begin>utc) { next=m_windows[middle].begin; right=middle-1; }
         else left=middle+1;
        }
      return (next<m_cfg.coverage_end_utc ? next : m_cfg.coverage_end_utc);
     }
  };
#endif
