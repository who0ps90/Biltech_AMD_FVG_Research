#ifndef BILTECH_AMD_RISK_EXECUTION_TESTS_MQH
#define BILTECH_AMD_RISK_EXECUTION_TESTS_MQH
#include "Risk.mqh"
#include "Execution.mqh"
#include "Storage.mqh"

// Helper and isolated file fixtures only. No order request or account position
// mutation is called from this suite. Storage always uses local/tester files,
// a fresh test identity, and deletes only files created by that test identity.
void BRiskExecutionAssert(const bool condition,const string label,int &failed,int &checks)
  {
   checks++;
   if(!condition) failed++;
   PrintFormat("%s risk_execution.%s",condition ? "PASS" : "FAIL",label);
  }

bool BRiskExecutionNear(const double a,const double b)
  { return MathAbs(a-b)<1e-8; }

BSetup BRiskExecutionSetup(const BDirection direction)
  {
   BSetup s;
   BClearSetup(s);
   s.state=B_FVG_CONFIRMED;
   s.direction=direction;
   s.range_low=80;
   s.range_high=130;
   s.atr_confirmation=3;
   if(direction==B_LONG)
     { s.zone_low=100.1; s.zone_high=100.6; s.extreme=98.05; }
   else
     { s.zone_low=109.4; s.zone_high=109.9; s.extreme=112.05; }
   return s;
  }

BRiskConfig BRiskExecutionConfig()
  {
   BRiskConfig cfg;
   cfg.percent=0.25;
   cfg.daily_loss_percent=0.5;
   cfg.max_fills_session=2;
   cfg.max_losses_day=2;
   cfg.commission_roundtrip_per_lot=0;
   cfg.slippage_ticks_roundtrip=0;
   cfg.max_spread_fraction=0.10;
   cfg.max_spread_price=0;
   return cfg;
  }

