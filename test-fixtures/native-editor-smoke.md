# Native Editor Smoke Test

This file focuses on the currently supported Markdown subset in the native editor prototype.

## Headings

# H1
## H2
### H3
#### H4
##### H5
###### H6

## Inline Formatting

Plain text.

This is **bold**, this is *italic*, this is `code`, and this is a [link](https://example.com).

Nested-ish: **bold with *****italic inside***** and more bold**.

Escapes: \\ backslash, \* asterisk, \` backtick, \[ brackets \].
- 

- 
- 
- sok\[ \] 
- [ ] sdas
- 1. 2'

- d

## Bullets
## 1.


## 1. dsd


- Bullet one
- Bullet two with **bold** and *italic* and `code`
- Bullet three with a [link](https://example.com/bullets)

## Tasks (Click The Checkbox)

- [x] Task 1 (unchecked)
- [x] Task 2 (checked)
- [x] Task 3 with **bold**
- [ ] Task 4 with `code` and a [link](https://example.com/tasks)

## Code Blocks

```swift
import Foundation

func hello(_ name: String) {
    print("Hello, \\(name)!")
}
```

```text
This is plain text inside a fenced code block.
It should be monospaced and have a subtle background.
```

