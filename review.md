# MACRO11 code review

Scope: all sources in `src/` at commit `5f553d7`.

Method: I read the code and built it twice in a scratch directory. One build was plain (`-O`). The other used
`-Wall -Wextra -fsanitize=address,undefined`. Each finding below was reproduced by assembling a small input,
except where it is marked *unverified*. Reproducers are written in `printf` escape syntax: `\t` is a tab and
`\n` is a newline. No source files were changed.

## Resolution (2026-10-03)

All findings below have been fixed, except where the table says otherwise. Each fix is covered by a
regression test in `src/tests/`, run with `make tests`.

| Finding | Status |
|---|---|
| 1.1 Errors not counted | Fixed. `report()` now counts every error it prints, and the exit status uses that count. |
| 1.2 Pass-0 messages lost | Fixed. Input files are checked before the object file is created. All open failures print a message. |
| 1.3 Doubled or missing locations | Fixed. Added `report_at()`. End-of-file errors point at the opening `.MACRO`/`.REPT`/`.IF`. |
| 1.4 Bad numbers, hang | Fixed. Invalid digits, numbers over 16 bits and missing progress are now errors. **Kept:** whitespace still separates `.WORD` values (`.WORD 1 2`), as before. |
| 1.5 Junk after operands | Fixed for all instructions. |
| 1.6 Truncation | Fixed: `.BYTE` range, EMT/TRAP (8 bits), MARK (6 bits). A literal over 177777 is an error. **Kept:** arithmetic still wraps at 16 bits (`177777+1` = 0), like MACRO-11. |
| 1.7 Unknown `.IF` condition | Fixed. The condition is now reported and treated as false. |
| 1.8 Unterminated string, stray `.ENDM`/`.ENDR`, label redefined with `=` | Fixed. **Not done:** a warning for a missing `.END`. |
| 2.1 Unterminated `.REPT`/`.IRP`/`.IRPC` | Fixed. `read_body()` returns failure at end of file. |
| 2.2 `.RAD50` hang | Fixed. Illegal characters are reported and encoded as blanks. |
| 2.3 Division by zero | Fixed. It is now an expression error. |
| 2.4 RLD overflow | Fixed. The accumulator is limited to what fits in an RLD record, and overflow reports "Expression too complex". |
| 2.5 Local label collisions | Fixed. Local labels are no longer truncated. |
| 2.6 Input file array | Fixed. 32 input files and 32 macro libraries are now enforced limits. |
| 2.7 `strncpy` | Fixed (`snprintf`). |
| 2.8 Leak | Fixed. `free_macro` now uses `buffer_free`. |
| 3.1 `.ASCII <n>` | Fixed. Byte values are parsed as a single term (`parse_term`). |
| 3.2 Object-file names | Fixed. A lossy name is a warning; two names that encode the same are an error. |
| 3.3 `toupper` | Fixed, together with `issym()` and the other `ctype` calls that were changed. |
| 3.4 Write errors | Fixed. Checked at `fclose`/`ferror`. |
| 3.5 Object format details | **Not changed** (unverified against the DEC specification). |
| 4.1 `.IIF` listing | Fixed. The data words now go on their own line with the PC. |
| 4.2 Duplicate `.END` line | Fixed. `file_gets` no longer returns an extra empty line at end of file. A last line with no newline now gets the correct line number. |
| 4.3 Format widths | Fixed. |
| 4.4 `symflags` | Fixed. |
| 5.1 to 5.4 `dumpobj` | Fixed: bounds checks, per-module reset, `CPLX_XOR`, `argc` check, exit status, GSD printed in file order. |
| 6.1 Tests | Fixed. Replaced with `tests/run-tests.sh`, which compares messages, exit status, listing and object dump with `tests/*.ref` (`-u` updates them). `argtests` is now POSIX `sh`. |
| 6.2 Warnings | Fixed, except the unused debug-only functions, which were kept on purpose. |

Additional bugs found and fixed while making these changes:

