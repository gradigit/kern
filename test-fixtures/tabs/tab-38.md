# Tab Test 38 — Class Diagram

```mermaid
classDiagram
    class Animal {
        +String name
        +eat() void
    }
    class Dog {
        +bark() void
    }
    Animal <|-- Dog
```
