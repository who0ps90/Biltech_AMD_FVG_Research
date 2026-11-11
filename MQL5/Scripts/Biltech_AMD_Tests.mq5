#property strict
#property script_show_inputs
#property description "Offline native fixtures only. This script never sends orders."
#include "../Include/BiltechAMD/SignalTests.mqh"
#include "../Include/BiltechAMD/TimeNewsTests.mqh"
#include "../Include/BiltechAMD/RiskExecutionTests.mqh"
#include "../Include/BiltechAMD/JournalTests.mqh"
void OnStart()
  {
   int failed=BRunSignalTests()+BRunTimeNewsTests()+BRunRiskExecutionTests()+BRunJournalTests();
   PrintFormat("BILTECH NATIVE FIXTURES: %s; failed assertions=%d; not a backtest",failed==0 ? "PASS":"FAIL",failed);
  }
