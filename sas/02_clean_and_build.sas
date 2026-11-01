/*=====================================================================
  02_clean_and_build.sas
  Enough for the Worst Year: Chapter 1, Meet the Insurer

  Reads Northgate's three raw files, finds and fixes the data
  problems, and builds the balance sheet at the valuation date.

     Capital Available = Assets - Unearned Premium - Unpaid Claims

  Saves clean datasets to the NG library for later chapters and
  exports the balance sheet to data/balance_sheet.csv.
=====================================================================*/

%include "~/capital-adequacy-stress-testing/sas/00_setup.sas";

/* Illustrative assumption: claims incurred but not yet reported (IBNR)
   are held at 15% of case reserves */
%let ibnr_load = 0.15;

/*---------------------------------------------------------------------
  1. Read the raw files
---------------------------------------------------------------------*/
proc import datafile="&root/data/raw_policies.csv" out=work.pol_raw dbms=csv replace;
   guessingrows=max;
run;

proc import datafile="&root/data/raw_claims.csv" out=work.clm_raw dbms=csv replace;
   guessingrows=max;
run;

proc import datafile="&root/data/raw_assets.csv" out=work.assets dbms=csv replace;
   guessingrows=max;
run;

/*---------------------------------------------------------------------
  2. Problem 1: duplicate policy records
     Keep one record per policy; the extras go to POL_DUPS
---------------------------------------------------------------------*/
proc sort data=work.pol_raw out=work.policies nodupkey dupout=work.pol_dups;
   by policy_id;
run;

/*---------------------------------------------------------------------
  3. Problem 2: duplicate claim records
     Keep one record per claim; the extras go to CLM_DUPS
---------------------------------------------------------------------*/
proc sort data=work.clm_raw out=work.clm_dedup nodupkey dupout=work.clm_dups;
   by claim_id;
run;

/*---------------------------------------------------------------------
  4. Problem 3: claims with no matching policy
     Set aside in ORPHANS for follow-up; keep matched claims, with
     the policy's territory attached
---------------------------------------------------------------------*/
proc sql;
   create table work.orphans as
      select c.*
      from work.clm_dedup as c
      where c.policy_id not in (select policy_id from work.policies);

   create table work.claims as
      select c.*, p.territory
      from work.clm_dedup as c
           inner join work.policies as p
           on c.policy_id = p.policy_id;
quit;

/*---------------------------------------------------------------------
  5. The territory "spike": claims by territory before and after
     cleaning
---------------------------------------------------------------------*/
proc sql;
   create table work.spike_raw as
      select coalesce(p.territory, '(no policy)') as territory length=12,
             count(*) as raw_claims
      from work.clm_raw as c
           left join work.policies as p
           on c.policy_id = p.policy_id
      group by calculated territory;

   create table work.spike_clean as
      select territory, count(*) as clean_claims
      from work.claims
      group by territory;

   create table work.spike as
      select r.territory as Territory,
             r.raw_claims as Raw_claims,
             coalesce(c.clean_claims, 0) as Clean_claims,
             case when calculated clean_claims > 0
                  then (r.raw_claims - calculated clean_claims) / calculated clean_claims
                  else . end as Overstated format=percent8.1
      from work.spike_raw as r
           left join work.spike_clean as c
           on r.territory = c.territory
      order by r.territory;
quit;

/*---------------------------------------------------------------------
  6. Data quality summary and case reserve reconciliation
---------------------------------------------------------------------*/
proc sql;
   create table work.dq_summary as
      select 'Policy records received' as Item length=50, count(*) as Records format=comma10.
         from work.pol_raw
      union all
      select 'Duplicate policy records removed', count(*) from work.pol_dups
      union all
      select 'Clean policies', count(*) from work.policies
      union all
      select 'Policies in force at valuation date', count(*) from work.policies
         where cancel_date is missing and exp_date > &valdate
      union all
      select 'Claim records received', count(*) from work.clm_raw
      union all
      select 'Duplicate claim records removed', count(*) from work.clm_dups
      union all
      select 'Claims with no matching policy (set aside)', count(*) from work.orphans
      union all
      select 'Clean claims', count(*) from work.claims;

   create table work.reserve_recon as
      select 'Case reserves in raw file' as Line length=50,
             sum(case_reserve) as Amount format=comma18.2
         from work.clm_raw
      union all
      select 'Less: duplicate claim records', -sum(case_reserve) from work.clm_dups
      union all
      select 'Less: claims with no matching policy', -sum(case_reserve) from work.orphans
      union all
      select 'Case reserves after cleaning', sum(case_reserve) from work.claims;
