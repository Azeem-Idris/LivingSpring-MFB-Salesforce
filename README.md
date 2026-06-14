# LivingSpring MFB — Salesforce Implementation
**Blackforce Cohort 11 Internship Project**

## Project Overview
A full Salesforce CRM implementation for LivingSpring Microfinance 
Bank, a Tier 2 Unit Microfinance Bank operating in Lagos, Nigeria. 
Built as part of a 6-week consulting engagement project.

## What Was Built
- Custom data model with 12 custom objects (Loans, Customers, 
  Repayment Schedules, KYC Documents, Cooperative Groups, and more)
- 5 Lightning Apps (Customer Service, Credit, Operations, 
  Compliance, Executive) with persona-based access control
- 6 Permission Sets with Field-Level Security for sensitive 
  financial fields (BVN, NIN, Rate Snapshot, Outstanding Balance)
- Screen Flows for guided customer onboarding and loan application
- Record-Triggered Before Save Flow for snapshot pricing lock at 
  loan approval (immutable rate/fee fields)
- AI Records Assistant — LWC + Apex + Google Gemini API via Named 
  Credential — natural language to SOQL, deployed to Utility Bar 
  across all 5 apps
- Audit logging via AI_Action_Log__c for every AI interaction
- Salesforce Path components for Loan Application, Loan, Customer 
  (KYC Status), and Repayment Schedule objects
- Validation Rules for BVN/NIN (11-digit enforcement), Decline 
  Reason (required on decline), and financial integrity rules
- Test classes with 75%+ Apex code coverage

## My Role
**Salesforce Administrator & Platform/AI Developer**

### AI Records Assistant (FR-12) — Primary Owner
- Architected and built the AI Records Assistant from first principles 
  using LWC, Apex, and Google Gemini API — deliberately avoiding 
  Salesforce Agentforce per BRD requirements to demonstrate 
  foundational AI integration skills
- Designed and configured External Credential + Named Credential 
  authentication pattern for secure API key storage (key never 
  hardcoded in source code)
- Built AILLMService.cls (LLM callout service), AIAssistantController.cls 
  (security validation + query execution + audit logging), and 
  AILogWriter.cls (without sharing audit helper)
- Implemented multi-layer security: validateQuery() blocks all write 
  operations, `with sharing` enforces record-level sharing rules, 
  FLS respected via running-user query execution
- Engineered SCHEMA_CONTEXT prompt with lookup relationship guidance 
  and few-shot examples to ensure accurate SOQL generation for 
  LivingSpring's custom object schema
- Deployed LWC chat component to Utility Bar across all 5 Lightning Apps
- Wrote comprehensive Apex test classes (13 test methods) using 
  HttpCalloutMock pattern for callout testing

### Salesforce Administration & Configuration
- Configured 6 Permission Sets (LS_CSO_PSet, LS_CreditOfficer_PSet, 
  LS_BranchManager_PSet, LS_Operations_PSet, LS_Compliance_PSet, 
  LS_Executive_PSet) with Field-Level Security for sensitive financial 
  fields (BVN, NIN, Rate Snapshot, Origination Fee Snapshot, 
  Outstanding Balance, Days Past Due)
- Built Customer Enquiry Case object including Support Process, Record 
  Type, quick actions, and list views
- Created formula fields for auto-calculation of loan costs (Total 
  Interest, Origination Fee, Insurance Amount, Expected Monthly 
  Repayment) on Loan_Application__c
- Built Record-Triggered Before Save Flow for snapshot pricing lock 
  at loan approval — immutably copying rate, fee, insurance, principal, 
  tenor, and product name from Loan Product onto Loan record
- Created AI_Action_Log__c custom object and LS_AI_Read_PSet 
  permission set as Phase 1 AI foundation
- Built Salesforce Path components for Loan Application, Loan, 
  Customer (KYC Status), and Repayment Schedule objects with Key 
  Fields and Guidance for Success at every stage
- Added validation rules for BVN (11-digit enforcement), NIN 
  (11-digit enforcement), and Decline Reason (required on decline)
- Improved Flow UX through sections, display text, helper text, 
  progress indicators, and org-level theming via Themes and Branding
- Authored Change Set deployment documentation for sandbox-to-
  integration-org release (17 component entries)
- Authored comprehensive AI Records Assistant Build Guide documenting 
  complete build process, all issues encountered with resolutions, 
  security design decisions, and demo guide

## Tech Stack
- Salesforce Sales Cloud (Enterprise Edition)
- Apex (AIAssistantController, AILLMService, AILogWriter)
- Lightning Web Components (aiRecordsAssistant)
- Google Gemini API (gemini-2.5-flash) via Named Credential
- Salesforce CLI / VS Code with Salesforce Extensions
- Jira (sprint management), Confluence (documentation)

## Key Technical Decisions
- External Credential + Named Credential pattern for secure 
  API key storage (never hardcoded in Apex)
- Before Save Flow for snapshot pricing (not After Save) — 
  avoids recursive trigger issues and is more performant
- `with sharing` on AIAssistantController — enforces 
  Salesforce sharing rules on every AI-generated query
- Provider-agnostic service layer — AILLMService is the only 
  class that changes if the LLM provider changes