- **`SOB` and `RTS` error paths:** both freed the operand tree twice.
- **`.RESTORE`:** it did `sect_sp++` instead of `--`, so `.SAVE`/`.RESTORE` never worked.
- **`.SAVE` limit:** it now has an overflow check.
- **`^C` of a relocatable value:** it was emitted as a negation in the complex relocation.
- **Copied error nodes:** copying an `EX_ERR` node shared its child, which caused a double free on input like `.WORD <1`.
- **Nested `<...<...>...>`:** `brackrange` hung on nested brackets in macro and `.IRP` arguments. It also read past the end of a line when the closing delimiter was missing.
- **`.REPT 0`:** it emitted the body once. A repeat count of zero or less now emits nothing.
- **Macro search path:** `my_searchenv` called `strtok(envcopy, ...)` on every iteration. With two or more `-p` directories, it looped forever when the macro was not in the first one. It also leaked memory.
- **`-l -`:** the documented "list to stdout" option was rejected by the option check.
- **Uninitialized `next`:** streams created by `new_file_stream` and `buffer_stream_construct` never set it. A `.MCALL` file without `.ENDM` then popped garbage from the stack and deleted the stream twice.
- **`.MCALL` with no `.MACRO`:** a file that contained no `.MACRO` gave no error at all.
- **`\` argument buffer:** the buffer for `\expr` macro arguments was too small for binary radix (stack overflow).
- **FP registers:** register numbers were accepted up to 4 instead of 3 (AC0 to AC3).
- **Character constants:** `'` or `"` at the end of a line read past the string.
- **`%9`:** it was accepted as R0.
- **Macro library entries:** text without a final newline, or a truncated library, could produce garbage lines.
- **Header dependencies:** the makefile listed almost none, so after a header change `make` would link stale object files.
- **`test.mac`:** the junk-after-operands check now catches two real typos in `src/test.mac` (`BLE YT15:` on line 63 and `BMI TE5:` on line 256). The test file was left as it is.

Severity:
- **High**: crash, hang, memory corruption, or wrong output with no diagnostic.
- **Medium**: an error is wrong or missing, but the output is still usable.
- **Low**: cosmetic or robustness issue.

---

## 1. Error reporting and exit status (cross-cutting)

These problems affect almost every diagnostic, so they come first.

### 1.1 HIGH: Most reported errors are not counted, so the exit status is 0
`assemble_stack()` (assemble.c:1488-1502) only counts an error when `assemble()` returns 0. Many error
paths call `report()` and then `return 1` or carry on, so the error is printed but not counted. When no
counted error occurs, there is no "N Errors" summary and the exit code is `EXIT_SUCCESS`. Build scripts
therefore treat broken sources as good.

Examples, all of which print an error but exit 0:

| Input | Message | Code location |
|---|---|---|
| `X: BR X+1000` | Branch target out of range | `check_branch` result ignored, `return 1` (assemble.c:1224) |
| `A: NOP` / `A: NOP` | Illegal symbol definition | assemble.c:124, statement continues |
| `JMP R0` | JMP Rn is illegal | assemble.c:1141, encoded anyway, `return 1` |
| `.ASCII <15>/x/` | Invalid expression | — |
| `.MACRO FOO` without `.ENDM` | Macro body not closed | macros.c:91 |
| `MARK`/`EMT`/`TRAP` with a non-literal operand | Instruction requires simple literal operand | assemble.c:1118 |

**Fix:** count errors inside `report()` (for example with a global `error_count` that is incremented only
in pass 1), not through return values.

### 1.2 HIGH: `report()` discards every message in pass 0, including fatal ones
`report()` (listing.c:181) returns immediately when `pass == 0`. Some messages can only happen in pass 0,
so they are never printed:
- `macro11 nonexist.mac -o x.obj` exits with status 1 and **prints nothing**. The "Unable to open file"
  message at macro11.c:316 is swallowed.
- An empty `x.obj` is still created, because the object file is opened (macro11.c:297) before the inputs
  are checked.
- If `fopen` of the object file fails (macro11.c:298), the program returns `EXIT_FAILURE` silently.
- If `fopen` of the listing file fails (macro11.c:254), it is not checked at all and the listing is
  silently disabled.

**Fix:** use a separate `fatal()` that always prints, and open the inputs before creating any output.

### 1.3 MEDIUM: Some messages print a doubled location and lack a real one
- "Unterminated conditional" (macro11.c:381) calls `report(NULL, "%s:%d: ...")`, which prints
  `**:0: ***ERROR a7.mac:1: Unterminated conditional`.
