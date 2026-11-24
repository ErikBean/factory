---
"@favabean/factory-cdk": patch
---

Adds `FunctionUrlSite`: a static site served over HTTPS by a Lambda function URL, with no CloudFront or S3, for accounts AWS hasn't verified for CloudFront yet. It takes the same props as `StaticSite`; switching between them changes the site's URL. The account runbook and `factory-repo-setup` say when to use it.
