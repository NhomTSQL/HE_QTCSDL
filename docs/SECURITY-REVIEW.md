# AR-IMMS security review — 2026-11-20

## Scope and evidence

Reviewed Flask authentication/API handlers, Next.js BFF routes, browser token handling,
CSV export, and the SQL procedures called by those routes. Tests run against the
edited source with mocked SQL; they do not claim to reproduce attacks against the
running database. No account passwords, roles, tickets or telemetry were changed
for this review. No authentication bypass or temporary production credentials were
used for testing.

This is a targeted source review with regression tests, not a complete penetration
test, dependency audit, or certification. Database migrations below remain unverified
on the live SQL Server.

## Confirmed findings and changes

| ID | Severity before changes | Finding and impact | Current source state |
|---|---|---|---|
| AUTH-01 | High | Missing session procedures caused authentication to fall back to trusting JWT alone. Revocation/disabled-account checks could be skipped. | Removed fallback: token issuance and authorization fail closed on DB/schema failure. Requires migration 26. |
| AUTH-02 | High | HTTP authorization relied on the role embedded in the token rather than the current database role. | Principal now comes from a live session/account query; invalid subject, session ID and security version are rejected. Migration 26 updates the query and invalidates sessions on credential/role changes. |
| AUTH-03 | High | SSE validated JWT signature but not a live session and did not recheck expiration/revocation during streaming. | Reuses the session validator; closes on expiration or failed validation at the next event/heartbeat (up to about 15 seconds). |
| BOLA-01 | High | Technicians could target arbitrary ticket IDs for status changes, notes and closure requests. Role checking alone did not verify assignment. | Added SQL authorization guard before these mutations. Technicians require assigned, nonclosed work; operators/admins keep their existing global operational permissions. |
| BOLA-02 | High | Any read-role user could request restart of any container by ID. | Field technicians now require an open/in-progress assigned ticket on that container's node. Admins/operators retain global restart permission. |
| CONFIG-01 | High if exposed | Running Flask directly enabled the debugger while binding every interface. | Debug disabled; default bind is loopback. FLASK_HOST is an explicit deployment choice; production still requires a proper WSGI server. |
| AUTH-04 | Medium | No API-level bound on repeated login/reset/MFA attempts or on password length. | Added a bounded, locked in-process attempt limiter and password input length validation. Production limitation described below. |
| INPUT-01 | Medium | Truthy JSON arrays could produce attribute errors; malformed notification input could be interpreted as marking all messages read. String "false" could trigger collector key rotation. | JSON object boundary and 1 MiB request limit; notification fields restricted; rotate_key requires an actual boolean. |
| DATA-01 | Medium | Account approval returned both the bootstrap password and the activation/recovery code. Sensitive responses did not consistently set no-store. | Bootstrap password removed from response. Flask responses and BFF upstream responses set no-store/nosniff. |
| CSV-01 | Medium | CSV quoting did not neutralize spreadsheet formulas in attacker-controlled text. | Formula-like strings are prefixed with an apostrophe; numeric inputs remain numeric. |
| MFA-01 | Medium | Setup could replace an already-enabled authenticator using an existing session. MFA state reads also used direct SELECT, incompatible with the intended EXECUTE-only DB role. | Migration 26 restricts setup to accounts without MFA and provides a scoped state-reading procedure. |
| PROXY-01 | Defense in depth | Proxy followed upstream redirects. No attacker-controlled redirecting upstream endpoint was confirmed. | HTTP(S), credential-free backend configuration; same-origin resolved paths; no redirect following; rejects traversal/encoded separators in catch-all segments. |

## Checks without a confirmed exploit in reviewed paths

- **SQL injection:** Flask uses bound SQLAlchemy parameters with fixed procedure
  names. The injection-shaped username regression verifies the payload is not
  interpolated into SQL text. Dynamic maintenance SQL reviewed uses database-derived
  quoted identifiers or typed integer partition numbers. This does not establish
  that every stored procedure is injection-free.
