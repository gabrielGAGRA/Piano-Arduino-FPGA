# Synthesizable Verilog-2001 (IEEE Std 1364-2001) Standards for Intel Cyclone V FPGAs

## 1. File & Header Conventions

- **File Extensions**: Use `.v` for synthesizable modules; `.vh` for header files. SystemVerilog extensions (`.sv`, `.svh`) are prohibited.
- **Single Design Element per File**: Exactly one module per `.v` file. The module name must exactly match the file basename.
- **Top-Level & Test Naming**: Top-level chip wrapper must be named `<design>_top.v`. Unit testbenches must be named `<module>_test.v` (or `tb_<module>.v` / `<module>_tb.v`).
- **File Header Comment**: Every file must start with a descriptive header comment explaining what problem the module solves and an overview of its Funcionamento:
  ```verilog
  // Descrição: Single-clock FIFO buffer with synchronous status flags.
  // Funcionamento: Circular ring buffer using Cyclone V M10K block RAM.
  ```
- **Compiler Directives**: Always declare `` `default_nettype none `` at the top of every file before module declarations to prevent silent implicit net inference. Restore with `` `default_nettype wire `` after `endmodule`.
- **Header Files (`.vh`)**: Shared constants and macros across modules must reside in `.vh` files with standard include guards:
  ```verilog
  `ifndef PROJECT_DEFS_VH
  `define PROJECT_DEFS_VH

  `define CLK_FREQ_HZ 50000000

  `endif // PROJECT_DEFS_VH
  ```
- **Linter Waivers**: When an intentional exception is required, justify it with an inline comment waiver:
  ```verilog
  // lint_waive: RULE_NAME - Reason why exception is strictly necessary
  ```

---

## 2. Aesthetics & Formatting

- **Indentation**: Exactly 2 spaces per indentation level. Do NOT use tabs. Configure editors to insert spaces.
- **Line Length**: Wrap code at 100 characters per line.
- **Line Wrapping**: Indent wrapped expression continuations by 4 spaces (or align with the opening parenthesis/bracket).
- **Line Endings & Character Set**: ASCII characters only, with POSIX/UNIX-style line endings (`\n`). Every non-empty file must end with a newline.
- **Trailing Spaces & Redundant Semicolons**: Delete trailing whitespace at the ends of lines. Do not use consecutive semicolons (`;;`).
- **`begin` and `end` (Eschatology)**:
  - `begin` must be on the same line as the preceding keyword (`if (...) begin`, `always @* begin`).
  - `end` must be on its own line.
  - `end else begin` must be kept on a single line.
  - For single-statement blocks, `begin` and `end` may be omitted only if the entire statement fits on a single line.
