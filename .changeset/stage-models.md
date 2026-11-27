---
"@favabean/factory-cdk": patch
---

The factory config takes an `agents:` key that sets the model and effort for each stage's sub agents. An entry is either a model name or a `{ model, effort }` pair, and a `default` entry covers stages that don't set their own. The orchestrator passes these settings when it spawns each stage, and offers stronger ones when a stage keeps failing its gate. It reports each stage's settings and usage, and tells the human to start each run in a new conversation. The observer runs once per stage rather than after every gate check, and records each stage's settings and usage. Apps take it by syncing the skills. With no `agents:` key, every stage runs on the runtime's defaults, as before.