- **Mass assignment:** reviewed business writes build explicit parameter dictionaries.
  Actor/user identifiers are taken from the authenticated principal. Public account
  requests cannot directly create an Administrator account; approval remains an
  administrator operation. Tests cover actor spoofing and requested admin role.
- **Insecure deserialization:** no pickle, eval, unsafe YAML loader or equivalent
  executable-object deserialization was found in the API input paths inspected.
  JSON shape validation was still necessary.
- **Notification IDOR:** existing notification procedures scope both listing and
  marking read to authenticated user_id. Added a regression confirming supplied
  notification IDs do not replace this authenticated scope.
- **XSS:** reviewed React rendering uses ordinary escaped text; no raw HTML sink
  was found in these views. This was not a browser-based stored/DOM XSS assessment.
- **CSRF:** current browser calls send explicit Bearer headers rather than an
  automatically attached session cookie. If authentication is moved to cookies,
  add appropriate SameSite, Origin and CSRF-token protections.
- **Secret files:** git tracked-file listing did not show .env/private-key files.
  This is not a full repository-history or secret-value scan.

## Remaining risks / not completed by this review

1. **JWT in SSE URL (Medium):** page.tsx still creates EventSource with a token
   query parameter; the BFF forwards it. Tokens can therefore reach request logs.
   Move to a header-authenticated streaming fetch or a properly designed short-lived
   stream ticket. Redact existing URL query strings in access logs.
2. **MFA replay / step-up (Medium):** valid TOTP codes can be reused within the
   accepted time window; MFA setup does not require a fresh password confirmation.
   Add atomic counter consumption and fresh reauthentication for enrollment.
3. **Shared inventory/read scope needs a policy decision:** current roles may read
   shared node/ticket/maintenance information. Assignment limits added here apply to
   mutations, not all reads. If technicians must only see their own tickets/site,
   enforce row filters at every listing/lookup/history path, including QR lookup.
4. **Limiter is testbed-only:** counters are per process, reset on restart, and BFF
   users may share an IP. Use a shared datastore/gateway with account + client limits
   and trusted proxy configuration for production; do not trust caller-supplied XFF.
5. **DB permissions:** schema-wide EXECUTE also exposes administrative procedures
   such as the development password setter to the application DB identity.
   Replace with a maintained procedure allowlist and separate provisioning identity.
6. **SessionStorage and transport:** browser JWTs remain accessible to same-origin
   JavaScript. Deployment HTTPS, CSP, third-party scripts, reverse proxy configuration
   and stored-token exposure were not comprehensively assessed.
7. **Dependencies:** no successful registry-backed dependency/CVE audit was run.
8. **Database and browser verification:** SQL authorization lock behavior,
   migration execution, actual role matrix and browser interactions still need
   integration tests against an isolated SQL Server.

## Apply and verify

Back up the database and use a privileged migration identity in the intended
environment. Apply, in order:

1. database/25_password_recovery.sql
2. database/26_security_hardening.sql
3. Restart Flask with the updated dependencies/configuration and sign in again.

Migration 26 includes the updated authentication procedure and session-role query.
The application intentionally refuses authentication if the session schema cannot
be verified. Do not reinstate the former fail-open fallback to hide a migration error.
The script contains no reset, DROP TABLE or credential seeding.

Run source regression checks from the repository root:

    .venv/Scripts/python.exe -m unittest discover -s backend -p test_security_regressions.py -v

From web:

    node --test tests/security.test.cjs
    npm.cmd run build

Observed: 22 backend test methods passed, including four forbidden-object mutation
subcases; 6 proxy/CSV tests passed. SQL is mocked and proxy tests run transpiled
modules, so neither suite proves the live database or browser deployment is secure.

## Reference criteria

- OWASP API1:2023 Broken Object Level Authorization:
  https://api-security.owasp.org/editions/2023/en/0xa1-broken-object-level-authorization/
- OWASP SSRF Prevention Cheat Sheet (disable redirect following):
  https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
