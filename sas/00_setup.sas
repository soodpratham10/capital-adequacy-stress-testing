/*=====================================================================
  00_setup.sas
  Enough for the Worst Year: capital adequacy for Northgate Public Auto

  Run first. Every chapter program starts with:
     %include "~/capital-adequacy-stress-testing/sas/00_setup.sas";
=====================================================================*/

/* ---- Project folder on SAS OnDemand (~ means your home folder) ---- */
%let root = ~/capital-adequacy-stress-testing;

/* ---- Library for project datasets ---- */
libname ng "&root/data";

/* ---- Valuation date: Northgate's balance sheet is struck here ---- */
%let valdate = '31DEC2026'd;

/* ---- General options ---- */
options nodate nonumber validvarname=v7 mprint;

/* ---- Confirm setup in the log ---- */
%put NOTE: =================================================;
%put NOTE: Northgate Public Auto project setup complete.;
%put NOTE: Project folder: &root;
%put NOTE: Valuation date: %sysfunc(putn(&valdate, date9.));
%put NOTE: =================================================;