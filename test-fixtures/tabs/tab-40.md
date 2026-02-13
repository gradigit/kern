# Tab Test 40 — State Diagram

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Loading: open
    Loading --> Editing: loaded
    Editing --> Saving: save
    Saving --> Editing: done
    Editing --> [*]: close
```
