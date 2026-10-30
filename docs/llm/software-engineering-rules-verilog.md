# Synthesizable Verilog-2001 Standards for Intel Cyclone V

## Conformance Notation
* ***must*** / ***must not***: Mandatory requirement / absolute prohibition.
* ***recommended***: Preferred practice.
* ***may***: Permitted optional action.
* ***can***: Inherent system capability.

---

## 1. File Structure & Directives
- Files ***must*** use `.v` (modules) or `.vh` (headers). SystemVerilog extensions (`.sv`, `.svh`) ***must not*** be used.
- Each `.v` file ***must*** contain exactly one module whose identifier matches the file basename.
- Top wrapper ***must*** be named `<design>_top.v`.
- Every file ***must*** begin with a concise comment header stating module purpose and theory of operation.
- Source files ***must*** declare `` `default_nettype none `` prior to `module` and restore with `` `default_nettype wire `` after `endmodule`.
- Header files ***must*** use include guards (` `ifndef GUARD_VH ` / ` `define GUARD_VH ` / ` `endif `).
- Intentional rule bypasses ***must*** be justified via `// lint_waive: RULE_NAME - Reason`.

## 2. Formatting & Syntax
- Indentation ***must*** be exactly 2 spaces. Hard tabs ***must not*** be used.
- Lines ***should*** fit within 100 columns. Continuations ***must*** indent by 4 spaces.
- Line endings ***must*** be LF (`\n`). Files ***must*** end with a newline.
- Trailing whitespace and duplicate semicolons (`;;`) ***must not*** be committed.
- `begin` ***must*** share the line with its trigger (`if (...) begin`, `always @* begin`). `end` ***must*** occupy its own line. Use `end else begin`.
- Preprocessor directives ***must*** be left-aligned at column 0.
- Operators ***must*** have surrounding whitespace. Control keywords ***must*** have space before parentheses.
- Function/task calls ***must not*** have whitespace before the argument parenthesis.
- Reduction operators preceded by other operators and nested ternary operators ***must*** be parenthesized.

## 3. Identifiers & Naming
- Identifiers for modules, nets, variables, ports, and functions ***must*** use `lower_snake_case`.
- Parameters and localparams ***must*** use `UpperCamelCase`.
- FSM states ***must*** use `localparam` with `kUpperCamelCase` naming (e.g., `kIdle`).
- Global macros ***must*** use `ALL_CAPS` with a group prefix (`GROUP__MACRO`). Local macros ***must*** start with an underscore (`_LOCAL`) and ***must*** be undefined with `` `undef `` at file end.
- Primary clock ***must*** be named `clk` (or `<domain>_clk`). Resets ***must*** be named `rst` (sync active-high) or `arst` (async active-high).
- Active-low hardware inputs ***must*** end in `_n` and ***must*** be inverted immediately at top-level (`wire rst = ~rst_n;`).
- Names ***must not*** end with `_<digit>` (e.g., `sig_1` is prohibited; use `sig_d1` or arrays).
- Signal qualifiers ***must*** follow ordering: semantic (`_bytes`, `_valid`) -> fixed-point (`_s8p8`) -> polarity (`_n`) -> stage/temporal (`_next`, `_d1`, `_le`).

## 4. Module Interfaces & Instantiation
- Port declarations ***must*** use Verilog-2001 ANSI style with explicit direction, type, signedness, and bounds `[MSB:0]`.
- Port order ***must*** place `clk` first, followed by `rst`/`arst`, flow control, data, and status.
- Input ports in module declarations ***must not*** specify default values.
- Module instantiations and parameter overrides ***must*** use explicit named binding (`.port(sig)`, `#(.Param(val))`). Positional mapping and `defparam` ***must not*** be used.
- Unused output ports ***must*** be bound as `.unused_out()`. Input ports ***must not*** be left floating; tie off to sized constants.
- Recursive instantiation ***must not*** be used.
- Generate blocks ***must*** name all `begin` blocks with a `gen_` prefix (`begin : gen_slices`).

## 5. Procedural Logic & FSMs
- Clocked sequential blocks ***must*** use non-blocking (`<=`) assignments exclusively.
- Combinational blocks ***must*** use `always @*` and blocking (`=`) assignments exclusively.
- Blocking and non-blocking assignments ***must not*** be mixed within the same procedural block.
- Signals ***must*** be driven by exactly one `always` block or continuous `assign`.
- Multiple non-blocking assignments to the same signal across non-exclusive `if` branches in the same cycle ***must not*** be used; chain conditions with `else if`.
- Combinational blocks ***must*** assign default values at the top of the block to prevent latch inference.
- `case` statements ***must*** include a `default:` branch.
- `casex` ***must not*** be used. `casez` ***may*** be used with `?` as the wildcard literal (`z`/`Z` ***must not*** be used).
- Synthesis pragmas (`full_case`, `parallel_case`) ***must not*** be used.
- FSMs ***must*** implement the two-process pattern: combinational block decodes `state_next` and outputs with a `default: state_next = 'bx;`; sequential block handles solely reset and `state <= state_next`.

## 6. Datatypes, Widths & Arithmetic
- Nets and continuous assigns ***must*** use `wire`. Procedural targets ***must*** use `reg`.
- Packed bit vectors ***must*** be little-endian `[MSB:LSB]` with `MSB >= LSB >= 0`.
- Unpacked memory arrays ***must*** be big-endian `[0:Depth-1]` with `0 <= left <= right`.
- Numeric literals ***must*** be sized explicitly (e.g., `8'd0`, `4'b0001`). Binary literals ***must*** write out all bits explicitly.
- Multi-bit vectors ***must not*** be tested directly in boolean contexts; explicit comparison ***must*** be used (`if (cnt != 4'd0)`).
- 1-bit boolean expressions ***must*** use logical operators (`&&`, `||`, `!`). Vector logic ***must*** use bitwise operators (`&`, `|`, `~`, `^`).
- Mixed signed/unsigned operations ***must*** cast unsigned operands with `$signed()`. Arithmetic shifts on signed vectors ***must*** use `>>>`.
- Synthesizable RTL ***must not*** assign `'bx` in operational logic (allowed only in `default:` case branches for X-propagation).
- Tasks ***must not*** appear in synthesizable modules. Combinational helpers ***must*** use `function automatic` with an explicit return width.

## 7. Cyclone V Architectural Invariants
- Logic-gated or logic-divided clocks (`wire clk_gated = clk & en`) ***must not*** be created. Clock control ***must*** use flip-flop clock enables (`if (clk_en)`).
- M10K block RAM inference requires synchronous reads (`always @(posedge clk) q <= mem[addr]`). Asynchronous reads (`assign q = mem[addr]`) ***must not*** be used on arrays intended for M10K.
- Core internal tri-state buses (`1'bz`) ***must not*** be used. Tri-state logic ***can*** exist only for bidirectional (`inout`) external pins in the top-level wrapper.
- DSP multiplier operands ***recommended*** to align with 9, 18, or 27 bits for native hardware mapping.
- Module outputs ***recommended*** to be registered.
- Clock domain crossings (CDC) ***must*** be isolated in dedicated synchronizer modules.
- The top-level wrapper (`*_top.v`) ***must*** contain only wiring, polarity inversions, and submodule instantiations. Application logic and sequential registers ***must not*** exist in the top wrapper.
