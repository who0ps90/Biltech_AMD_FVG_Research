#ifndef BILTECH_AMD_VISUALS_MQH
#define BILTECH_AMD_VISUALS_MQH
#include "Types.mqh"
class BVisuals
  {
private:
   string m_prefix;
   long m_ids[];
   int m_limit;
   void Rectangle(const string name,const datetime left,const double high,const datetime right,const double low,const color shade)
     {
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,left,high,right,low);
      ObjectMove(0,name,0,left,high); ObjectMove(0,name,1,right,low);
      ObjectSetInteger(0,name,OBJPROP_COLOR,shade); ObjectSetInteger(0,name,OBJPROP_FILL,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
     }
   void Label(const string name,const datetime at,const double price,const string text,const color shade)
     {
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,at,price);
      ObjectMove(0,name,0,at,price); ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_COLOR,shade); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
     }
   void Level(const string name,const datetime at,const datetime end,const double price,const color shade)
     {
      if(price<=0) return;
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,at,price,end,price);
      ObjectMove(0,name,0,at,price); ObjectMove(0,name,1,end,price);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
     }
public:
   void Init(const ulong magic,const int history_limit) { m_prefix="BAMD_"+(string)magic+"_"; m_limit=history_limit; }
   void Draw(const BSetup &s,const datetime now)
     {
      if(s.id<=0) return;
      bool found=false;
      for(int i=0;i<ArraySize(m_ids);i++) if(m_ids[i]==s.id) found=true;
      if(!found)
        {
         int n=ArraySize(m_ids); ArrayResize(m_ids,n+1); m_ids[n]=s.id;
         if(n+1>m_limit)
           {
            ObjectsDeleteAll(0,m_prefix+(string)m_ids[0]+"_");
            for(int i=1;i<=n;i++) m_ids[i-1]=m_ids[i]; ArrayResize(m_ids,n);
           }
        }
      string key=m_prefix+(string)s.id+"_";
      datetime right=(s.confirmed_at>0 ? s.confirmed_at:MathMax(now,s.qualified_at));
      Rectangle(key+"range",s.range_start,s.range_high,right,s.range_low,clrDarkSlateGray);
      datetime detected=(s.observed_qualification>0 ? s.observed_qualification:s.qualified_at);
      Label(key+"detected",detected,s.range_high,"Range observed "+TimeToString(detected,TIME_DATE|TIME_SECONDS)+"; close="+TimeToString(s.qualified_at,TIME_SECONDS),clrLightGray);
      if(s.swept_at>0) Label(key+"sweep",(s.observed_sweep>0 ? s.observed_sweep:s.swept_at),s.extreme,"Sweep observed; close="+TimeToString(s.swept_at,TIME_SECONDS),clrOrange);
      if(s.reclaim_at>0) Label(key+"reclaim",(s.observed_reclaim>0 ? s.observed_reclaim:s.reclaim_at),(s.direction==B_LONG ? s.range_low:s.range_high),"Reclaim observed; close="+TimeToString(s.reclaim_at,TIME_SECONDS),clrAqua);
      if(s.confirmed_at>0)
        {
         datetime end=(s.expires_at>s.confirmed_at ? s.expires_at:s.confirmed_at+900);
         Rectangle(key+"fvg",s.confirmed_at,s.zone_high,end,s.zone_low,clrDarkGreen);
         Label(key+"confirmation",(s.observed_confirmation>0 ? s.observed_confirmation:s.confirmed_at),s.zone_high,"FVG observed; close="+TimeToString(s.confirmed_at,TIME_SECONDS),clrLime);
         Level(key+"entry",s.confirmed_at,end,s.entry,clrAqua);
         Level(key+"sl",s.confirmed_at,end,s.sl,clrRed); Level(key+"tp",s.confirmed_at,end,s.tp,clrLime);
        }
      Label(key+"state",right,s.range_low,BStateName(s.state)+": "+s.reason,(s.state==B_INVALIDATED ? clrTomato:clrWhite));
      ChartRedraw();
     }
  };
#endif