- "Macro body not closed" (macros.c:91) runs at end of file, when `stack->top` is NULL. It prints
  `**:0: ***ERROR Macro body not closed` with no file or line, and is not counted (see 1.1).

### 1.4 MEDIUM: Bad numbers and junk operands are silently turned into extra data words
`do_word()` (assemble_aux.c:632-651) does not check that `parse_expr()` succeeded, that it consumed input,
or that the next character is a comma or end of line. `parse_expr` returns `EX_ERR` without reporting
anything. Consequences:

| Input | Result |
|---|---|
| `.WORD 9` | **Infinite loop / hang**. The `9` is never consumed. |
| `.WORD ^B102` | Two words `000002 000002`, no error |
| `.WORD 8.5` | Two words `000010 000005`, no error |
| `.WORD 1 2` | Two words, no error. MACRO-11 reports an error here. |

Any unknown-opcode line goes through the implicit `.WORD` path, so the same hang can be triggered from
many places. `.WORD 9` is a very easy typo to make in octal source.

### 1.5 MEDIUM: Junk after instruction operands is silently ignored
For example, `MOV R0,R1 junk` assembles to `010001` with no error. Instruction handlers do not check that
`cp` is at end of line or at a comment after the last operand.

### 1.6 MEDIUM: Values that do not fit are truncated without a diagnostic
In each case MACRO-11 would report a truncation (T) or address (A) error:

| Input | Result |
|---|---|
| `.BYTE 400` | Emits `000` |
| `.BYTE -200` | Emits `200` |
| `.WORD 200000`, `.WORD 177777+1` | Emits `000000` |
| `EMT 400` | Emits `104400`, which is `TRAP 0`. **Wrong code.** |
| `MARK 100` | Emits `006500`, which is `MARK 0`. **Wrong code.** |

The `OC_MARK` case (assemble.c:1107-1126) ORs the full literal into the opcode without a range check:
8 bits for EMT/TRAP, 6 bits for MARK. The same applies to SPL (3 bits), if it shares this path.

### 1.7 MEDIUM: Unknown `.IF` condition codes are accepted and use an uninitialized variable
`.IF XX 1` gives no error. In the expression branch (assemble.c:785-800), if no condition name matches,
`ok` and `word` are never set. GCC warns about this at assemble.c:800 and 823. The block is then assembled
or skipped depending on whatever value happens to be on the stack.

### 1.8 MEDIUM: Missing diagnostics for malformed directives
- **Unterminated string:** `.ASCII /abc` without the closing delimiter assembles silently.
- **`.ENDM` outside a macro:** accepted silently.
- **Redefining a label with `=`:** `C: .WORD 0` then `C=5` is silently ignored. `add_sym` returns NULL for
  a permanent symbol, and the `=` path (assemble.c:220-240) returns without reporting. Expected: an M
  (multiple definition) error.
- **Missing `.END`:** accepted without a warning. *Low.*

---

## 2. Crashes, hangs and memory errors in the assembler

### 2.1 HIGH: `.REPT`, `.IRP` or `.IRPC` without `.ENDR` causes a segfault
At end of file, `read_body` returns and `stack->top` is NULL. `expand_rept` (rept_irpc.c:100) and the
`.IRP`/`.IRPC` code (rept_irpc.c:228) then dereference `stack->top->name`.

Reproducer:
```
printf '\t.REPT 3\n\tNOP\n\t.END\n'
```
Result: SIGSEGV.

### 2.2 HIGH: `.RAD50` with a non-RAD50 character hangs
`rad50()` (rad50.c:62-64) does not advance `*endp` past an illegal character. The loop in `.RAD50`
(assemble.c:1076-1080) therefore stores words forever.

Reproducer: `.RAD50 /A-B/`.

### 2.3 HIGH: Division by zero crashes with SIGFPE
`evaluate()` (extree.c:539) divides without checking for zero.

Reproducer: `.WORD 1/0` crashes the assembler. Expected: an error, with the result treated as 0.

### 2.4 HIGH: Complex relocation overflows the RLD buffer and the relocation is silently lost
- `text_fit()` (object.c:309-324) flushes the buffer when an entry does not fit, but does not check that
  the entry fits in an *empty* buffer.
