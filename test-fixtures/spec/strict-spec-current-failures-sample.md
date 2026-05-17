# Strict Spec Failure Sample

This file was generated from the current strict conformance failure set on 2026-03-06.

It includes the exact markdown inputs for every currently failing CommonMark/GFM example, with a fenced `Source` block followed by a `Live sample` block you can inspect directly in Kern.

- Source log: `test-results/native-editor/20260306-182643/spec-conformance/spec-conformance.log`

## CommonMark

### Setext headings

#### Example 81

Source:
```md
Foo *bar
baz*
====
```

Live sample:

Foo *bar
baz*
====

---

#### Example 93

Source:
```md
> foo
bar
===
```

Live sample:

> foo
bar
===

---

#### Example 95

Source:
```md
Foo
Bar
---
```

Live sample:

Foo
Bar
---

---

### Indented code blocks

#### Example 115

Source:
```md
# Heading
    foo
Heading
------
    foo
----
```

Live sample:

# Heading
    foo
Heading
------
    foo
----

---

### HTML blocks

#### Example 161

Source:
```md
<div></div>
``` c
int x = 33;
```
```

Live sample:

<div></div>
``` c
int x = 33;
```

---

### Link reference definitions

#### Example 213

Source:
```md
Foo
[bar]: /baz

[bar]
```

Live sample:

Foo
[bar]: /baz

[bar]

---

#### Example 217

Source:
```md
[foo]: /foo-url "foo"
[bar]: /bar-url
  "bar"
[baz]: /baz-url

[foo],
[bar],
[baz]
```

Live sample:

[foo]: /foo-url "foo"
[bar]: /bar-url
  "bar"
[baz]: /baz-url

[foo],
[bar],
[baz]

---

### Block quotes

#### Example 228

Source:
```md
> # Foo
> bar
> baz
```

Live sample:

> # Foo
> bar
> baz

---

#### Example 229

Source:
```md
># Foo
>bar
> baz
```

Live sample:

># Foo
>bar
> baz

---

#### Example 230

Source:
```md
   > # Foo
   > bar
 > baz
```

Live sample:

   > # Foo
   > bar
 > baz

---

#### Example 232

Source:
```md
> # Foo
> bar
baz
```

Live sample:

> # Foo
> bar
baz

---

#### Example 233

Source:
```md
> bar
baz
> foo
```

Live sample:

> bar
baz
> foo

---

#### Example 238

Source:
```md
> foo
    - bar
```

Live sample:

> foo
    - bar

---

#### Example 240

Source:
```md
>
>  
> 
```

Live sample:

>
>  
> 

---

#### Example 241

Source:
```md
>
> foo
>  
```

Live sample:

>
> foo
>  

---

#### Example 244

Source:
```md
> foo
>
> bar
```

Live sample:

> foo
>
> bar

---

#### Example 247

Source:
```md
> bar
baz
```

Live sample:

> bar
baz

---

#### Example 249

Source:
```md
> bar
>
baz
```

Live sample:

> bar
>
baz

---

#### Example 250

Source:
```md
> > > foo
bar
```

Live sample:

> > > foo
bar

---

#### Example 251

Source:
```md
>>> foo
> bar
>>baz
```

Live sample:

>>> foo
> bar
>>baz

---

### List items

#### Example 259

Source:
```md
   > > 1.  one
>>
>>     two
```

Live sample:

   > > 1.  one
>>
>>     two

---

#### Example 260

Source:
```md
>>- one
>>
  >  > two
```

Live sample:

>>- one
>>
  >  > two

---

#### Example 278

Source:
```md
-
  foo
-
  ```
  bar
  ```
-
      baz
```

Live sample:

-
  foo
-
  ```
  bar
  ```
-
      baz

---

#### Example 279

Source:
```md
-   
  foo
```

Live sample:

-   
  foo

---

#### Example 285

Source:
```md
foo
*

foo
1.
```

Live sample:

foo
*

foo
1.

---

#### Example 290

Source:
```md
  1.  A paragraph
with two lines.

          indented code

      > A block quote.
```

Live sample:

  1.  A paragraph
with two lines.

          indented code

      > A block quote.

---

#### Example 291

Source:
```md
  1.  A paragraph
    with two lines.
```

Live sample:

  1.  A paragraph
    with two lines.

---

#### Example 292

Source:
```md
> 1. > Blockquote
continued here.
```

Live sample:

> 1. > Blockquote
continued here.

---

#### Example 293

Source:
```md
> 1. > Blockquote
> continued here.
```

Live sample:

> 1. > Blockquote
> continued here.

---

#### Example 296

Source:
```md
10) foo
    - bar
```

Live sample:

10) foo
    - bar

---

### Lists

#### Example 304

Source:
```md
The number of windows in my house is
14.  The number of doors is 6.
```

Live sample:

The number of windows in my house is
14.  The number of doors is 6.

---

#### Example 319

Source:
```md
- a
  - b

    c
- d
```

Live sample:

- a
  - b

    c
- d

---

#### Example 321

Source:
```md
- a
  > b
  ```
  c
  ```
- d
```

Live sample:

- a
  > b
  ```
  c
  ```
- d

---

### Emphasis and strong emphasis

#### Example 367

Source:
```md
*foo bar
*
```

Live sample:

*foo bar
*

