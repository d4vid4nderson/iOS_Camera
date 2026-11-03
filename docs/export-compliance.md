# Export compliance: Film Exposures (iOS)

A record of how the app uses encryption, for App Store Connect's export compliance
questions and for anyone who asks. Last reviewed: November 3, 2026.

## Summary

Film Exposures uses only encryption provided by Apple's operating system (HTTPS through
URLSession, the Keychain, and Apple's CryptoKit for one hash). It contains no proprietary
encryption, implements no standard encryption algorithms of its own, and bundles no
third-party cryptographic libraries. Under Apple's guidance this is exempt from export
compliance documentation, and the app declares it in its Info.plist:

```
ITSAppUsesNonExemptEncryption = NO
```

(Set as `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in `RetroCam.xcodeproj`, in
every build since the TestFlight workflow was added.)

## Every use of cryptography in the app

| Where | What | Provided by | Purpose |
|---|---|---|---|
| All network requests (`ShareAPI`, `RollShare`, `Social`, `Account`) | TLS (HTTPS) to filmexposures.com | iOS `URLSession` | Protect data in transit |
| `Account.swift` | Session token stored in the Keychain | iOS Security framework | Secure storage on the device |
| `Account.swift` | Sign in with Apple | iOS AuthenticationServices | Authentication |
| `SocialSignIn.swift` | SHA-256 of a one-time PKCE code verifier for Google and Facebook sign-in | Apple CryptoKit | Authentication (proves the sign-in request wasn't swapped) |
| `SocialSignIn.swift` | Google and Facebook sign-in pages | iOS `ASWebAuthenticationSession` (HTTPS) | Authentication |

There is no encryption of photos, files or messages by the app itself, no VPN or
tunnelling, no end-to-end encryption, and no custom or non-standard algorithms.

The share server (Cloudflare Workers) signs photo links with HMAC-SHA-256 and checks
sign-in tokens; that runs on the server, not in the app binary, and is also used only
for authentication.

## Answers for App Store Connect

If App Store Connect asks about encryption (for a build, or under App Information):

1. **Does your app use encryption?** Yes (it uses HTTPS).
2. **Does your app qualify for any of the exemptions provided in Category 5, Part 2 of the
   U.S. Export Administration Regulations?** Yes: it uses only encryption within Apple's
   operating system, and encryption used for authentication.
3. If it asks **which type of encryption algorithms** the app implements, choose
   **"None of the algorithms mentioned above"**. The app neither implements proprietary
   algorithms nor implements standard algorithms instead of, or in addition to, the
   encryption in Apple's operating system.
4. **France:** with only operating-system encryption, no French encryption declaration
   is needed.

With these answers no documentation upload, CCATS or compliance code is required.

## Year-end self-classification report

Apple notes that apps using exempt encryption "might" need a year-end self-classification
report to the U.S. Bureau of Industry and Security. That report is emailed to the
government, not uploaded to Apple or published. It applies to mass-market encryption
items under EAR 740.17(b)(1); an app whose only cryptography is the operating system's
HTTPS and authentication is generally outside that. Confirm with a lawyer if in doubt.

## When to review this again

- Adding a third-party SDK or library that includes cryptography (for example OpenSSL,
  libsodium, or an analytics/ads SDK with its own networking stack).
- Encrypting photos or data in the app beyond what iOS provides, end-to-end encryption,
  or any custom algorithm.

If any of these happen, `ITSAppUsesNonExemptEncryption` may need to become `YES`, with
documentation uploaded in App Store Connect.

References:
- Apple, *Complying with Encryption Export Regulations*:
  https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