- A complex RLD entry can be up to 2 + 126 bytes long, plus a 2-byte header, which exceeds `rld[128]`.
- `rld_byte()` (object.c:372) then writes past the array, into `tr->rld_offset`.

Reproducer: `.WORD G0+G1+...+G20` (21 globals). UBSan reports index 128 out of bounds. The plain build
exits 0 and writes **no RLD entry** for that word, so the linker produces a wrong value.

Related problem: `text_complex_fit` returns NULL when its accumulator is full, but every caller ignores
that. `complex_tree` in assemble_aux.c ignores it, and so do `text_complex_commit` and
`text_complex_commit_displaced`, which ignore the result when they append `CPLX_STORE`. With 22 or more
terms the expression is truncated with no STORE byte. Expected: an "expression too complex" error.

### 2.5 HIGH: Local labels collide after block 9 or 99, depending on label length
- parse.c builds internal local-label names as `"%ld$%d"`, the label followed by the block number, for
  example `1000$10`.
- `add_sym` (symbols.c:192) truncates names to `symbol_len` (6), so `1000$10` becomes `1000$1`. That is
  the same name as `1000$` in block 1.
- `lookup_sym` does not truncate, so references are not found either.

Result: from block 10 onward you get "Illegal symbol definition 1000$10" and "Bad branch target". With
`10$` the collision starts at block 1000, which a large source easily reaches.

**Fix:** never truncate internal local-label names, or apply the same truncation in lookup.

### 2.6 MEDIUM: Too many input files overflow a stack array
`fnames[32]` (macro11.c:157) is filled at line 293 without a bounds check. 33 or more input files overflow
the array.

### 2.7 LOW: `strncpy` into `macfile` may leave the string unterminated
assemble.c:549 uses `strncpy(macfile, label, sizeof(macfile))`. If `label` is that long, the result is
not NUL-terminated and the following `strncat` overruns the buffer.

### 2.8 LOW: Memory leak
LeakSanitizer reports a 1054-byte leak from `buffer_appendn` (stream2.c:126) on every run of
`src/test.mac`. This is harmless for a one-shot tool, but it makes leak checking noisy.

---

## 3. Wrong code or parsing (no crash)

### 3.1 MEDIUM: `.ASCII`/`.ASCIZ` with angle-bracket byte values is broken
- `.ASCII <15>/x/` reports "Invalid expression" and emits a single `000`.
- `.ASCIZ <15><12>/x/` emits `015 000 000`.

Both are standard MACRO-11 syntax, for example a CR/LF prefix. Expected output: `015 012 170 000`. The
error is also not counted (see 1.1).

### 3.2 MEDIUM: Global symbol names are mangled or collide in the object file
`rad50x2` (rad50.c:98-106) stops at the first non-RAD50 character and after 6 characters, without a
warning:
- With `-yus`, `.GLOBL A_B, A_C` produces two references that are both named `A`.
- With `-ysl 10`, `LONGNAME1==1` and `LONGNAME2==2` produce two definitions of `LONGNA`.

Expected: at least a warning when an object-file name loses characters or collides with another name.

### 3.3 LOW: `toupper` on a plain `char`
`toupper(*cp)` at rad50.c:62, 74 and 84 is undefined behaviour for bytes ≥ 0x80. Cast the argument to
`unsigned char`.

### 3.4 LOW: `writerec` ignores write errors
`writerec` does not check the result of `fputc` for the checksum byte (object.c:102). The callers in
macro11.c ignore its return value, so a full disk produces a corrupt object file and exit status 0.

### 3.5 LOW (*unverified*): Object format details
- TEXT records can reach 132 bytes including the header. Other DEC tools may expect at most 128.
- `gsd_xfer` (object.c:207) writes flags `010` on the transfer-address GSD entry, where the DEC
  specification has 0.

Check both against the RT-11/RSX object-format specification.

---

## 4. Listing file

### 4.1 MEDIUM: `.IIF` lines lose the PC column
`.IIF NE 1, .WORD 1` is listed as `1 000001000001`. `list_value()` writes the condition value into the
PC column. `list_word()` (listing.c:91-120) then finds `binline` longer than the PC column but shorter
than the source column, so it appends the data word straight after the value. The PC is never printed.
Expected: the listing shows the PC (`000000`) followed by the data word.

