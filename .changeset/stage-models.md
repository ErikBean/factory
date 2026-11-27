---
"@favabean/factory-cdk": patch
---

The factory config takes a `models:` key naming the model each stage's sub agents run on, and the orchestrator passes it when it spawns them. The orchestrator offers a stronger model when a stage keeps failing its gate, reports each stage's model and usage, and tells the human to start each run in a new conversation. The observer runs once per stage rather than after every gate check, and records each stage's model and usage. Apps take it by syncing the skills; with no `models:` key, every stage runs on the runtime's default as before.
