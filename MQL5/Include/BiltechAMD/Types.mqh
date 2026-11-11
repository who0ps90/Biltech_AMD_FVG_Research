#ifndef BILTECH_AMD_TYPES_MQH
#define BILTECH_AMD_TYPES_MQH
#define B_RULE_VERSION "1.0.0"

enum BState
  {
   B_IDLE=0, B_RANGE_READY, B_SWEPT, B_RECLAIMED, B_FVG_CONFIRMED,
   B_ORDER_PENDING, B_POSITION_OPEN, B_COMPLETED, B_INVALIDATED
  };
enum BDirection { B_SHORT=-1, B_NONE=0, B_LONG=1 };
enum BSessionZone { B_NEW_YORK=0, B_LONDON=1, B_BROKER_SERVER=2 };
enum BBrokerDST { B_FIXED=0, B_US_DST=1, B_EU_DST=2 };

struct BSignalConfig
  {
   int lookback;
   int atr_period;
   double max_range_atr;
   int range_expiry_bars;
   int reclaim_bars;
   int fvg_bars;
   double min_fvg_atr;
  };

// All *_at timestamps are knowledge/event times in broker server time.
// MqlRates.time is always the candle OPEN time; bars are oldest -> newest.
struct BSetup
  {
   BState state;
   BDirection direction;
   long id;
   long session_id;
   string symbol;
   string config_id;
   datetime range_start;
   datetime qualified_at;
   datetime sweep_bar_open;
   datetime swept_at;
   datetime reclaim_at;
   datetime confirmed_at;
   datetime expires_at;
   datetime observed_qualification;
   datetime observed_sweep;
   datetime observed_reclaim;
   datetime observed_confirmation;
   double range_high;
   double range_low;
   double extreme;
   double zone_low;
   double zone_high;
   double atr_confirmation;
   double entry;
   double sl;
   double tp;
   double volume;
   double planned_risk_money;
   double spread_submission;
   int range_age;
   int sweep_age;
   int reclaim_age;
   bool attempted;
   ulong order_ticket;
   ulong position_id;
   string reason;
  };

struct BTransition
  {
   BState from_state;
   BState to_state;
   datetime at;
   BSetup snapshot;
   string reason;
  };

string BStateName(const BState state)
  {
   switch(state)
     {
      case B_IDLE: return "IDLE";
      case B_RANGE_READY: return "RANGE_READY";
      case B_SWEPT: return "SWEPT";
      case B_RECLAIMED: return "RECLAIMED";
      case B_FVG_CONFIRMED: return "FVG_CONFIRMED";
      case B_ORDER_PENDING: return "ORDER_PENDING";
      case B_POSITION_OPEN: return "POSITION_OPEN";
      case B_COMPLETED: return "COMPLETED";
      case B_INVALIDATED: return "INVALIDATED";
     }
   return "UNKNOWN";
  }

void BClearSetup(BSetup &s)
  {
   ZeroMemory(s);
   s.state=B_IDLE;
   s.direction=B_NONE;
   s.reason="Waiting for a qualifying completed range";
  }

bool BFinitePositive(const double value)
  {
   return MathIsValidNumber(value) && value>0.0;
  }

// MQL CSV primitives are delimiter based; keep each textual field a single cell.
string BCSVCell(string text)
  {
   StringReplace(text,",",";"); StringReplace(text,"\r"," "); StringReplace(text,"\n"," ");
   StringReplace(text,"\"","'"); return text;
  }

bool BStrategyComment(const string comment)
  { return StringFind(comment,"BAMD:")==0; }

double BTickFloor(const double price,const double tick)
  {
   return MathFloor(price/tick+1e-9)*tick;
  }
double BTickCeil(const double price,const double tick)
  {
   return MathCeil(price/tick-1e-9)*tick;
  }
#endif