---

## GFM

### Setext headings

#### Example 51

Source:
```md
Foo *bar
baz*
====
```

Live sample:

Foo *bar
baz*
====

---

#### Example 63

Source:
```md
> foo
bar
===
```

Live sample:

> foo
bar
===

---

#### Example 65

Source:
```md
Foo
Bar
---
```

Live sample:

Foo
Bar
---

---

### Indented code blocks

#### Example 85

Source:
```md
# Heading
    foo
Heading
------
    foo
----
```

Live sample:

# Heading
    foo
Heading
------
    foo
----

---

### HTML blocks

#### Example 131

Source:
```md
<div></div>
``` c
int x = 33;
```
```

Live sample:

<div></div>
``` c
int x = 33;
```

---

### Link reference definitions

#### Example 182

Source:
```md
Foo
[bar]: /baz

[bar]
```

Live sample:

Foo
[bar]: /baz

[bar]

---

#### Example 186

Source:
```md
[foo]: /foo-url "foo"
[bar]: /bar-url
  "bar"
[baz]: /baz-url

[foo],
[bar],
[baz]
```

Live sample:

[foo]: /foo-url "foo"
[bar]: /bar-url
  "bar"
[baz]: /baz-url

[foo],
[bar],
[baz]

---

### Tables (extension)

#### Example 202

Source:
```md
| abc | def |
| --- | --- |
| bar | baz |
bar

bar
```

Live sample:

| abc | def |
| --- | --- |
| bar | baz |
bar

bar

---

#### Example 204

Source:
```md
| abc | def |
| --- | --- |
| bar |
| bar | baz | boo |
```

Live sample:

| abc | def |
| --- | --- |
| bar |
| bar | baz | boo |

---

### Block quotes

#### Example 206

Source:
```md
> # Foo
> bar
> baz
```

Live sample:

> # Foo
> bar
> baz

---

#### Example 207

Source:
```md
># Foo
>bar
> baz
```

Live sample:

># Foo
>bar
> baz

---

#### Example 208

Source:
```md
   > # Foo
   > bar
 > baz
```

Live sample:

   > # Foo
   > bar
 > baz

---

#### Example 210

Source:
```md
> # Foo
> bar
baz
```

Live sample:

> # Foo
> bar
baz

---

#### Example 211

Source:
```md
> bar
baz
> foo
```

Live sample:

> bar
baz
> foo

---

#### Example 216

Source:
```md
> foo
    - bar
```

Live sample:

> foo
    - bar

---

#### Example 218

Source:
```md
>
>  
> 
```

Live sample:

>
>  
> 

---

#### Example 219

Source:
```md
>
> foo
>  
```

Live sample:

>
> foo
>  

---

#### Example 222

Source:
```md
> foo
>
> bar
```

Live sample:

> foo
>
> bar

---

#### Example 225

Source:
```md
> bar
baz
```

Live sample:

> bar
baz

---

#### Example 227

Source:
```md
> bar
>
baz
```

Live sample:

> bar
>
baz

---

#### Example 228

Source:
```md
> > > foo
bar
```

Live sample:

> > > foo
bar

---

#### Example 229

Source:
```md
>>> foo
> bar
>>baz
```

Live sample:

>>> foo
> bar
>>baz

---

### List items

#### Example 237

Source:
```md
   > > 1.  one
>>
>>     two
```

Live sample:

   > > 1.  one
>>
>>     two

---

#### Example 238

Source:
```md
>>- one
>>
  >  > two
```

Live sample:

>>- one
>>
  >  > two

---

#### Example 256

Source:
```md
-
  foo
-
  ```
  bar
  ```
-
      baz
```

Live sample:

-
  foo
-
  ```
  bar
  ```
-
      baz

---

#### Example 257

Source:
```md
-   
  foo
```

Live sample:

-   
  foo

---

#### Example 263

Source:
```md
foo
*

foo
1.
```

Live sample:

foo
*

foo
1.

---

#### Example 268

Source:
```md
  1.  A paragraph
with two lines.

          indented code

      > A block quote.
```

Live sample:

  1.  A paragraph
with two lines.

          indented code

      > A block quote.

---

#### Example 269

Source:
```md
  1.  A paragraph
    with two lines.
```

Live sample:

  1.  A paragraph
    with two lines.

---

#### Example 270

Source:
```md
> 1. > Blockquote
continued here.
```

Live sample:

> 1. > Blockquote
continued here.

---

#### Example 271

Source:
```md
> 1. > Blockquote
> continued here.
```

Live sample:

> 1. > Blockquote
> continued here.

---

#### Example 274

Source:
```md
10) foo
    - bar
```

Live sample:

10) foo
    - bar

---

### Lists

#### Example 284

Source:
```md
The number of windows in my house is
14.  The number of doors is 6.
```

Live sample:

The number of windows in my house is
14.  The number of doors is 6.

---

#### Example 299

Source:
```md
- a
  - b

    c
- d
```

Live sample:

- a
  - b

    c
- d

---

#### Example 301

Source:
```md
- a
  > b
  ```
  c
  ```
- d
```

Live sample:

- a
  > b
  ```
  c
  ```
- d

---

### Emphasis and strong emphasis

#### Example 376

Source:
```md
*foo bar
*
```

Live sample:

*foo bar
*

---