- **Preprocessor Directives**: Keep branching preprocessor directives (`` `ifdef ``, `` `ifndef ``, `` `else ``, `` `elsif ``, `` `endif ``) left-aligned at column 0.
- **Spacing**:
  - Space around keywords: include whitespace before and after keywords (`if (cond)`, `for (...)`, `case (sel)`).
  - Space around binary operators: include whitespace on both sides of all binary operators (`+`, `-`, `*`, `==`, `&&`, etc.).
  - No space between function/task/macro name and opening parenthesis: `my_func(arg)`.
  - Case items: no space before colon, at least one space after colon (`kIdle: begin`).
- **Parentheses**:
  - Use parentheses around reduction operators when preceded by another operator: `~(&foo)`.
  - Nested ternary expressions must be enclosed in parentheses: `sel_a ? val_a : (sel_b ? val_b : val_c)`.

---

## 3. Naming Conventions

### Summary Table

| Construct | Style | Example |
|---|---|---|
| Modules, nets, variables, ports, functions, tasks | `lower_snake_case` | `rx_data_valid`, `baud_counter` |
| Primary chip I/O pads (top-level wrapper) | `UPPER_SNAKE_CASE` or `lower_snake_case` | `HEX0`, `LEDR`, `key_n` |
| Module tunable `parameter` & internal `localparam` | `UpperCamelCase` | `DataWidth`, `MaxCycles` |
| FSM state constants (`localparam [W-1:0]`) | `kUpperCamelCase` | `kIdle`, `kWaitAck`, `kTransmit` |
| Global `` `define `` macros | `ALL_CAPS` with `<GROUP>__` prefix | `SOC__MAX_CHANNELS` |
| Local `` `define `` macros (within single file) | `_ALL_CAPS` with mandatory `` `undef `` | `_LOCAL_TIMEOUT` |
| Module instances | `<module_name>` or `<module_name>_<suffix>` | `fifo_buffer fifo_rx`, `counter counter_0` |

### Clocks & Resets
- Clock port must be named `clk`.
- Active-high synchronous reset must be named `rst`.
- Active-high asynchronous reset must be named `arst`.
- For modules with multiple clock domains, prefix signals with the clock domain mnemonic: `dram_clk`, `dram_rst`, `dram_data`.
- Physical active-low board inputs must end in `_n` (`rst_n`, `key_n`) and must be inverted at top-level:
  ```verilog
  wire rst = ~rst_n;
  ```

### Register & Signal Suffixes
- **Register Output vs Input**: Register output uses `<name>`; combinational next-state D-input uses `<name>_next`.
- **Register Controls**: Load enable uses `_le`; counter increment uses `_inc`; synchronous clear uses `_clear`.
- **Delayed Signals**: Clock-cycle delayed copies use `_d` (1 cycle), `_d2` (2 cycles), etc.
- **Pipeline Stages**: Multi-stage pipelines use prefixes `p1_`, `p2_`, `p3_` to group signals belonging to the same stage.
- **Flow Control**:
  - Ready/Valid: `_valid`, `_valid_next`, `_ready`.
  - Req/Ack: `_req`, `_ack`.
- **Polarity & Numbers**: Active-low uses `_n`; differential pairs use `_p` / `_n`. Fixed-point signals use `_sMpN` (signed) or `_uMpN` (unsigned).
- **Units**: Always include physical units as suffixes where applicable (`_bytes`, `_cycles`, `_hz`, `_ns`).
- **Suffix Ordering**: Order multiple suffixes from semantic to temporal:
  1. Semantic / units (`_bytes`, `_valid`, `_ready`)
  2. Fixed-point format (`_s8p8`)
  3. Active-low polarity (`_n`)
  4. Differential polarity (`_p`, `_n`)
  5. Stage / Delay / Register qualifier (`_next`, `_le`, `_inc`, `_clear`, `_d`, `_d2`)
- **Prohibited Suffix**: NEVER end a signal name with an underscore followed by numbers (`foo_1`, `foo_2`). Synthesis tools map flattened buses using this convention, which leads to naming confusion. Use `foo_d1`, `foo_ch1`, or indexed arrays.

---

## 4. Module Boundaries, Instantiations & Generate

- **Port Header Style**: Verilog-2001 ANSI port style only. Declare direction, type, signedness, width `[MSB:0]`, and name. The closing parenthesis of the port list must be on its own line in column 0.
- **Port Ordering**: Clocks first (`clk`), followed by resets (`rst`, `arst`), then flow control, data, and status ports.
- **No Default Port Values**: Input ports in module headers must NOT specify default values (`input wire foo = 1'b0` is prohibited).
  ```verilog
  module debounce #(
    parameter DebounceCycles = 50000
  )(
    input  wire        clk,
    input  wire        rst,
    input  wire        button_in,
    output reg         button_out,
    output wire        pulse_out
  );
  ```
- **Named Instantiations**: Named port binding only (`.clk(clk), .rst(rst)`). Positional port mapping is strictly forbidden.
- **Named Parameter Overrides**: Always override parameters by name: `counter #(.Width(8)) counter_0 (...)`. Positional parameter overrides and `defparam` are prohibited.
- **Unconnected Ports**: Unused output ports must be explicitly written as empty bindings: `.unused_out()`. Input ports must NEVER be left floating—tie off explicitly to sized constants (`.unused_in(1'b0)`).
- **No Recursive Instantiation**: Modules must not instantiate themselves.
- **Generate Blocks**: Always explicitly label generate construct `begin` blocks with a `gen_` prefix:
  ```verilog
  genvar i;
  generate
    for (i = 0; i < Width; i = i + 1) begin : gen_bit_slices
      // Slice implementation
    end
  endgenerate
  ```

---

## 5. Procedural Assignments, Latches, & FSMs

- **Sequential (`always @(posedge clk ...)` )**: Use non-blocking (`<=`) assignments exclusively. NEVER use blocking (`=`) in sequential blocks.
- **Combinational (`always @*`)**: Use blocking (`=`) assignments exclusively. NEVER use non-blocking (`<=`) in combinational blocks.
- **NEVER Mix Assignment Types**: Never mix `=` and `<=` within the same procedural block.
- **Single Driver**: A signal must be driven by exactly one `always` block or a single continuous `assign`.
- **Single NBA per Condition**: In sequential blocks, avoid multiple non-blocking assignments to the same signal in separate `if` conditions that can both be true in the same cycle. Chain mutually exclusive conditions with `else if`.
- **Latch Prevention**: In `always @*`, define default values for all outputs at the very top of the block before any conditional logic, OR explicitly assign them in every branch of `if`/`else` and `case`.
- **Exhaustive `case` & Wildcards**:
  - Always provide a `default:` branch in `case` statements.
  - Ban `casex`. Use `casez` when wildcard matching is required, and use `?` (never `z`/`Z`) for wildcard bits.
  - Synthesis pragmas (`// synopsys full_case parallel_case`) are strictly PROHIBITED.
- **Finite State Machines (Two-Process Pattern)**:
  1. Define states as `localparam [Width-1:0]` in `kUpperCamelCase`, with idle state named `kIdle`.
  2. Combinational block decodes state: assign defaults at the top (`state_next = state;`), decode with `case (state)` where each case item has a descriptive comment, and assign `'bx` in `default:` for X-propagation in simulation.
  3. Sequential block contains ONLY reset and state latching:
  ```verilog
  localparam [1:0]
    kIdle  = 2'd0,
    kRead  = 2'd1,
    kWrite = 2'd2;

  reg [1:0] state;
  reg [1:0] state_next;

  // Combinational next-state decode
  always @* begin
    state_next = state;
    ready = 1'b0;

    case (state)
      // Wait for incoming transaction request
      kIdle: begin
        ready = 1'b1;
        if (req) begin
          state_next = kRead;
        end
      end

      // Fetch memory word
      kRead: begin
        state_next = kWrite;
      end

      // Commit output
      kWrite: begin
        state_next = kIdle;
      end

      default: begin
        state_next = 2'bxx;
        ready = 1'bx;
      end
    endcase
  end

  // Sequential state register
  always @(posedge clk or posedge arst) begin
    if (arst) begin
      state <= kIdle;
    end else begin
      state <= state_next;
    end
  end
  ```

---

## 6. Types, Widths, & Arithmetic

- **Data Types**: Use `wire` for nets, continuous assignments, and submodule port interconnects. Use `reg` strictly for procedural targets in `always` blocks.
- **Array Endianness & Ordering**:
  - Packed bit vectors and registers MUST be little-endian `[MSB:LSB]` with `MSB >= LSB >= 0` (e.g. `reg [7:0] data`).
  - Unpacked memory arrays MUST be big-endian `[0:Depth-1]` with `0 <= left <= right` (e.g. `reg [7:0] ram [0:1023]`).
- **Explicit Width Sizing**:
  - Number literals MUST be explicitly sized (e.g., `8'd42`, `1'b0`, `{Width{1'b0}}`).
  - Binary literals MUST explicitly specify all digits: `4'b0001` (never `4'b1`).
  - Exception: Literal `1` or `0` in parameterized addition/subtraction (`data + 1`) or integer loop indices.
- **No Multi-Bit Signals in Boolean Context**: Compare multi-bit signals to zero explicitly: `if (counter != 4'd0)` instead of `if (counter)`.
- **Logical vs Bitwise**: Use logical operators (`&&`, `||`, `!`) for 1-bit boolean expressions; use bitwise operators (`&`, `|`, `~`, `^`) for vector logic.
- **Signed Arithmetic**:
  - Unsigned operands must be cast with `$signed()` when mixed with signed operands.
  - When shifting signed values arithmetically, always use `>>>` instead of `>>`.
- **Don't-Care (`X`) Assignments**: Do not assign explicit `'bx` in synthesizable RTL to specify don't-care logic, as this causes simulation-synthesis differences. (Assigning `X` in `default:` case items to catch illegal simulation states is permitted).
- **Functions & Tasks**:
  - Tasks are prohibited in synthesizable RTL (use submodules instead; tasks are allowed in testbenches).
  - Combinational helper functions must be declared `function automatic` with an explicit return range and single output.

---

## 7. FPGA Architecture: Clocks, Resets, & Cyclone V Hardware Invariants

- **Dedicated Clock Networks (GCLK)**: Never generate gated or divided clocks using logic gates (`wire clk_gated = clk & en`). Clock muxing must use dedicated ALTCLKCTRL primitives or synchronous register enables.
- **Clock Enables**: Implement clock gating using flip-flop clock enables:
  ```verilog
  always @(posedge clk or posedge arst) begin
    if (arst) begin
      q <= {Width{1'b0}};
    end else if (clk_en) begin
      q <= d;
    end
  end
  ```
- **M10K Block Memory Inference**:
  - Quartus Prime infers Cyclone V M10K blocks (10,240 bits) ONLY when reads are synchronous (`always @(posedge clk) q <= mem[addr]`). Asynchronous reads (`assign q = mem[addr]`) cannot map to M10K blocks and will exhaust FPGA ALM logic.
  - Memory initialization: Use `initial $readmemh("file.hex", ram);` or `$readmemb`.
- **Internal Tri-States Prohibited**: Cyclone V FPGA core fabric contains no internal tri-state buses (`1'bz`). Core multiplexing must use logic multiplexers. Tri-states are permitted ONLY on top-level bidirectional physical I/O pins (`inout`) in chip wrappers (`*_top.v`).
- **Cyclone V DSP Blocks**: Keep multiplier widths aligned to 9, 18, or 27 bits for optimal mapping to Cyclone V Variable Precision DSP Blocks.
- **Registered Module Outputs**: Strongly prefer registering all module outputs. If the outputs of a non-trivial module are combinational, document this explicitly in the module header comment.
- **Clock Domain Crossing (CDC)**: Any module spanning multiple clock domains must encapsulate CDC synchronization into dedicated submodules. Never mix CDC logic and application logic at the same hierarchical level.
- **Pure Top-Level Wrapper**: Top-level `<design>_top.v` modules must contain only submodule instantiations and physical pad connections (inverting active-low buttons or managing physical `inout` tri-state buffers). No internal application logic or sequential registers in the top-level instance.
