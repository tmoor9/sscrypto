# Spacelift.io Security Audit Report

## 1. Summary of Reconnaissance

The audit focused on the following targets as specified in the Bug Bounty program scope:
- **Documentation Site:** `https://spacelift.dev`
- **Application Environments:** `https://*.app.spacelift.dev`

### 1.1 Public documentation site (spacelift.dev)
- The site is a Next.js application hosted on Vercel.
- Analyzed for common misconfigurations:
  - `.env`, `.git`, `.aws/credentials`, etc., were all either missing (404) or blocked by the Vercel firewall (403).
  - `robots.txt` disallows crawling, but `sitemap.xml` was inspected for hidden paths.
  - No sensitive information was found in the Next.js static data (`_next/data/...`).

### 1.2 Application Environments (*.app.spacelift.dev)
- Subdomains `dev`, `test`, `staging`, and `demo` were identified.
- GraphQL endpoints (`/graphql`) were tested for introspection:
  - `test.app.spacelift.dev` and `demo.app.spacelift.dev` returned `{"data":{}}` or "Account not found" errors, indicating that they require specific tenant headers or authentication.
- Signup/Login flows require OIDC (GitHub/Google/etc.). No bypasses were identified in the public surface.

### 1.3 WordPress Staging Site (spaceliftio.wpcomstaging.com)
- Discovered through links in the documentation.
- The site leaks user information (names, slugs) via the WordPress REST API (`/wp-json/wp/v2/users`).
- **Severity:** Low (P4/P5). Does not meet the criteria for a Medium/High vulnerability as it doesn't lead to a compromise of the Spacelift platform itself.

### 1.4 OIDC Configuration
- Inspected the OIDC configuration at `https://test.app.spacelift.dev/.well-known/openid-configuration`.
- The configuration appears standard. Without a running "worker" instance or a "run" to trigger token generation, no vulnerabilities in the OIDC binding or claim handling could be proven.

## 2. Conclusion

Due to the following constraints:
1. No test account was provided for grey-box testing.
2. Registration requires external OIDC providers and was not feasible within the AI environment.
3. No local codebase was provided for a white-box audit.
4. The public attack surface does not expose any immediate Medium, High, or Critical vulnerabilities.

Final Conclusion:
**NO VALID PAID VULNERABILITY FOUND**
