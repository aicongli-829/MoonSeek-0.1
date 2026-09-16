# `.fnrules` Reference

FileNest rule files are UTF-8 text. Each non-empty line contains one command. Whitespace separates arguments, double quotes preserve spaces, and `#` starts a comment outside quoted text.

```text
# Organize documents and normalize their names
scan recursive on
scan hidden off
classify custom
category extension "pdf,docx,txt" "Documents"
rename spaces
rename extension_lower
conflict number
sort name
sequence start 1 width 3
```

## Scan settings

| Syntax | Meaning |
| --- | --- |
| `scan recursive on|off` | Include or skip nested directories. |
| `scan hidden on|off` | Include or skip hidden entries. |
| `scan extensions "jpg,png"` | Limit the scan to a comma-separated extension list. |
| `scan exclude "relative/path"` | Skip a relative directory. Repeat to add more exclusions. |

Boolean settings also accept `true`/`false`, `yes`/`no`, and `开`/`关`.

## Classification

```text
classify none
classify type
classify month
classify type_month
classify custom
```

Custom classification evaluates category rules in order:

```text
category extension "pdf,docx" "Documents"
category keyword "invoice" "Finance"
```

An extension category uses a comma-separated list. A keyword category matches file names. Each rule needs a non-empty destination folder.

## Rename operations

| Syntax | Result |
| --- | --- |
| `rename prefix "Trip_"` | Add text before the base name. |
| `rename suffix "_final"` | Add text after the base name. |
| `rename remove "copy"` | Remove matching text. |
| `rename replace "old" "new"` | Replace text. |
| `rename spaces` | Normalize whitespace. |
| `rename lower` / `rename upper` | Change base-name case. |
| `rename extension_lower` | Lowercase the extension. |
| `rename separator "_"` | Normalize separators. |
| `rename number "Photo"` | Replace the base name with a numbered label. |
| `rename number_suffix "Photo"` | Append a numbered label. |
| `rename regex "pattern"` | Remove text matched by a regular expression. |

Rules run from top to bottom. At most 30 rename rules and 30 category rules are accepted.

## Ordering and conflicts

```text
sort name        # natural file-name order
sort path
sort month
sort size

conflict skip    # leave conflicting rows unchanged
conflict number  # append (2), (3), and so on

sequence start 1 width 3
```

Sequence start must be between `0` and `1,000,000`; width must be between `1` and `8`.

## Quoting and escapes

Quoted arguments support `\n`, `\r`, `\t`, `\"`, and `\\`. Diagnostics include the one-based source line. A rule file is rejected as a whole when any command is invalid.

Always run `preview` with a new rule file before using `apply`.
