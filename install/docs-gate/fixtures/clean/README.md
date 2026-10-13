# Clean fixture

See [the guide](docs/guide.md), [its setup](docs/guide.md#set-up-the-tool), [the CLI](docs/guide.md#the-docs-check-cli) and [usage](#usage).

## Usage

Jump to [the second usage](#usage-1), [what's new](#whats-new-in-v20), [C++ & Go](#c--go) and [the anchor](#named-anchor).

## Usage

Second heading with the same text.

## What's new in v2.0?

## C++ & Go

<a name="named-anchor"></a>

External: [site](https://example.com/a#b), [mail](mailto:team@example.com), [Allye page](https://allye.app/hq/kb/ALY/ab12cd34), [subdomain](https://docs.allye.app/x) and [kb page](kb-page:ab12cd34).

Inline code is ignored: `[x](missing-inline.md)`.

```bash
# Not a heading
[x](missing-in-fence.md)
```

~~~
[y](missing-in-tilde.md)
~~~

- A list item with an indented fence:

  ```
  [z](missing-indented.md)
  ```

````markdown
```
[w](missing-nested.md)
```
````

Reference link [ref][r].

[r]: docs/guide.md#reference

Query strings are ignored: [plain](docs/guide.md?plain=1) and [plain anchor](docs/guide.md?plain=1#reference).
A root file starting with two dots is inside the root: [dots](..notes.md).
Angle-bracket targets with spaces: [spaced](<docs/my guide.md>) and [spaced anchor](<docs/my guide.md#spaced>).
Taken slugs: [usage-1-1](#usage-1-1) and [item-2](#item-2).
Quoted heading: [quoted](#quoted-heading).

## Usage-1

## Item

## Item-1

## Item

> ## Quoted heading
>
> ```
> [x](missing-quoted.md)
> ```

Case-insensitive anchor: [Usage](#Usage). Single-quoted anchor: [single](#single-anchor).
Parentheses in targets: [paren](foo(1).md). Underscores: [under](#init-and-my_var_-and-x_y).

<a id='single-anchor'></a>

## __init__ and my_var_ and _x_y_

Indented code block:

    ```
    [x](missing-indented-code.md)

Paragraph before a continuation line
    ```
is not a fence.