void BRunStorageFixtures(int &failed,int &checks)
  {
   // Never borrow a live strategy identity or the common-files risk store.
   ulong magic=7000000000000000000+(GetTickCount64()%1000000000000)*1000+(GetMicrosecondCount()%1000);
   string prefix="";
   bool fresh=false;
   const ulong plan_ticket=9007199254740993;
   for(int attempt=0;attempt<5;attempt++)
     {
      prefix="BiltechAMD_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
             (string)BHash(AccountInfoString(ACCOUNT_SERVER))+"_"+(string)magic;
      fresh=!FileIsExist(prefix+".lock") && !FileIsExist(prefix+"_active.csv") &&
            !FileIsExist(prefix+"_active.csv.tmp") &&
            !FileIsExist(prefix+"_plan_"+(string)plan_ticket+".csv") &&
            !FileIsExist(prefix+"_plan_"+(string)plan_ticket+".csv.tmp");
      if(fresh) break;
      magic++;
     }
   BRiskExecutionAssert(fresh,"storage.fresh_test_namespace",failed,checks);
   if(!fresh) return;

   BStore store;
   string why="";
   bool initialized=store.Init(magic,true,why);
   BRiskExecutionAssert(initialized,"storage.acquire_local_test_lock",failed,checks);
   if(!initialized) return;
   BRiskExecutionAssert(store.Prefix()==prefix,"storage.expected_isolated_prefix",failed,checks);

   BSetup read;
   BClearSetup(read);
   datetime last=0;
   bool exists=true;
   bool loaded=store.Load(read,last,exists);
   BRiskExecutionAssert(!loaded && !exists,"storage.fresh_snapshot_absent",failed,checks);

   BSetup original=BRiskExecutionSetup(B_LONG);
   original.id=1704704400;
   original.session_id=20240108;
   original.symbol="UNITTEST_SYMBOL";
   original.config_id="unit-test:fixture-v1";
   original.range_start=D'2024.01.08 09:00:00';
   original.qualified_at=D'2024.01.08 09:15:00';
   original.sweep_bar_open=D'2024.01.08 09:15:00';
   original.swept_at=D'2024.01.08 09:20:00';
   original.reclaim_at=D'2024.01.08 09:25:00';
   original.confirmed_at=D'2024.01.08 09:30:00';
   original.expires_at=D'2024.01.08 09:45:00';
   original.entry=100.3;
   original.sl=97.7;
   original.tp=105.5;
   original.volume=0.2;
   original.planned_risk_money=25.125;
   original.spread_submission=0.15;
   original.range_age=3;
   original.sweep_age=2;
   original.reclaim_age=2;
   original.attempted=true;
   original.order_ticket=plan_ticket;
   original.position_id=9007199254740995;
   original.reason="fixture, preserve delimiter\nsecond line";
   datetime written_last=D'2024.01.08 09:25:00';
   BRiskExecutionAssert(store.Save(original,written_last),"storage.save_snapshot",failed,checks);
   exists=false;
   loaded=store.Load(read,last,exists);
   BRiskExecutionAssert(loaded && exists,"storage.load_existing_snapshot",failed,checks);
   BRiskExecutionAssert(last==written_last && read.range_start==original.range_start &&
                        read.qualified_at==original.qualified_at && read.sweep_bar_open==original.sweep_bar_open &&
                        read.swept_at==original.swept_at && read.reclaim_at==original.reclaim_at &&
                        read.confirmed_at==original.confirmed_at && read.expires_at==original.expires_at,
                        "storage.timestamps_roundtrip",failed,checks);
   BRiskExecutionAssert(read.state==original.state && read.direction==original.direction &&
                        read.id==original.id && read.session_id==original.session_id,
                        "storage.state_and_identity_roundtrip",failed,checks);
   BRiskExecutionAssert(read.symbol==BCSVCell(original.symbol) && read.config_id==BCSVCell(original.config_id) &&
                        read.reason==BCSVCell(original.reason),"storage.text_delimiters_sanitized",failed,checks);
   BRiskExecutionAssert(read.order_ticket==original.order_ticket && read.position_id==original.position_id,
                        "storage.tickets_above_double_integer_precision",failed,checks);
   BRiskExecutionAssert(BRiskExecutionNear(read.entry,original.entry) && BRiskExecutionNear(read.sl,original.sl) &&
                        BRiskExecutionNear(read.tp,original.tp) && BRiskExecutionNear(read.extreme,original.extreme) &&
                        BRiskExecutionNear(read.volume,original.volume) && BRiskExecutionNear(read.planned_risk_money,original.planned_risk_money),
                        "storage.price_and_risk_roundtrip",failed,checks);
   BRiskExecutionAssert(read.attempted && read.range_age==original.range_age && read.sweep_age==original.sweep_age &&
                        read.reclaim_age==original.reclaim_age,"storage.attempt_guard_roundtrip",failed,checks);

   BStore duplicate;
   BRiskExecutionAssert(!duplicate.Init(magic,true,why),"storage.concurrent_same_identity_refused",failed,checks);
   duplicate.Close();
   BSetup no_ticket=original;
   no_ticket.order_ticket=0;
   BRiskExecutionAssert(!store.SavePlan(no_ticket,written_last),"storage.zero_ticket_plan_refused",failed,checks);
   BRiskExecutionAssert(store.SavePlan(original,written_last),"storage.save_ticket_plan",failed,checks);
   BClearSetup(read);
   BRiskExecutionAssert(store.LoadPlan(plan_ticket,read) && read.order_ticket==plan_ticket &&
                        read.confirmed_at==original.confirmed_at,"storage.ticket_plan_roundtrip",failed,checks);

   store.Close();
   BStore restored;
   bool restarted=restored.Init(magic,true,why);
   BRiskExecutionAssert(restarted,"storage.reacquire_after_restart",failed,checks);
   if(restarted)
     {
      BClearSetup(read);
      BRiskExecutionAssert(restored.Load(read,last,exists) && read.attempted && read.order_ticket==plan_ticket &&
                           last==written_last,"storage.restart_preserves_attempt_and_bar",failed,checks);
      int h=FileOpen(prefix+"_active.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
      bool corrupted=(h!=INVALID_HANDLE);
      if(corrupted)
        { FileWriteString(h,"BAMD_STATE_1,1,5"); FileFlush(h); FileClose(h); }
      BRiskExecutionAssert(corrupted,"storage.create_truncated_snapshot_fixture",failed,checks);
      exists=false;
      BRiskExecutionAssert(!restored.Load(read,last,exists) && exists,"storage.corrupt_snapshot_fails_closed",failed,checks);
     }
   restored.Close();
   // No wildcard removal: these exact files belong to the fresh test prefix.
   string owned_files[5];
   owned_files[0]=prefix+".lock";
   owned_files[1]=prefix+"_active.csv";
   owned_files[2]=prefix+"_active.csv.tmp";
   owned_files[3]=prefix+"_plan_"+(string)plan_ticket+".csv";
   owned_files[4]=prefix+"_plan_"+(string)plan_ticket+".csv.tmp";
   bool cleaned=true;
   for(int i=0;i<5;i++)
      if(FileIsExist(owned_files[i]) && !FileDelete(owned_files[i])) cleaned=false;
   BRiskExecutionAssert(cleaned,"storage.cleanup_exact_test_files",failed,checks);
  }

int BRunRiskExecutionTests()
  {
   int failed=0,checks=0;
   string why="";
   {
    BSetup s=BRiskExecutionSetup(B_LONG);
    bool planned=BPlanPrices(s,0.1,0.15,why);
    BRiskExecutionAssert(planned,"plan_long.accepted",failed,checks);
    BRiskExecutionAssert(BRiskExecutionNear(s.entry,100.3) && BRiskExecutionNear(s.sl,97.7) && BRiskExecutionNear(s.tp,105.5),"plan_long.passive_midpoint_and_protective_rounding",failed,checks);
    BRiskExecutionAssert(BRiskExecutionNear((s.tp-s.entry)/(s.entry-s.sl),2),"plan_long.actual_2r",failed,checks);
    s.range_high=s.tp;
    BRiskExecutionAssert(BPlanPrices(s,0.1,0.15,why),"plan_long.exact_range_target_accepted",failed,checks);
    s.range_high=s.tp-0.1;
    BRiskExecutionAssert(!BPlanPrices(s,0.1,0.15,why),"plan_long.insufficient_reward_room_rejected",failed,checks);
   }
   {
    BSetup s=BRiskExecutionSetup(B_SHORT);
    BRiskExecutionAssert(BPlanPrices(s,0.1,0.15,why),"plan_short.accepted",failed,checks);
    BRiskExecutionAssert(BRiskExecutionNear(s.entry,109.7) && BRiskExecutionNear(s.sl,112.4) && BRiskExecutionNear(s.tp,104.3),"plan_short.passive_midpoint_and_protective_rounding",failed,checks);
    BRiskExecutionAssert(BRiskExecutionNear((s.entry-s.tp)/(s.sl-s.entry),2),"plan_short.actual_2r",failed,checks);
    s.range_low=s.tp;
    BRiskExecutionAssert(BPlanPrices(s,0.1,0.15,why),"plan_short.exact_range_target_accepted",failed,checks);
    s.range_low=s.tp+0.1;
    BRiskExecutionAssert(!BPlanPrices(s,0.1,0.15,why),"plan_short.insufficient_reward_room_rejected",failed,checks);
   }
   {
    BSetup s=BRiskExecutionSetup(B_LONG);
    BRiskExecutionAssert(BPlanPrices(s,0.1,0.7,why) && BRiskExecutionNear(s.sl,97.3),"buffer.spread_dominates",failed,checks);
    s=BRiskExecutionSetup(B_LONG);
    s.zone_low=100; s.zone_high=100.25; s.extreme=98.25; s.atr_confirmation=1;
    BRiskExecutionAssert(BPlanPrices(s,0.25,0.1,why) && BRiskExecutionNear(s.entry,100) && BRiskExecutionNear(s.sl,97.75) && BRiskExecutionNear(s.tp,104.5),"buffer.two_ticks_dominate_non_decimal_tick",failed,checks);
    s=BRiskExecutionSetup(B_LONG);
    BRiskExecutionAssert(!BPlanPrices(s,0,0.1,why),"plan_invalid.zero_tick",failed,checks);
    s.atr_confirmation=0;
    BRiskExecutionAssert(!BPlanPrices(s,0.1,0.1,why),"plan_invalid.zero_atr",failed,checks);
    s=BRiskExecutionSetup(B_LONG);
    BRiskExecutionAssert(!BPlanPrices(s,0.1,-0.1,why),"plan_invalid.negative_spread",failed,checks);
   }

   BRiskExecutionAssert(BRiskExecutionNear(BVolumeDown(0.257,0.01,0.01,10),0.25),"volume.round_down",failed,checks);
   BRiskExecutionAssert(BVolumeDown(0.009,0.01,0.01,10)==0,"volume.minimum_risk_violation_no_round_up",failed,checks);
   BRiskExecutionAssert(BRiskExecutionNear(BVolumeDown(0.01,0.01,0.01,10),0.01),"volume.exact_minimum",failed,checks);
   BRiskExecutionAssert(BRiskExecutionNear(BVolumeDown(12,0.1,0.1,10),10),"volume.maximum_cap",failed,checks);
   BRiskExecutionAssert(BRiskExecutionNear(BVolumeDown(0.99,0.25,0.25,10),0.75),"volume.non_decimal_step",failed,checks);
   BRiskExecutionAssert(BVolumeDown(1,0,0.01,10)==0 && BVolumeDown(1,0.01,2,1)==0,"volume.invalid_contract_rejected",failed,checks);

   BRiskConfig cfg=BRiskExecutionConfig();
   BRiskExecutionAssert(BSpreadOK(cfg,0.2,2,why),"spread.exact_fraction_boundary",failed,checks);
   BRiskExecutionAssert(!BSpreadOK(cfg,0.200001,2,why),"spread.excess_fraction_rejected",failed,checks);
   cfg.max_spread_price=0.15;
   BRiskExecutionAssert(BSpreadOK(cfg,0.15,2,why),"spread.exact_absolute_boundary",failed,checks);
   BRiskExecutionAssert(!BSpreadOK(cfg,0.150001,2,why),"spread.excess_absolute_rejected",failed,checks);
   BRiskExecutionAssert(!BSpreadOK(cfg,-0.1,2,why) && !BSpreadOK(cfg,0.1,0,why),"spread.invalid_quote_or_stop_rejected",failed,checks);
   BRiskExecutionAssert(BSpreadOK(cfg,0,2,why),"spread.zero_is_valid",failed,checks);

   BRiskExecutionAssert(!BDailyHit(1,2,-49.99,10000,0.5),"daily.just_above_loss_boundary_allowed",failed,checks);
   BRiskExecutionAssert(BDailyHit(1,2,-50,10000,0.5),"daily.exact_money_boundary_locked",failed,checks);
   BRiskExecutionAssert(BDailyHit(2,2,10,10000,0.5),"daily.exact_two_losses_locked",failed,checks);
   BRiskExecutionAssert(BDailyHit(3,2,10,10000,0.5),"daily.excess_losses_locked",failed,checks);

   BRiskExecutionAssert(BOrderAccepted(true,TRADE_RETCODE_PLACED),"order.pending_placed_accepted",failed,checks);
   BRiskExecutionAssert(BOrderAccepted(true,TRADE_RETCODE_DONE),"order.done_accepted",failed,checks);
   BRiskExecutionAssert(BOrderAccepted(true,TRADE_RETCODE_DONE_PARTIAL),"order.partial_fill_accepted_for_reconciliation",failed,checks);
   BRiskExecutionAssert(!BOrderAccepted(true,TRADE_RETCODE_REJECT),"order.rejected_not_accepted",failed,checks);
   BRiskExecutionAssert(!BOrderAccepted(false,TRADE_RETCODE_DONE),"order.send_false_not_accepted",failed,checks);
   BRiskExecutionAssert(!BOrderAccepted(true,TRADE_RETCODE_TIMEOUT),"order.uncertain_timeout_not_retried",failed,checks);

   datetime expiry=D'2024.01.08 09:45:00';
   BRiskExecutionAssert(!BPendingExpired(expiry-1,expiry),"expiry.before_boundary_active",failed,checks);
   BRiskExecutionAssert(BPendingExpired(expiry,expiry),"expiry.exact_boundary_expired",failed,checks);
   BRiskExecutionAssert(BPendingExpired(expiry+1,expiry),"expiry.after_boundary_expired",failed,checks);
   BRiskExecutionAssert(BPendingExpired(expiry,0),"expiry.missing_deadline_fails_closed",failed,checks);

   BRunStorageFixtures(failed,checks);
   PrintFormat("RISK EXECUTION TEST SUMMARY: checks=%d passed=%d failed=%d",checks,checks-failed,failed);
   return failed;
  }
#endif
