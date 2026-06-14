# LivingSpring MFB — AI Records Assistant (FR-12)
## Complete Build Documentation

**Author:** [Your name] — Platform/AI Developer, Group 3, Cohort 11
**Sprint:** Sprint 3 — UAT & Final Delivery
**Status:** Phase 1 (Read-only) — Complete

---

## 1. Overview

This document records the complete build process for the AI Records Assistant,
the natural-language chat component deployed to the Utility Bar across all
five LivingSpring MFB Lightning Apps (Customer Service, Credit, Operations,
Compliance, Executive).

**What it does:** A user types a plain-English question (e.g. "show all
loans in arrears in Yaba branch above ₦200,000"). The assistant converts
this into a SOQL query, executes it under the user's own permissions
(respecting Field-Level Security and sharing rules), and displays the
results as a clickable table inside the chat.

**Phase 1 scope (read-only):**
- Natural language to SOQL conversion
- Read-only query execution with security validation
- Results displayed in chat with clickable record links
- Every interaction logged to AI_Action_Log__c
- Graceful failure when the LLM is unavailable

**Out of scope for Phase 1 (stretch goal):**
- Write/update/delete operations with confirmation step
- LS_AI_Destructive_PSet permission set

---

## 2. Architecture

### 2.1 The five layers (per BRD FR-12)

| Layer | Component | File(s) |
|---|---|---|
| UI | LWC chat component | aiRecordsAssistant (html/js/css/meta.xml) |
| API | Apex controller | AIAssistantController.cls |
| Service | LLM callout service | AILLMService.cls |
| Audit | Custom object | AI_Action_Log__c |
| Security | Permission Set | LS_AI_Read_PSet |

### 2.2 Data flow

```
User types question in chat (LWC)
       |
       v
AIAssistantController.sendMessage() [Apex, @AuraEnabled]
       |
       v
AILLMService.askClaude() --[Named Credential callout]--> Gemini API
       |
       v
Gemini returns generated SOQL (as plain text)
       |
       v
validateQuery() - blocks INSERT/UPDATE/DELETE/MERGE/UPSERT/UNDELETE
       |
       v
Database.query() - executed under running user's permissions (with sharing)
       |
       v
formatRecords() - converts SObject results to display-friendly map
       |
       v
logInteraction() - writes to AI_Action_Log__c (always, success or failure)
       |
       v
Results returned to LWC, displayed as table with clickable Name links
```

### 2.3 LLM Provider Decision

**Evaluated:**
1. Anthropic Claude (direct API) — initially chosen
2. AWS Bedrock — rejected, too much AWS-side setup for the timeframe
3. OpenAI — rejected, free trial credits unreliable for new accounts
4. Google Gemini — final choice

**Why Gemini was chosen:**

Initial plan was Anthropic Claude via direct API, using the
recommended External Credential + Named Credential pattern
(more secure than Legacy Named Credentials, since the API key
is stored encrypted in the External Credential's Principal,
never in code).

The Claude integration was fully built and successfully connected
- Named Credential, External Credential, Principal, and Permission Set
grants were all correctly configured (see Section 6 for the
permission-grant issue we hit and fixed). However, the Claude
API returned a 401, which traced to **insufficient account
credit balance** on Anthropic's platform — a billing issue,
not a configuration issue.

Since this is an unpaid internship project, we switched to
**Google Gemini** (`gemini-2.5-flash`), which offers a genuinely
free tier (no card required) with rate limits (~15 req/min,
1500/day) far exceeding demo needs.

**Architecture impact:** Only `AILLMService.cls` changed.
`AIAssistantController.cls`, `AILogWriter.cls`, and the LWC
were untouched — proving the service layer is correctly
abstracted and provider-agnostic. This is a strong point to
make in the pitch.

**Pitch defense:** "We designed AILLMService as a swappable
service layer. We initially built and tested against Claude;
when we hit a billing constraint, switching to Gemini took
changing one class with no impact on the controller, audit
logging, or UI. In Phase 2, if LivingSpring standardizes on
a different provider, this is the only class that changes."

---

## 3. Infrastructure Setup (Step by Step)

### 3.1 Get a Gemini API key

1. Go to https://aistudio.google.com/apikey
2. Sign in with any Google account
3. Click "Create API Key" — no payment method required
4. Copy the key

### 3.2 Create the External Credential

Setup → Security → External Credentials → New
- Label: Claude_AI_Credential (name retained from initial Claude
  build — cosmetic only, does not affect function)
- Authentication Protocol: Custom
- Save

### 3.3 Add a Principal

On the External Credential detail page → Principals → New
- Parameter Name: ClaudePrincipal
- Sequence Number: 1
- Identity Type: Named Principal
- Save

### 3.4 Authentication Parameters (Note: superseded — see 3.7)

Initial Claude setup added two Authentication Parameters here
(x-api-key, anthropic-version). These were later removed when
switching to Gemini, because the Gemini integration ultimately
passes the API key via URL query string from Apex (see Section
3.7) rather than via Named Credential headers, due to a header
pass-through issue (documented in Section 6.4).

### 3.5 Create the Named Credential

Setup → Security → Named Credentials → New (the NEW tab, not Legacy)
- Label: ClaudeAI
- Name: GeminiAI (API Name — IMPORTANT: Apex references this
  exact name via `callout:GeminiAI`)
- URL: https://generativelanguage.googleapis.com
- External Credential: Claude_AI_Credential
- Generate Authorization Header: OFF
- Save

### 3.6 Remote Site Settings

Setup → Remote Site Settings → New
- Name: GeminiAI
- URL: https://generativelanguage.googleapis.com
- Active: checked
- Save

### 3.7 Custom Metadata Type for API Key storage

Because of the header pass-through issue (Section 6.4), the
Gemini API key is stored in Custom Metadata and appended to
the callout URL as a query parameter in Apex.

Setup → Custom Metadata Types → New
- Label: API Key
- Plural Label: API Keys
- Object Name: API_Key

Add custom field:
- Field Label: Key Value
- Field Name: Key_Value
- Type: Text (255)

Setup → Custom Metadata Types → API Key → Manage Records → New
- Label: Gemini API Key
- Name: Gemini_API_Key
- Key Value: [paste Gemini API key here]

### 3.8 Grant Permission Set access to the External Credential

This step was the cause of a "couldn't access the credential"
error (Section 6.3) and is easy to miss.

Setup → Permission Sets → LS_AI_Read_PSet → External Credential
Principal Access → Edit
- Move Claude_AI_Credential / ClaudePrincipal to Enabled
- Save

Then confirm your test user has LS_AI_Read_PSet assigned:
Setup → Users → [user] → Permission Set Assignments → confirm
LS_AI_Read_PSet is listed.

---

## 4. Apex Classes

### 4.1 Deploy order matters

AIAssistantController depends on AILLMService and AILogWriter.
Deploy in this order, or deploy all three together in one
folder-level deploy (Salesforce resolves dependency order within
a single deploy operation):

1. AILLMService.cls
2. AILogWriter.cls
3. AIAssistantController.cls

### 4.2 AILogWriter.cls

Small helper class. Declared `without sharing` so audit logging
always succeeds regardless of the running user's create
permissions on AI_Action_Log__c.

```apex
public without sharing class AILogWriter {
    public static void writeLog(AI_Action_Log__c log) {
        insert log;
    }
}
```

### 4.3 AILLMService.cls (final Gemini version)

[Insert the final Gemini version of AILLMService.cls here —
the one using GEMINI_MODEL_PATH and getApiKey() from Custom
Metadata, with the key appended as a URL query parameter]

Key points:
- Single public method: askClaude(systemPrompt, userMessage) -
  name retained from initial Claude build for compatibility
  with AIAssistantController, despite now calling Gemini
- Throws AILLMException on any HTTP error or callout failure -
  this is what allows graceful failure messaging in the UI
- API key retrieved from API_Key__mdt and appended to endpoint
  URL as ?key=... query parameter

### 4.4 AIAssistantController.cls

[Insert the final AIAssistantController.cls here, including the
final SCHEMA_CONTEXT with relationship field guidance and
few-shot examples from Section 6.5]

Key points:
- sendMessage() is the single @AuraEnabled entry point
- Declared `with sharing` - enforces record-level sharing rules
  automatically on every Database.query() call
- validateQuery() blocks all write-operation keywords before
  any query executes
- SCHEMA_CONTEXT teaches the LLM which fields are lookups and
  how to use relationship syntax (__r.Name) - critical fix,
  see Section 6.5
- logInteraction() writes to AI_Action_Log__c on every path:
  success, error, and clarification-needed
- Field names used: Generated_DML__c, Target_Records__c (matched
  to the actual AI_Action_Log__c schema built in LMFB-534, which
  used BRD section 17 stretch-goal naming rather than FR-12
  read-only naming - see Section 6.2)

---

## 5. LWC: aiRecordsAssistant

### 5.1 Files

- aiRecordsAssistant.html
- aiRecordsAssistant.js
- aiRecordsAssistant.css
- aiRecordsAssistant.js-meta.xml

### 5.2 js-meta.xml configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__UtilityBar</target>
        <target>lightning__RecordPage</target>
        <target>lightning__AppPage</target>
    </targets>
</LightningComponentBundle>
```

Note: targetConfigs with supportedFormFactors was attempted but
removed - `supportedFormFactors` is not a valid tag for the
lightning__UtilityBar target (see Section 6.7).

### 5.3 Adding to Utility Bar (all 5 apps)

Repeat for: LivingSpring Customer Service, LivingSpring Credit,
LivingSpring Operations, LivingSpring Compliance, LivingSpring
Executive

Setup → App Manager → [App] → Edit → Utility Items (Desktop Only)
→ Add Utility Item
- Component: aiRecordsAssistant
- Label: AI Assistant
- Icon: einstein
- Panel Width: 440
- Panel Height: 540
- Start automatically: unchecked
- Save

---

## 6. Issues Encountered and Resolutions (Chronological)

This section documents every real issue hit during the build, in
the order encountered, for future teams working on this org.

### 6.1 Empty .cls-meta.xml files causing silent deploy failures

**Issue:** Apex class files created manually in VS Code without
the SFDX scaffolding command had empty .cls-meta.xml files,
causing "Unexpected token <EOF>" errors that blocked deployment
of all files in the same batch.

**Fix:** Every .cls file needs a matching .cls-meta.xml with:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

### 6.2 AI_Action_Log__c field name mismatch

**Issue:** AIAssistantController.cls referenced
Generated_SOQL__c and Target_Object__c, but the actual object
(built in LMFB-534) used Generated_DML__c and Target_Records__c
- field names taken from BRD Section 17 (stretch goal CRUD
wording: "Generated DML... Target Records") rather than the
FR-12 read-only wording ("Generated SOQL... Target Object").

**Fix:** Updated Apex to reference the existing field names
rather than renaming Salesforce fields (which would have
required re-checking FLS across all Permission Sets).

### 6.3 "Couldn't access the credential" error

**Issue:** Apex callout failed with: "We couldn't access the
credential(s). You might not have the required permissions, or
the external credential 'Claude_AI_Credential' might not exist."
Despite the External Credential genuinely existing.

**Cause:** External Credentials require an EXPLICIT grant linking
a Permission Set to the Credential's Principal. Existence of the
credential is not sufficient - access must be granted separately.

**Fix:** Setup → Permission Sets → LS_AI_Read_PSet → External
Credential Principal Access → Edit → enable Claude_AI_Credential
/ ClaudePrincipal → Save. Also confirmed the test user has
LS_AI_Read_PSet assigned.

### 6.4 Claude 401, then Gemini 403 - header pass-through issue

**Issue (Claude):** After fixing 6.3, got HTTP 401 from Claude's
API. Diagnosed via curl/reqbin.com test outside Salesforce -
confirmed the API key itself was correctly stored, but Anthropic
account had insufficient credit balance (billing issue, not
config issue) - see Section 2.3 for the provider switch decision.

**Issue (Gemini, after switching providers):** Got HTTP 403
"Method doesn't allow unregistered callers" - Gemini's API
key, set as an Authentication Parameter (x-goog-api-key) on the
Principal, was not being forwarded as a header by the Named
Credential.

**Fix:** Abandoned header-based key passing entirely. Stored
the Gemini key in Custom Metadata (API_Key__mdt, see Section
3.7) and appended it as a URL query parameter
(?key=...) directly in AILLMService.cls. This is less "by the
book" than the External Credential pattern but fully functional
and the key is never hardcoded in source.

### 6.5 Renamed Named Credential broke callout reference

**Issue:** After renaming the Named Credential's API Name from
ClaudeAI to GeminiAI (for clarity/naming conventions), got:
"The callout couldn't access the endpoint... named credential
'ClaudeAI' might not exist."

**Cause:** Apex's `callout:ClaudeAI` string literal still
referenced the old API Name. Renaming a Label does not rename
the API Name automatically, and Apex references API Names.

**Fix:** Updated NAMED_CREDENTIAL constant in AILLMService.cls
from 'callout:ClaudeAI' to 'callout:GeminiAI'.

### 6.6 "This query could not be answered reliably" - lookup field schema issue

**Issue:** Queries like "show all loan applications with branch
named Yaba branch" returned the generic error message to the
user. Debug logging revealed Gemini generated:
`SELECT ... FROM Loan_Application__c WHERE LivingSpring_Branch__c
= 'yaba branch' LIMIT 200`
which failed with "invalid ID field: yaba branch" - because
LivingSpring_Branch__c is a Lookup field (holds a record ID),
not a text field.

**Fix:** Rewrote SCHEMA_CONTEXT to:
1. Explicitly state which fields are lookups and their
   relationship names (e.g. LivingSpring_Branch__r.Name)
2. List __r.Name relationship paths in each object's field list
3. Add few-shot example queries showing correct relationship
   syntax for common question patterns
4. Use LIKE '%Yaba%' instead of exact match for branch name
   filters, to tolerate phrasing variation ("Yaba", "Yaba branch",
   "YABA")

This fix resolved the majority of query failures since most
custom objects reference LivingSpring_Branch__c, Customer__c,
or Loan_Product__c as lookups.

### 6.7 LWC deployment - XML parsing and targetConfigs errors

**Issue 1:** "ParseError... processing instruction target
matching [xX][mM][lL] is not allowed" - caused by a malformed
or duplicated <?xml?> declaration in js-meta.xml.

**Fix:** Rewrote the file from scratch ensuring <?xml
version="1.0" encoding="UTF-8"?> is the literal first line with
nothing before it (no blank lines, no BOM character).

**Issue 2:** "The 'supportedFormFactors' tag isn't supported for
lightning__UtilityBar"

**Fix:** Removed the entire <targetConfigs> block. The <targets>
block alone is sufficient for Utility Bar/Record Page/App Page
exposure.

### 6.8 Apex test failures - validation rule on Account

**Issue:** All 10 AIAssistantControllerTest tests failed at
@testSetup with: "REQUIRED_FIELD_MISSING: BVN__c, NIN__c,
Birth_Date__c" - because the test Account record didn't satisfy
the BVN/NIN 11-digit validation rules (built in the demo
corrections sprint) and a required Birth_Date__c.

**Fix:** Updated setupData() to include valid 11-digit dummy
values for BVN__c and NIN__c and a placeholder Birth_Date__c.

### 6.9 Utility Bar close (X) button - replaced with Clear Chat

**Issue:** The X button's onclick dispatched a custom 'close'
event with no listener. Attempted fixes using
lightning/platformUtilityBarApi's getEnclosingUtilityId +
minimizeUtilityItem were inconsistent across contexts (returned
unresolved Proxy objects in some cases).

**Resolution:** Rather than depend on a fragile platform API for
a cosmetic close action (the Utility Bar icon itself already
toggles the panel open/closed - standard Salesforce behavior),
replaced the close button with a "Clear chat" reset button using
the standard utility:refresh icon. This removes the platform API
dependency entirely and adds genuine value - users can clear a
long conversation during a demo or work session.

## 7. Testing

### 7.1 Test classes

- AILLMServiceTest.cls - tests successful callout (mocked) and
  HTTP error handling, using HttpCalloutMock
- AILogWriterTest.cls - tests AI_Action_Log__c insertion
- AIAssistantControllerTest.cls - tests success path, no-results
  path, clarification path, DELETE/UPDATE blocking, invalid SOQL
  handling, LLM-unavailable handling, record-context handling,
  and audit logging - 10 test methods total

### 7.2 Running tests

Setup → Apex Classes → [test class] → Run Test
or
Setup → Apex Test Execution → select classes → Run

### 7.3 Coverage verification

Setup → Apex Classes → org-wide % Covered shown at top of page.
Target: 75%+ (Salesforce production deployment requirement)

Result as of [date]: [X]% - all 10 AIAssistantControllerTest
methods passing after the Section 6.8 fix, plus
AILLMServiceTest (2 methods) and AILogWriterTest (1 method).

---

## 8. Demo Guide

### 8.1 Tested working queries

| # | Persona | Query | Result |
|---|---|---|---|
| 1 | Compliance | "show all loans in arrears above 200000" | [confirm result] |
| 2 | Executive | "show all loans disbursed this month above 500000 with no repayment" | [confirm result] |
| 3 | Credit Officer | "find customers with KYC still pending review" | [confirm result] |
| 4 | Operations | "show repayment schedules due this week that are overdue" | [confirm result] |
| 5 | Any | "show all loan applications with the branch named yaba branch" | Confirmed working |

### 8.2 FLS/sharing rules demo

Log in as a Credit Officer (e.g. Tunde), ask "show all loans" -
should return only loans where the Credit Officer is assigned,
not other officers' pipelines. Enforced automatically by `with
sharing` on AIAssistantController.

### 8.3 Graceful failure demo

Temporarily put an invalid value in the Gemini_API_Key Custom
Metadata record, ask any question - should display "The AI
service is currently unavailable. Please try again in a moment."
Restore the correct key afterward.

### 8.4 Coverage demo for "tough question" defense

> "Show me how the AI Records Assistant prevents an admin from
> accidentally deleting an active loan. What model are you
> calling, where does it run, and what data leaves the org?"

**Answer:** "Three enforcement layers. First, validateQuery() in
AIAssistantController scans every generated query for INSERT,
UPDATE, DELETE, MERGE, UPSERT, and UNDELETE keywords and throws
a SecurityException before the query ever reaches the database.
Second, our system prompt instructs the LLM to only return SELECT
statements. Third, the controller class is declared 'with
sharing', so even a successfully-executed query respects
Salesforce's sharing rules for the running user. We're calling
gemini-2.5-flash via Google's Generative Language API. The only
data leaving the org is the user's natural language question and
our object schema description - no record data is sent to the
LLM."

To prove coverage live: Setup → Apex Classes →
AIAssistantControllerTest → click the % Covered link → shows
green/red highlighted lines in the actual class.