### 4.2 LOW: The `.END` line number is printed twice
Every listing ends with the `.END` line, followed by a second line that contains only the same line
number. The same happens when there is no `.END`. This is caused by an extra `list_flush` at end of
input.

### 4.3 LOW: `%*s` gets a `size_t` field width
listing.c:105-137 passes `offsetof(...)` and `SIZEOF_MEMBER(...)`, which are `size_t`, as `%*` field
widths. `printf` expects an `int`. On LP64 targets that is undefined behaviour; it works on x86-64 by
accident. Cast to `int`, as line 66 already does.

### 4.4 LOW: `symflags()` always returns an empty string
`symflags()` (symbols.c:66) returns `fp`, which points to the end of the string, instead of `temp`. Only
the debug tree dump is affected.

---

## 5. `dumpobj`

### 5.1 HIGH: Use-after-free on object files with more than one module
`got_endgsd` (dumpobj.c:382) frees `all_gsds`, but does not reset `nr_gsds` or `gsdsize` or NULL the
pointer. The next module writes into freed memory and frees it again.

Reproducer: `cat a.obj b.obj > two.obj; dumpobj two.obj` segfaults.

`psects[]`, `psectid` and `xferad` are also never reset per module, so CPLX_REL sector names are wrong in
later modules.

### 5.2 HIGH: No bounds checks when parsing records
Crafted or truncated input causes heap overreads in several places:

| Input | Location |
|---|---|
| Empty record | dumpobj.c:643 |
| GSD record ending mid-entry | dumpobj.c:299/311 |
| TEXT record shorter than 4 bytes | dumpobj.c:391 |
| Truncated RLD entry | dumpobj.c:421/407 |
| Complex string with no STORE byte | dumpobj.c:524-585 |

Two more cases:
- More than 256 PSECTs overflows `psects[256]` (dumpobj.c:336).
- An unknown CPLX_REL sector hits `assert` (dumpobj.c:568). With `NDEBUG` it reads out of bounds instead.

### 5.3 MEDIUM: "PSECT displaced" (RLD type 014) prints a stale value
This RLD type has no constant, but dumpobj.c:495-500 prints `word` anyway.

Example: in psect BBB, `.WORD X+5` followed by `MOV X,R0` (X in psect AAA) prints `AAA+5` instead of
`AAA`.

### 5.4 LOW: Smaller dumpobj issues
- `CPLX_XOR` (complex code 07) is not decoded.
- `argv[1]` and `argv[2]` are used without checking `argc`.
- A truncated file or bad checksum still returns `EXIT_SUCCESS`.
- EOF before the checksum byte is reported as a checksum mismatch instead of a truncated file.
- GSD lines are sorted with `qsort`, so their printed order no longer matches the GSD order that CPLX_REL
  sector numbers refer to.

---

## 6. Build and test infrastructure

### 6.1 The `tests` target does not work
- `make tests` refers to `tests/test-undef.mac`, but there is no `tests/` directory.
- `argtests` uses `(( ... ))`, which is bash-only, while make runs `/bin/sh`. On systems where that is
  dash, every test prints FAIL or a syntax error.
- The last check uses `$$OPT` outside the loop, where it is empty.

There are no tests that check the generated output. `src/test.mac` is only assembled, never compared with
expected results.

### 6.2 Compiler warnings
`-Wall -Wextra` reports about 45 warnings. These are worth fixing:
- `maybe-uninitialized` at assemble.c:800 and 823 (the real bug in 1.7) and at mlb.c:263.
- Implicit fall-through at assemble.c:693, assemble_aux.c:230 and extree.c:127. Check that each is
  intended and mark it.
- The `-Wformat` warnings in listing.c (4.3).

Everything else is unused variables and parameters.

---

## Suggested fix order
1. Fix error counting and pass-0 reporting (1.1, 1.2), so that every diagnostic is printed and changes the
   exit status.
2. Fix the hangs and crashes: `.WORD 9` (1.4), `.RAD50` (2.2), division by zero (2.3), unterminated
   `.REPT`/`.IRP` (2.1) and the RLD overflow (2.4).
3. Fix the silent wrong code: EMT/TRAP/MARK ranges (1.6), local-label truncation (2.5), and `.ASCII <n>`
   (3.1).
4. Add tests that compare listings and object dumps with expected output, so these stay fixed.