quit;

/*---------------------------------------------------------------------
  7. Balance sheet inputs
     Unearned premium: premium for the days of cover still to come,
     on policies in force (not cancelled) at the valuation date
---------------------------------------------------------------------*/
proc sql;
   create table work.bs_inputs as
      select
         (select sum(annual_premium*(exp_date - &valdate)/365)
             from work.policies
             where cancel_date is missing and exp_date > &valdate) as upr,
         (select sum(case_reserve) from work.claims)                   as case_res,
         (select sum(market_value) from work.assets
             where asset_class = 'Bond')                               as bonds,
         (select sum(market_value) from work.assets
             where asset_class = 'Equity')                             as equities,
         (select sum(market_value) from work.assets
             where asset_class = 'Cash')                               as cash
      from work.assets(obs=1);
quit;

/*---------------------------------------------------------------------
  8. The balance sheet
---------------------------------------------------------------------*/
data ng.balance_sheet;
   set work.bs_inputs;
   length section $12 item $45 amount 8;
   format amount comma18.2;

   bonds_r    = round(bonds, 0.01);
   equities_r = round(equities, 0.01);
   cash_r     = round(cash, 0.01);
   assets_r   = round(bonds_r + equities_r + cash_r, 0.01);

   upr_r      = round(upr, 0.01);
   case_r     = round(case_res, 0.01);
   ibnr_r     = round(&ibnr_load*case_res, 0.01);
   liab_r     = round(upr_r + case_r + ibnr_r, 0.01);

   capital_r  = round(assets_r - liab_r, 0.01);

   section = 'Assets';      item = 'Bonds';                         amount = bonds_r;    output;
   section = 'Assets';      item = 'Equities';                      amount = equities_r; output;
   section = 'Assets';      item = 'Cash';                          amount = cash_r;     output;
   section = 'Assets';      item = 'Total assets';                  amount = assets_r;   output;
   section = 'Liabilities'; item = 'Unearned premium';              amount = upr_r;      output;
   section = 'Liabilities'; item = 'Unpaid claims: case reserves';  amount = case_r;     output;
   section = 'Liabilities'; item = 'Unpaid claims: IBNR provision'; amount = ibnr_r;     output;
   section = 'Liabilities'; item = 'Total liabilities';             amount = liab_r;     output;
   section = 'Capital';     item = 'Capital available';             amount = capital_r;  output;

   keep section item amount;
run;

/*---------------------------------------------------------------------
  9. Save clean data for later chapters and export the balance sheet
---------------------------------------------------------------------*/
data ng.policies; set work.policies; run;
data ng.claims;   set work.claims;   run;
data ng.assets;   set work.assets;   run;

proc export data=ng.balance_sheet outfile="&root/data/balance_sheet.csv" dbms=csv replace;
run;

/*---------------------------------------------------------------------
  10. Report
---------------------------------------------------------------------*/
title "Chapter 1: Data quality summary";
proc print data=work.dq_summary noobs label;
run;

title "Chapter 1: Claims by territory, before and after cleaning";
proc print data=work.spike noobs label;
run;

title "Chapter 1: Case reserve reconciliation";
proc print data=work.reserve_recon noobs label;
run;

title "Northgate Public Auto: Balance sheet at %sysfunc(putn(&valdate, worddate18.))";
proc print data=ng.balance_sheet noobs label;
   var section item amount;
run;
title;