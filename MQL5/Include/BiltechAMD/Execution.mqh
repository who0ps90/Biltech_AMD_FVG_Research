#ifndef BILTECH_AMD_EXECUTION_MQH
#define BILTECH_AMD_EXECUTION_MQH
#include "Types.mqh"
#include "Risk.mqh"

bool BOrderAccepted(const bool sent,const uint retcode)
  { return sent && (retcode==TRADE_RETCODE_PLACED || retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL); }

bool BPendingExpired(const datetime now,const datetime expiration)
  { return expiration<=0 || now>=expiration; }

bool BDailyHit(const int losses,const int maximum_losses,const double net,const double baseline,const double percent)
  { return losses>=maximum_losses || (baseline>0 && net<=-baseline*percent/100); }

class BExecution
  {
private:
   ulong m_magic;
   bool m_visual,m_demo,m_real;
   ulong m_retry_tickets[];
   int m_retry_counts[];
   datetime m_retry_times[];
   bool m_retry_close[];
   bool Retry(const ulong ticket,const datetime now,string &why,const bool close_action=false)
     {
      int n=ArraySize(m_retry_tickets),p=-1;
      for(int i=0;i<n;i++) if(m_retry_tickets[i]==ticket && m_retry_close[i]==close_action) p=i;
      if(p<0) { p=n; ArrayResize(m_retry_tickets,n+1); ArrayResize(m_retry_counts,n+1); ArrayResize(m_retry_times,n+1); ArrayResize(m_retry_close,n+1); m_retry_close[p]=close_action; m_retry_tickets[p]=ticket; m_retry_counts[p]=0; m_retry_times[p]=0; }
      if(m_retry_counts[p]>=3) { why="Management retry limit reached for ticket="+(string)ticket+"; inspect residual exposure"; return false; }
      if(now-m_retry_times[p]<5) return false;
      m_retry_counts[p]++; m_retry_times[p]=now; return true;
     }
public:
   void Init(const ulong magic,const bool visual,const bool demo,const bool real)
     { m_magic=magic; m_visual=visual; m_demo=demo; m_real=real; }
   bool Permission(string &why)
     {
      if(m_visual) { why="VisualOnly: order requests disabled"; return false; }
      if(!MQLInfoInteger(MQL_TESTER))
        {
         ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
         if(mode==ACCOUNT_TRADE_MODE_REAL && !m_real) { why="Real-account permission is false"; return false; }
         if((mode==ACCOUNT_TRADE_MODE_DEMO || mode==ACCOUNT_TRADE_MODE_CONTEST) && !m_demo) { why="Demo/contest permission is false"; return false; }
         if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { why="Terminal disconnected"; return false; }
        }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
        { why="Terminal, EA or account trading permission unavailable"; return false; }
      return true;
     }
   int Exposure()
     {
      int count=0;
      for(int i=OrdersTotal()-1;i>=0;i--) if(OrderGetTicket(i)>0 && (ulong)OrderGetInteger(ORDER_MAGIC)==m_magic) count++;
      for(int i=PositionsTotal()-1;i>=0;i--) if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_MAGIC)==m_magic) count++;
      return count;
     }
   bool SymbolUnmixed(const string symbol,string &why)
     {
      if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        {
         if(PositionSelect(symbol)) { why="Netting symbol has an existing position; ownership could mix"; return false; }
         for(int i=OrdersTotal()-1;i>=0;i--)
            if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==symbol)
              { why="Netting symbol has a working order; future ownership could mix"; return false; }
        }
      return true;
     }
   bool CheckLimit(const string symbol,const BSetup &s,const MqlTick &quote,string &why)
     {
      if(!BFinitePositive(quote.bid) || !BFinitePositive(quote.ask) || quote.ask<quote.bid || quote.time<=0)
        { why="Invalid live quote"; return false; }
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double min_distance=MathMax(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
      if(s.direction==B_LONG ? s.entry>=quote.ask || quote.ask-s.entry<min_distance : s.entry<=quote.bid || s.entry-quote.bid<min_distance)
        { why="Midpoint already marketable, missed, or inside broker stop/freeze distance"; return false; }
      if(MathAbs(s.entry-s.sl)<min_distance || MathAbs(s.tp-s.entry)<min_distance)
        { why="Protective prices violate broker distances; strategy prices retained"; return false; }
      long allowed=SymbolInfoInteger(symbol,SYMBOL_ORDER_MODE);
      if((allowed&SYMBOL_ORDER_LIMIT)==0 || (allowed&SYMBOL_ORDER_SL)==0 || (allowed&SYMBOL_ORDER_TP)==0)
        { why="Broker does not support limit with initial SL/TP"; return false; }
      ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
         (s.direction==B_LONG && mode==SYMBOL_TRADE_MODE_SHORTONLY) ||
         (s.direction==B_SHORT && mode==SYMBOL_TRADE_MODE_LONGONLY))
        { why="Instrument trading mode forbids this entry"; return false; }
      return true;
     }
   bool Submit(const string symbol,BSetup &s,string &why)
     {
      if(!Permission(why)) return false;
      MqlTradeRequest request={}; MqlTradeResult result={}; MqlTradeCheckResult checked={};
      request.action=TRADE_ACTION_PENDING; request.magic=m_magic; request.symbol=symbol;
      request.volume=s.volume; request.price=s.entry; request.sl=s.sl; request.tp=s.tp;
      request.type=(s.direction==B_LONG ? ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT);
      request.type_filling=ORDER_FILLING_RETURN;
      request.comment="BAMD:"+(string)s.id;
      long expiry=SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE);
      if((expiry&SYMBOL_EXPIRATION_SPECIFIED)!=0) { request.type_time=ORDER_TIME_SPECIFIED; request.expiration=s.expires_at; }
      else if((expiry&SYMBOL_EXPIRATION_GTC)!=0) request.type_time=ORDER_TIME_GTC;
      else { why="Broker has neither exact specified expiry nor GTC; unsupported"; return false; }
      if(!OrderCheck(request,checked) || (checked.retcode!=0 && checked.retcode!=TRADE_RETCODE_DONE))
        { why="OrderCheck rejected: "+(string)checked.retcode+" "+checked.comment; return false; }
      bool sent=OrderSend(request,result);
      if(!BOrderAccepted(sent,result.retcode))
        { why="OrderSend rejected/uncertain; never retried: "+(string)result.retcode+" "+result.comment; return false; }
      s.order_ticket=result.order;
      if(s.order_ticket==0) { why="Accepted request lacks order ticket; reconcile before any new entry"; return false; }
      why="Limit accepted with attached SL/TP; fills reconciled from transactions";
      return true;
     }
   bool Cancel(const ulong ticket,const datetime now,string &why)
     {
      if(!OrderSelect(ticket) || (ulong)OrderGetInteger(ORDER_MAGIC)!=m_magic || !BStrategyComment(OrderGetString(ORDER_COMMENT))) return false;
      if(!Permission(why) || !Retry(ticket,now,why)) return false;
      MqlTradeRequest request={}; MqlTradeResult result={};
      request.action=TRADE_ACTION_REMOVE; request.order=ticket; request.magic=m_magic;
      bool sent=OrderSend(request,result);
      why="Cancel ticket="+(string)ticket+" retcode="+(string)result.retcode+" "+result.comment;
      return BOrderAccepted(sent,result.retcode);
     }
   bool ClosePosition(const ulong ticket,const datetime now,BRiskLedger &ledger,string &why)
     {
      if(!PositionSelectByTicket(ticket) || (ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) return false;
      if(!ledger.SafePosition((ulong)PositionGetInteger(POSITION_IDENTIFIER)))
        { why="Refuse close: position history cannot prove exclusive EA ownership"; return false; }
      if(!Permission(why) || !Retry(ticket,now,why,true)) return false;
      string symbol=PositionGetString(POSITION_SYMBOL); MqlTick quote={};
      if(!SymbolInfoTick(symbol,quote) || quote.bid<=0 || quote.ask<=0) { why="No valid close quote"; return false; }
      MqlTradeRequest request={}; MqlTradeResult result={};
      request.action=TRADE_ACTION_DEAL; request.position=ticket; request.magic=m_magic; request.symbol=symbol;
      request.volume=PositionGetDouble(POSITION_VOLUME); request.deviation=20;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      request.type=(buy ? ORDER_TYPE_SELL:ORDER_TYPE_BUY); request.price=(buy ? quote.bid:quote.ask);
      long filling=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      if((filling&SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
      else if((filling&SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
      else if((ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET) request.type_filling=ORDER_FILLING_RETURN;
      else { why="No supported close filling policy"; return false; }
      bool sent=OrderSend(request,result);
      why="Close ticket="+(string)ticket+" retcode="+(string)result.retcode+" "+result.comment;
      return BOrderAccepted(sent,result.retcode);
     }
  };
#endif
