
# Google Verilog Style Guide

<a id="basics"></a>

## Basics

<a id="basics-summary"></a>

### Summary

This guide defines a Google style for Verilog. The goals are to:

*   promote consistency across hardware development projects
*   promote best practices
*   increase code sharing and reuse

This style guide defines style for SystemVerilog compliant code. Additionally,
this style guide defines style for both synthesizable and testbench code.

<a id="terminology-conventions"></a>

### Terminology Conventions

Unless otherwise noted, the following terminology conventions apply to this
style guide:

*   The word ***must*** indicates a mandatory requirement. Similarly, ***do
    not*** indicates a prohibition. Imperative and declarative statements
    correspond to ***must***.
*   The word ***recommended*** indicates that a certain course of action is
    preferred or is most suitable. Similarly, ***not recommended*** indicates
    that a course of action is unsuitable, but not prohibited. There may be
    reasons to use other options, but the implications and reasons for doing so
    must be fully understood.
*   The word ***may*** indicates a course of action is permitted and optional.
*   The word ***can*** indicates a course of action is possible given material,
    physical, or causal constraints.

<a id="style-linter"></a>

### Style Linter

The following Style Linter tools can be used to automatically check the code for
violations to the mandatory requirements of this Style Guide:

*   [Verible Verilog Style Linter](https://github.com/chipsalliance/verible/tree/master/verible/verilog/tools/lint)

<a id="style-guide-exceptions"></a>

### Style Guide Exceptions

<span class="Summary">Justify all exceptions with a comment.</span>

No style guide is perfect. There are times when the best path to a working
design, or for working around a tool issue, is to simply cut the Gordian Knot
and create code that is at variance with this style guide. It is always okay to
deviate from the style guide by necessity, as long as that necessity is clearly
justified by a brief comment, as well as a [Style Linter](#style-linter) waiver
pragma where appropriate.

<a id="inclusive-language"></a>

### Which Verilog to Use

<span class="Summary">Prefer SystemVerilog-2017.</span>

All RTL and tests must be developed in SystemVerilog, following the
[SystemVerilog-2017 standard].

[SystemVerilog-2017 standard]: https://ieeexplore.ieee.org/document/8299595

### Summary

This section covers file conventions, mostly how files are to be
[named](#file-names).

<a id="file-extensions"></a>

### File Extensions

<span class="Summary">Use `.sv` and `.svh` file extensions for SystemVerilog
files.</span>

File extensions have the following meanings:

*   `.sv` indicates a SystemVerilog file defining a module or package.
*   `.svh` indicates a SystemVerilog [global macro file](#global-macro-files) or
    [include file](#include-files).
*   `.v` indicates a Verilog-2001 file defining a module or package.
*   `.vh` indicates a Verilog-2001 [global macro file](#global-macro-files) or
    [include file](#include-files).

<a id="file-names"></a>

### File Names

<span class="Summary">File names must match the design element name and indicate
the Verilog dialect.</span>

If a source file declares a design element, the file name must begin with the
name of that design element. For example, a file declaring a module named
`interconnect` must be named `interconnect.sv`.

Declare only one design element per file. As per IEEE 1800-2017 section 3.2, a
design element may be either a module, package, program, interface, checker,
primitive, or configuration.

For variants of a design element, it is permissible to insert dot-delimited
strings between the design element name and the file extension to indicate the
particular variant contained in that file. For example, a file containing a
gate-level model of an interconnect module might be named
`interconnect.gate.sv`.

<a id="standard-files"></a>

### Standard Design Files

<span class="Summary">The following filenames are special: `[design]_top.sv`,
`[design]_pkg.sv`. </span>

Each design must have two standard files, `[design]_top.sv` and
`[design]_pkg.sv`, where `[design]` is the unique name of the design.

*   `[design]_top.sv` is the top-level module of the design.
*   `[design]_pkg.sv` defines a package named `[design]_pkg` containing
    declarations related to the design.

A "design" here is one of the following hierarchical elements: project top,
cluster (a collection of design blocks) or a design block.

A "design block" is the fundamental architecture or microarchitecture building
block of the design. Every design block has its black box behavior fully
specified. In particular, a design block’s interfaces are fully specified in the
documentation (both the port list and the behavior of every port).

<a id="file-structure"></a>

### File Structure

<span class="Summary">The overall structure of a SystemVerilog file must start
with the [header](#header), followed by the declaration and then the
implementation.</span>

<a id="header"></a>

#### Header Comment

<span class="Summary">Every file must start with a header comment.</span>

A header comment contains a short description of the design element, explaining
what problem it solves. Additional text must give an overview of any non-obvious
parts of the theory of operation of this particular implementation.

<a id="basic-template"></a>

### Basic Template

<span class="Summary">A template that demonstrates many of the items detailed
throughout the style guide.</span>

Template:

<a id="generated-code"></a>

### Generated Code

<span class="Summary">Generated code must be accompanied by all necessary input
files and scripts necessary to automatically reproduce the generated
output.</span>

Generators include Verilog preprocessors and programs that create Verilog from
other sources like Haskell, Chisel, C or C++.

Code generation tools that operate in-place on Verilog files must not strip out
the generating macros, and must preserve those recipes within the file (in other
words, as comments). Code generators that operate in this fashion must be
idempotent and repeatable.

Comments wrapped in `/**` and `**/` comment lines are reserved for use by
generators.

Generated code must meet the style guidelines.

<a id="formatting"></a>

## Aesthetics and Formatting

<a id="formatting-summary"></a>

### Summary

The Aesthetics and Formatting section addresses purely aesthetic aspects of
style, primarily:

-   [Wrap lines at 100 characters](#line-length).
-   [Indentation is two spaces per level](#indentation), [no tabs](#tabs).
-   [Space-delimit all keywords and binary operators](#spacing).
-   [Prefer `// Comment` style comments](#comments).

<a id="general-file-appearance"></a>

### General File Appearance

<a id="characters"></a>

#### Characters

<span class="Summary">Use only ASCII characters with UNIX-style line
endings("\\n").</span>

<a id="posix-file-endings"></a>

#### POSIX File Endings

<span class="Summary">All lines on non-empty files must end with a newline
("\\n").</span>

The
[POSIX standard](http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_206)
mandates that lines end with a newline character. This includes the final line
in every file.

<a id="line-length"></a>

#### Line Length

<span class="Summary">Wrap the code at 100 characters per line.</span>

The maximum line length for style-compliant Verilog code is 100 characters per
line.

Exceptions:

-   Any place where line wraps are impossible (for example, an include path
    might extend past 100 characters).

[Line-wrapping](#line-wrapping) contains additional guidelines on how to wrap
long lines.

<a id="tabs"></a>

#### No Tabs

<span class="Summary">Do not use tabs anywhere.</span>

Use spaces to indent or align text. See [Indentation](#indentation) for rules
about indentation and wrapping.

To convert tabs to spaces on any file, you can use the
[UNIX `expand`](http://linux.die.net/man/1/expand) utility.

<a id="trailing-spaces"></a>

#### No Trailing Spaces

<span class="Summary">Delete trailing whitespace at the end of lines.</span>

<a id="redundant-semicolons"></a>

#### No Redundant Semicolons

<span class="Summary">Delete redundant semicolons.</span>

Semicolons may represent null statements or items in SystemVerilog. One is
enough; consecutive semicolons (`;;`) are likely typos.

<a id="eschatology"></a>

### Eschatology

<span class="Summary">Use `begin` and `end` unless the whole statement fits on a
single line.</span>

If a whole semicolon-terminated statement fits on a single line, `begin` and
`end` may be omitted, otherwise enclose it in `begin` and `end`.

Assume that any macro call could expand to multiple statements, and enclose them
in `begin` and `end` where necessary (for example, inside conditional and loop
blocks).

`begin` must be on the same line as the preceding keyword, and ends the line.
`end` must start a new line. `end else begin` must be together on one line. The
only exception is if `end` has a label, a following `else` must be on a new
line.

For single-statement blocks, `begin` and `end` may be omitted if the statement
fits on a single line. Both styles (including or omitting `begin` and `end`) are
acceptable.

The preceding style also applies to individual case items within a case
statement. `begin` and `end` may be omitted if the entire case item (the case
expression and the associated statement) fits on a single line. Otherwise, use
the `begin` keyword on the same line as the case expression.

<a id="indentation"></a>

### Indentation

<span class="Summary">Indentation is two spaces per level.</span>

Indentation is two spaces per level, no tabs. (Configure your editor to emit
spaces when you hit the tab key.)

<a id="indented-sections"></a>

#### Indented Sections

Always add an additional level of indentation to the enclosed sections of all
paired keywords. Examples of SystemVerilog keyword pairs:

-   `begin` and `end`
-   `module` and `endmodule`
-   `package` and `endpackage`
-   `class` and `endclass`
-   `function` and `endfunction`
-   and similar.

Indent all members of struct, union, and enum declarations by two spaces.

<a id="line-wrapping"></a>

#### Line Wrapping

When wrapping a long expression, indent the continued part of the expression by
four spaces, like this:

Or, if it improves readability, align the continued part of the expression with
a grouping open parenthesis or brace. Similarly, an expression containing a
nested struct may be aligned with the first structure member name. In the
absence of other considerations, use the minimum number of lines.

Operators in a wrapped expression can be placed at either the end or the
beginning of each line, but this must be done consistently within a file.

<a id="preprocessor-indentation"></a>

#### Preprocessor Directives

<span class="Summary">Keep branching preprocessor directives left-aligned and
un-indented.</span>

Keep branching preprocessor directives (`` `ifdef ``, `` `ifndef ``, `` `else ``,
`` `elsif ``, `` `endif ``) aligned to the left, even if they are nested. Indent
the conditional branches of text as if the preprocessor directives were absent.
Non-branching preprocessor directives must follow the same indentation rules as
the regular code.

Un-indented branching preprocessor directives disrupt the flow of reading to
emphasize that there is conditional text. Leaving conditional branch text
un-indented will result in post-preprocessed text looking properly indented.

<a id="spacing"></a>

### Spacing

<a id="space-around-keywords"></a>

#### Space Around Keywords

<span class="Summary">Include whitespace before and after SystemVerilog
keywords.</span>

Keywords must be delimited by whitespace, even if not syntactically required.

Do not include a whitespace:

-   before keywords that immediately follow a group opening, such as an open
    parenthesis.
-   before a keyword at the beginning of a line.
-   after a keyword at the end of a line.

For example:

<a id="expressions"></a>

#### Space Around Binary Operators

<span class="Summary">Include whitespace on both sides of all binary operators.
</span>

Use spaces around all binary operators. Add sufficient whitespace to aid
readability.

For example:

**Exception:** When declaring a bit vector or indexing or slicing an array, it
is acceptable to use the compact notation for simple expressions. For example:

For more complex expressions in array indices, space-delimit all binary
operators.

When splitting alternation expressions into multiple lines, use a format that is
similar to an equivalent if-then-else line. For example:

<a id="comma-spacing"></a>

#### Comma-delimited Lists

<span class="Summary">For multiple items on a line, one space must separate the
comma and the next character.</span>

Additional whitespace is allowed for readability.

<a id="tabular-alignment"></a>

#### Tabular Alignment

<span class="Summary">Adding whitespace to align related items is
recommended.</span>

Where it is reasonable to do so, align a group of two or more similar lines so
that the identical parts are directly above one another. This alignment makes it
easy to see which characters are the same and which characters are different
between lines.

[Use spaces, not tabs](#indentation).

For example:

<a id="dimension-spacing"></a>

#### Array Dimensions in Declarations

Add a space around packed dimensions.

Do not add a space:

-   between identifier and unpacked dimensions.
-   between multiple dimensions.

Applies to packed and unpacked arrays as well as dynamic arrays, associative
arrays, and queues.

<a id="parameterized-type-spacing"></a>

#### Parameterized Types

<span class="Summary">Add one space before type parameters, except when the type
is part of a qualified name.</span>

A qualified name contains at least one scope `::` operator connecting its
segments. A space in a qualified name would break the continuity of a reference
to one symbol, so it must not be added. Parameter lists must follow the
[space-after-comma](#comma-spacing) rule.

<a id="label-spacing"></a>

#### Labels

<span class="Summary">Code block labels have one space before and after the
colon. Statement labels have no space before the colon and one space after the
colon.</span>

For example:

<a id="case-item-spacing"></a>

#### Case items

There must be no whitespace before a case item's colon; there must be at least
one space after the case item's colon.

The `default` case item must include a colon.

For example:

<a id="module-header-spacing"></a>

#### Module Header Spacing

<span class="Summary">Module header definitions have spaces after the module
name and between any parameter lists and port lists.</span>

For example:

<a id="module-instantiation-spacing"></a>

#### Module Instantiation Spacing

<span class="Summary">Module instances have spaces after the instance name and
between any parameter lists and port lists.</span>

For example:

<a id="function-task-call-spacing"></a>

#### Function And Task Calls

<span class="Summary">Function and task calls must not have any spaces between
the function name or task name and the open parenthesis.</span>

For example:

<a id="macro-call-spacing"></a>

#### Macro Calls

<span class="Summary">Macro calls must not have any spaces between the macro
name and the open parenthesis.</span>

For example:

<a id="line-continuation"></a>

#### Line Continuation

<span class="Summary">It is recommended to right-align line continuations.
</span>

Aligning line continuations ('`\ `' character) helps visually mark the end of a
multi-line macro. The position of alignment only needs to be beyond the
rightmost extent of a multi-line macro by at least one space, when a space does
not split a token, but must not exceed the maximum line length.

<a id="parentheses"></a>

### Parentheses

<span class="Summary">Use parentheses to make operations unambiguous.</span>

In any instance where a reasonable human would need to expend thought or refer
to an operator precedence chart, use parentheses instead to make the order of
operations unambiguous.

<a id="reduction-operator"></a>

#### Reduction Operator

<span class="Summary">Parentheses are required to isolate any reduction
operation when immediately preceded by any other operator.</span>

<a id="ternary-expressions"></a>

#### Ternary Expressions

<span class="Summary">Nested ternary expressions must be enclosed in
parentheses.</span>

For example:

While the following nested ternary has only one meaning to the compiler, the
meaning can be unclear and error-prone to humans:

<a id="comments"></a>

### Comments

<span class="Summary">C++ style comments (`// foo`) are strongly recommended for
single and multi-line comments. The `/**` token is reserved for use with
generators.</span>

A standalone comment above a block of code explains that code. An inline comment
explains the code that is on the same line as the comment.

For example:

Comments that start with `/**` are reserved for use by generator directives.

<a id="spelling"></a>

#### Punctuation, Spelling, and Grammar

<span class="Summary">Maintain consistent and correct
[punctuation, spelling, and grammar](https://google.github.io/styleguide/cppguide.html#Punctuation,_Spelling_and_Grammar)
within comments.</span>

Pay attention to punctuation, spelling, and grammar; it is easier to read
well-written comments than badly written ones.

Comments must be as readable as narrative text, with proper capitalization and
punctuation. In many cases, complete sentences are more readable than sentence
fragments. Shorter comments, such as comments at the end of a line of code, can
sometimes be less formal as long as the style remains consistent.

Although it can be frustrating to have a code reviewer point out that you are
using a comma instead of a semicolon, it is very important that source code
maintain a high level of clarity and readability. Proper punctuation, spelling,
and grammar help with that goal.

<a id="dead-code"></a>

<a id="naming-conventions"></a>

## Naming Conventions

### Naming Overview

<span class="Summary">All identifiers are styled `lower_snake_case` unless
otherwise specified in the following table.</span>

> "There are only two hard things in Computer Science: cache invalidation and
> naming things." -- Phil Karlton

All identifiers are styled `lower_snake_case`, except for the constructs
summarized in the following table:

Construct                                                                                          | Style
-------------------------------------------------------------------------------------------------- | -----
[`` `define `` macros](#defines)                                                                   | `ALL_CAPS`
[Tunable parameters for parameterized modules, classes, and interfaces](#naming-module-parameters) | `UpperCamelCase`
[Constants](#naming-constants)                                                                     | `UpperCamelCase`
[Type `parameter`](#naming-module-parameters)                                                      | `lower_snake_case_t`
[Struct and union types](#structs-unions)                                                          | `lower_snake_case_t`
[Constraints](#constraints)                                                                        | `lower_snake_case_c`
Interface declarations                                                                             | `lower_snake_case_if`
[Enumeration types](#enumerations)                                                                 | `lower_snake_case_t` or `lower_snake_case_e`
[Enumerated value names](#enumerations)                                                            | `kUpperCamelCase`
[Chip primary IOs](#signal-naming)                                                                 | `UPPER_SNAKE_CASE` or `lower_snake_case`

Everything else, including
[declarations (module, class, package)](#module-names),
[instance names](#module-instance-names),
[signals (nets and ports)](#signal-naming), [genvars](#generate-constructs),
[labels](#label-spacing), functions, tasks, and other variables, must be named
consistent with the `lower_snake_case` convention.

External library identifiers and their overrides in the user code that violate
the preceding naming conventions are permitted. Example: UVM's
`convert2string()` can be used without renaming.

When an identifier is styled as `UpperCamelCase`, it is permissible to separate
numeric values with an underscore. For example, `IndexedThing_5_12`.

Further, there are a number of naming conventions for signals, constants, and
ports that are documented in more detail in the following sections.

<a id="signal-descriptive"></a>

<a id="descriptive-names"></a>

### Use Descriptive Names

Names must describe what an element's purpose is. Optimize for readability using
names that would be clear even to people on a different team.

Use names that describe the purpose or intent of the object. Do not worry about
saving horizontal space as it is far more important to make your code
immediately understandable by a new reader. Minimize the use of abbreviations
that would likely be unknown to someone outside your project (especially
acronyms and initialisms). Do not abbreviate by deleting letters within a word.
As a rule of thumb, an abbreviation is probably OK if it's listed in Wikipedia.
If additional abbreviations must be used, make sure your project has a glossary
of acceptable abbreviations.

Descriptiveness is recommended to be proportional to the name's scope of
visibility. For example, `n` may be a fine name within a 5-line function, but
within the scope of a 1000-line module, it's likely too vague.

When adding a comment to a signal declaration, consider whether an improved
signal name would be more appropriate.

Don't reuse variables for convenience. Instead create a new variable with a
unique, descriptive name.

<a id="binary-parameters"></a>

### Prefer Positive Enablement

<span class="Summary">Signals, ports, and parameters must be named
positively.</span>

All boolean signals are assumed to be active-high, unless explicitly named with
a `_n` suffix to indicate that the [signal is active-low](#active-low-signals).
Active-low signals are not recommended.

When naming boolean parameters, prefer positive enablement names ("Foo" or
"EnableFoo") over disablement ("DisableFoo").

<a id="ports"></a>

### Hierarchical consistency

<span class="Summary">The same signal must have the same name at any level of
the hierarchy.</span>

A signal that connects to a port of an instance must have the same name as that
port. By proceeding in this manner, signals that are directly connected must
maintain the same name at any level of hierarchy.

Exceptions to this convention are expected, such as:

*   When connecting a port to an element of an array of signals.

*   When mapping a generic port name to something more specific to the design.
    For example, two generic blocks, one with a `requester_bus` port and one
    with a `completer_bus` port might be connected by a `foo_bar_bus` signal.

In each exceptional case, care must be taken to make the mapping of port names
to signal names as unambiguous and consistent as possible.

A corollary of this principle is that signal names must change when that
signal's meaning changes. For example, if a `write_address` signal means "byte
index" at one level of hierarchy but "word index" within a sub-module, those
signals must have different names to indicate their differences (for example,
`write_byte_address` and `write_word_address`).

<a id="clocks"></a>

<a id="clock-and-reset-names"></a>

### Clock and Reset

<span class="Summary">These signals must be named `clk`, `rst`, and `arst`.
</span>

Clocks and resets must follow the following naming rules:

*   Clock is named `clk`.
*   Synchronous reset is named `rst` and is active high.
*   Asynchronous reset is named `arst` and is active high.

These names may optionally be prefixed to specify more specific use. Most
commonly, these signals will be prefixed with a mnemonic indicating a clock
domain, as required by the [Clock Domain Prefixes](#clock-domains) section.

For example:

### Avoid signal names that end with underscore-number

Signal names must never end with an underscore followed by a number (for
example, `foo_1`, `foo_2`, etc.). Many synthesis tools map buses into nets using
that naming convention, so similarly named nets can lead to confusion when
examining a synthesized netlist.

### Avoid reserved keywords as signal names

Reserved Verilog or SystemVerilog keywords may never be used as names (see
Tables 22.1-22.6 of [SystemVerilog-2017 standard] for the full list of reserved
keywords).

When interoperating with different languages, be mindful not to use keywords
from other languages.

<a id="signal-prefixes"></a>

### Prefixes

Use common prefixes to identify groups of signals that operate together. For
example, all elements of an AXI-S interface would share a prefix: `foo_valid`,
`foo_ready`, and `foo_data`.

Additionally, prefixes must be used to clearly label which signal is in which
clock group for any module with multiple clocks. See the section on
[clock domains](#clock-domains) for more details.

Examples:

-   Signals associated with controlling a blockram might share a `bram_` prefix.
-   Signals that are synchronous with `dram_clk` rather than `clk` must share a
    `dram_` prefix.

Code example:

This naming convention makes it easier to map port names onto similar signal
names using simple and consistent rules. See the section on
[Hierarchical Consistency](#ports) for more information.

<a id="clock-domains"></a>

#### Clock Domain Prefixes

<span class="Summary">If a module contains multiple clocks, all signals must be
prefixed by a clock domain mnemonic.</span>

Generally, it is recommended to structure modules so that most modules only have
a single clock domain (fully synchronous). For modules that must span multiple
clock domains, it is required that every port and signal within the module be
labelled with a prefix that uniquely associates each signal with a clock domain.
This prefix must be the same prefix used in the naming of the associated clock.

Even asynchronous resets must be de-asserted synchronously with a specific clock
domain, and so must be named accordingly.

For example:

<a id="src-dest-prefix"></a>

#### Source-Destination Prefixes

It is sometimes useful to document the expected connectivity between modules in
the signal name. The convention for indicating this connectivity is
`<src>_<dest>__`, where `<src>` and `<dest>` are convenient abbreviations for
the endpoints of the communication (at least, from a top-level perspective). The
endpoint abbreviation must specify a specific instance, or a reasonable generic
name if the specific instance is not known.

The `<src>` endpoint must always be the *producer* or *requester* of a given
*communication* (which can either be an individual flow-controlled channel or a
protocol-level group of individual flow-controlled channels). `<dest>` must
always be the *consumer* or *completer* of the communication. A communication
direction is not necessarily the same as each signal's direction. In this
manner, a set of related signals that work together to form a distinct
communication between modules always have the same naming prefix. The scope of
the communication (in other words, channel or group of channels) must be
explicitly documented using comments so that there is no naming ambiguity.

Source-destination prefixes are never mandatory, and must only be used at levels
of hierarchy where they clarify the intent of the design. When stripping this
prefix from a signal name at a hierarchical boundary, the right-hand side of the
`__` separator must remain unchanged.

An example:

<a id="pipelines"></a>

#### Pipeline Stage Prefixes

<span class="Summary">Clearly label your pipeline stage variables.</span>

When implementing a multi-stage pipeline, label your variables so that it is
clear which pipeline stage each variable is associated with. For example, a
three stage pipeline might use the prefixes `p1_`, `p2_`, and `p3_` to indicate
which signal is associated with which stage.

Clearly labelling which pipeline stage a signal is associated with helps to
detect and avoid bugs where signals that are valid in one pipeline stage are
accidentally used in a different pipeline stage.

Example:

NOTE: This guide makes a distinction between *delayed signals* and *pipelines*.
A *delayed signal* is a stand-alone signal that is delayed by a number of
cycles. A *pipeline* is a collection of signals across a number of cycles, as in
the preceding example. In this example, the valid signal is a delayed version of
the original in_valid signal, but the other signals are not delayed signals. The
pipelining naming convention emphasizes the grouping of signals in the same
stage, not their relative delays from their origin. The use of prefixes for
pipeline stages and suffixes for delayed signals makes the distinction clear.
See [Delayed Signal Suffix](#delayed-signal) for details.

<a id="signal-suffixes"></a>

### Suffixes

There are some standard suffixes for signals that have special meanings. Signals
must only end with these suffixes when the standard meanings are intended.

Some common conventions for suffixes are summarized here:

*   [Specify units](#signal-units) as a suffix where possible.
*   The `_n` suffix indicates an [active-low signal](#active-low-signals).
*   When used as a pair, the `_n` and `_p` suffixes indicate a
    [differential pair of signals](#differential-pairs).
*   The `_ready`, `_valid`, and `_valid_next` suffixes are expected to follow
    standardized [Ready/Valid semantics](#ready-valid).
*   The `_req` and `_ack` suffixes are expected to follow standardized
    [Request/Acknowledge semantics](#req-ack).
*   The `_next` and `_le` suffixes indicate
    [the data and load-enable inputs for a clocked register](#registers).
*   The `_d` suffix indicates a
    [clock-cycle delayed copy of a signal](#delayed-signal).
*   The `_sMpN` and `_uMpN` suffixes (where M and N are integers) indicate a
    [fixed-point signal](#fixed-point-signals).
*   When combining multiple suffixes on a single signal, follow the standardized
    [order of suffixes](#suffix-ordering).

<a id="signal-units"></a>

#### Specify units

Just as with [constants](#constant-units), include the units for a signal in the
signal's symbolic name. Counters must indicate what is being counted. Address
signals must be named to indicate the word size of the thing being indexed.

Unitless signals (for example, `foo_is_enabled`) are excepted from this rule.
Additionally, some standard interfaces (for example, AXI-M) have standardized
naming of signals. In that context, the standardized signal names (`waddr`) are
preferable to more precise names (`write_byte_address`).

Prefer specifying units for logic-vector type signals assuming a 0-based
least-significant bit. If that is not practical and a bit slice is required,
then the signal name must encode the bit-vector range.

Examples:

*   `write_byte_address` is clearer than `write_address`.

*   `max_mibytes_per_sec` is clearer than `max_rate`.

*   `packet_size_beats` or `packet_size_kibytes` is clearer than `packet_size`.

*   `cycle_counter` or `transfer_counter` is clearer than `counter`.

*   For a 64-bit signal `foo_byte_address`, it is assumed to be defined as
    `logic [63:0] foo_byte_address`. A corresponding signal slice in units of 4B
    address could then be defined as either `logic [61:0] foo_4byte_address` or
    `logic [63:2] foo_63_2_byte_address`.

<a id="constant-units"></a>

#### Units for Constants

Just as with [signals](#signal-units), include the units for a constant in the
constant's symbolic name (preferably, as a suffix). The exceptions to this rule
are for constants that are inherently unitless, or if the constant is describing
the default unit type, "bits."

Example:

<a id="active-low-signals"></a>

#### Active-Low Signals

<span class="Summary">The `_n` suffix indicates an active-low signal.</span>

It's recommended to avoid active-low signals. If active-low signals are used,
they must have the `_n` suffix in their name. Otherwise, all signals are assumed
to be active high.

<a id="differential-pairs"></a>

#### Differential Pairs

<span class="Summary">Use the `_p` and `_n` suffixes to indicate a differential
pair.</span>

For example, `in_p` and `in_n` comprise a differential pair set.

<a id="valid"></a>

#### Valid Qualifier Suffix

<span class="Summary">`foo_valid` indicates when `foo_*` signals are valid.
</span>

Signals named with the "\_valid" suffix indicate when a set of related signals
are valid. The signals being labelled by the "foo\_valid" signal must all have
the same "foo\_" prefix.

Signals named with the "\_valid_next" suffix indicate when a set of related
signals will be valid in the next clock cycle (distinct from the
[`_next` register suffix](#registers)). An interface may use `_valid_next`
instead of `_valid` to provide early valid indication; all of the following
rules applied to `_valid` similarly apply to `_valid_next`.

Signals in the "foo\_" group must be ignored when "foo\_valid" is not asserted.

Note that the additional presence of a signal ending with `_ready` indicates the
use of [ready/valid flow control semantics](#ready-valid).

For example:

<a id="registers"></a>

#### Register Signal Suffixes

<span class="Summary">The `_next` and `_le` suffixes have standard meanings
related to registers.</span>

The `_next` suffix indicates a signal that is a D input into a register.
Therefore, the `_next` suffix is permitted on interface signals and module ports
to indicate next-state signals passing across hierarchical boundaries.

The `_le` suffix indicates an optional load-enable signal to a register.

Example:

Additionally:

The `_inc` suffix indicates an increment-enable signal when implementing a
counter.

The `_clear` suffix indicates a register-specific synchronous clear operation.

<a id="delayed-signal"></a>

#### Delayed Signal Suffix

<span class="Summary">Signals delayed by a single clock cycle must end in a `_d`
suffix.</span>

If one signal is only a delayed version of another signal, the `_d` suffix must
be used to indicate this relationship.

If another signal is then delayed by another clock cycle, the next signal must
be identified with the `_d2` suffix, and then `_d3` and so on.

Example:

NOTE: This guide makes a distinction between *delayed signals* and *pipelines*.
A *delayed signal* is a stand-alone signal that is delayed by a number of
cycles. A *pipeline* is a collection of signals across a number of cycles.
[Pipelines have a different style.](#pipelines)

<a id="fixed_point_signals"></a>

<a id="fixed-point-signals"></a>

#### Fixed-Point Signals

<span class="Summary">Signals used for fixed-point arithmetic may be suffixed to
indicate their sign, number of integer bits (including sign bit for signed
signals), and number of fractional bits.</span>

In modules with multiple fixed-point data types, adding a suffix to signal names
may be useful to clearly capture intended design behavior. If a suffix is used,
signal names must be in the form `_sMpN` for signed signals and `_uMpN` for
unsigned signals. "N" indicates the number of fractional bits. "M" indicates the
number of integer bits, including the sign bit for signed signals. This format
is based on [Q Notation](https://en.wikipedia.org/wiki/Q_(number_format)).

Example:

<a id="suffix-ordering"></a>

#### Order of Suffixes

<span class="Summary">When combining multiple suffixes on a single signal, order
them from inner semantic qualifiers to outer temporal qualifiers.</span>

When multiple standard suffixes apply to a single signal, they must be appended
in the following order:

1.  **Units / Semantic Qualifiers**: Functional qualifiers and units (for
    example, `_bytes`, `_valid`, `_ready`, `_req`, `_ack`).
2.  **Fixed-Point Format**: Fixed-point format specifiers (`_sMpN`, `_uMpN`).
3.  **Active-Low Polarity**: Active-low indicator (`_n`).
4.  **Differential Polarity**: Differential pair polarity (`_p`, `_n`).
5.  **Stage / Delay / Register Qualifiers**: Temporal qualifiers (`_next`,
    `_le`, `_inc`, `_clear`, `_d`, `_d<N>`).

Examples:

<a id="macros"></a>

## Preprocessor Directives and Pragmas

This section provides guidance on the use of verilog preprocessor directives and
pragmas.

<a id="global-macro-files"></a>

### Global Macro Files

<span class="Summary">A global macro file is a file that contains only
[global defines](#defines). Global defines are only permitted within global
macro files.</span>

Global macro files are distinct from [include files](#include-files). Global
macro files may not be included using `` `include ``. They are intended to be
visible by all source files in a project.

<a id="defines"></a>

### Macro Definitions

<span class="Summary">Macro names must be `ALL_CAPS` (in other words, consist of
only capital letters, digits, or underscores).</span>

A **global define** is a tick-defined macro in a
[global macro file](#global-macro-files) that is shared by all source files in a
project. To reduce namespace collisions, global defines must be prefixed by the
name of a group of related macros, followed by a pair of underscores:

A global define that is a natural extension or abbreviation of a construct in
the UVM library is exempt from these rules - it is acceptable to define such
macros with the same convention as the UVM library (in other words,
`lower_snake_case`).

<span class="Summary">Local macros must be prefixed with a single underscore.
</span>

A **local define** is a tick-defined macro that must only be used within the
scope of a single local file. It must be explicitly undefined after use, to
avoid polluting the global macro namespace. To indicate that a macro is only
meant to be used in the local scope, the macro name must be prefixed with a
single underscore.

To ensure that local defines stay local, be careful not to `` `include `` other
files between the macro definition and `` `undef ``.

Example:

<a id="standard-macros"></a>

### Standard Macros

<span class="Summary">Use standard macros when available.</span>

Whenever possible, reuse standard macro libraries rather than writing your own.
This style guide provides a reference implementation for the following standard
macros.

<a id="stringify-macro"></a>

#### STRINGIFY Macro

The `STRINGIFY` macro presents a standard way to convert a macro argument into a
string.

For example:

Don't invent alternative implementations:

<a id="bounded-lookup-macro"></a>

#### BOUNDED\_LOOKUP Macro

The `BOUNDED_LOOKUP` macro presents a standard way to build an rvalue that
indexes into an array, when the array size is smaller than maximum possible
value of the index.

The verilog expression `array[index]` would return `'X` for out-of-bound
indices. This alternative has the following properties:

*   Efficient: unnecessary high bits of index are discarded (aliasing the
    array).
*   Safe: returns '0 for all other out-of-bound indices.

<a id="x-of-type-macro"></a>

#### X\_OF\_TYPE Macro

The `X_OF_TYPE` macro presents a standard way to typecast `'X`.

<a id="assertion-macros"></a>

#### Assertion Macros

<span class="Summary">Use assertion libraries to enforce unified implementation
throughout the design.</span>

Following is a reference implementation of standard assertion macros used in
this document.

<a id="synthesis-pragmas"></a>

### Synthesis Pragmas

<span class="Summary">Do not use synthesis pragmas that can lead to
simulation-synthesis differences.</span>

There are several pragmas that impact the creation of the design database
leading to different tools inferring different functionality. These can lead to
hard-to-debug simulation-synthesis mismatches that (depending on methodology)
might not be caught by logical equivalence checks. These include `translate_off`
and `translate_on`, `synthesis_off` and `synthesis_on`, `read_comments_as_hdl
on` and `read_comments_as_hdl off`, `parallel case`, and `full case`. Do not use
these pragmas.

<a id="ifdef-directives"></a>

### `` `ifdef `` Directives

<span class="Summary">Do not use `` `ifdef ``, `` `else ``, `` `elsif ``, or ``
`ifndef `` compiler directives except as prescribed.</span>

Avoid `` `ifdef `` whenever possible. Misuse of `` `ifdef ``-style compiler
directives can negatively impact code coverage, and can lead to a mismatch
between simulation and synthesis. For most use cases, separate source units or
generate-if statements provide a better solution.

The following exceptions are permitted.

<a id="ifdef-simulation"></a>

#### `` `ifdef SIMULATION ``

May only be used additively, to add debug logic or logging statements.
SIMULATION will typically be defined in simulation environments, and will never
be defined in any other environment.

Do not use the SIMULATION macro to select between RTL and behavioral models (see
[anti-patterns](#ifdef-antipatterns)). Do not use the SIMULATION macro to wrap
simple assertions (see [ASSERT_ON](#ifdef-assert_on)).

For example:

<a id="ifdef-assert_on"></a>

#### `` `ifdef ASSERT_ON ``

May only be used additively, to add assertions or assertion-specific modeling
code. This enables an easy path to disable assertions in cases where faster
simulation is needed. See the [Assertion macros](#assertion-macros) section for
macros that implement this switch.

For example:

<a id="ifdef-fpv_on"></a>

#### `` `ifdef FPV_ON ``

May only be used additively, to add monitors and logic used exclusively by
formal property verification tools.

<a id="ifdef-simulator"></a>

#### `` `ifdef <simulator> ``

Some simulators have simulator-specific debug features that need preprocessor
guards. No functional RTL must ever be enclosed by an `` `ifdef <simulator> ``
block.

The legal names to identify supported simulators are:

*   `VCS`: for Synopsys VCS simulators.
*   `INCA`: for Cadence Incisive simulators.
*   `XCELIUM`: for Cadence Xcelium simulators.
*   `DSIM`: for Metrics DSim simulators.

<a id="ifdef-technology"></a>

#### `` `ifdef <technology> ``

It is permitted to use `` `ifdef `` directives to select between implementations
enabled by specific technologies (standard cell libraries, emulation, processes,
FPGA architectures).

If used, there must always be a valid `` `else `` clause that describes a default
implementation. There must also be unit tests that exercise all technology
cases.

Some of the standard names are:

*   `EMULATION`: for emulation-specific code.
*   `FPGA`: for FPGA-specific code.

<a id="ifdef-antipatterns"></a>

#### `` `ifdef `` Anti-patterns

Do not enable features with `` `ifdef ``. Instead, use parameters and generate-if
statements.

Do not use directives similar to `` `ifdef DISABLED `` to disable blocks of code.
Delete dead code instead.

Do not use include guards. Use a properly ordered compilation file list (flist)
so that include guards are unnecessary. See the
[Include Guards](#include-guards) section for more details.

<a id="ifdef-exceptions"></a>

#### `` `ifdef `` Exceptions

There are always unanticipated exceptional scenarios. If your project must use
non-standard `` `ifdef `` directives, follow the following guidelines:

*   The canonical design that gets deployed is what is represented with no
    defines set.

*   Clearly document and justify your macro in the project documentation (no "ad
    hoc" `` `ifdef `` macros).

*   Prefix your macro names with a unique project namespace identifier. For
    example, `FOOBAR__DEBUG` is preferable to `DEBUG` to avoid namespace
    collisions between projects.

*   Choose macro names that connote positive enablement. For example, prefer
    `FOOBAR__PERF_COUNTERS` to `FOOBAR__DISABLE_PERF_COUNTERS`.

<a id="includes"></a>

### Includes

<a id="include-files"></a>

#### Include Files

<span class="Summary">Files intended for [`` `include ``](#include-directives)
are referred to as "include files".</span>

<a id="include-directives"></a>

#### Include Directives

<span class="Summary">Use `` `include `` directives only to include files into a
verilog package file or to include files with code snippets.</span>

Include directives used for the purpose of compiling each file standalone are
forbidden. Instead, use a properly ordered compilation file list and Multi-File
Compilation Unit (MFCU) mode.

There are only a few cases where include directives are allowed:

1.  Including files into a verilog package file is allowed. Each file must be
    included into only one package.

1.  Including files with code snippets is allowed, only when the code snippet
    cannot be wrapped into its own module or package.

<a id="include-guards"></a>

#### Include Guards

<span class="Summary">Don't use include guards.</span>

Include guards protect against repeated expansion within the same translation
unit. They must not be used since the current style guide rule on the use of
[includes](#include-directives) will prevent this from happening.

<a id="stopping-compilation"></a>

### Stopping Compilation

<span class="Summary">Use the `` `DIE() `` macro to fail compilation.</span>

Using this (undefined) macro allows the source file to be parsed by tools that
lack preprocessing, such as code search and IDE outline generators. Pass an
explanation as a string to `` `DIE ``. This convention does not depend on any
other macro files.

<a id="modules-and-packages"></a>

<a id="modules"></a>

## Modules

<a id="module-header-definition"></a>

### Module Header Definition

<span class="Summary">Use the Verilog-2001 full port declaration style, and use
the following format.</span>

Use the Verilog-2001 combined port and I/O declaration style. Do not use the
Verilog-95 list style. Port declarations in the module header must fully declare
the port name, type, and direction.

The clock port(s) must be declared first in the port list, followed by any and
all reset inputs.

For port or parameter lists with declarations, the closing parenthesis of each
list must be on its own line, in column zero. The opening parenthesis must occur
on the same line as the module name or the previous list's closing parenthesis.
The following are exceptions to these rules:

*   If a list has no declarations, then the parentheses are optional. If used,
    the opening and closing parenthesis must be on the same line.
*   If import statements are used, then the opening parenthesis of the following
    list must be on its own line.

Each [import statement](#package-imports) must appear on its own dedicated line
of code.

<a id="module-header-definition-examples"></a>

#### Module Header Definition Examples

Example of a module header without parameters:

Example of a module header with a
[parameter declaration](#parameterized-module-declaration):

Example of a module header with an [import statement](#package-imports):

Do not use Verilog-95 style:

<a id="module-names"></a>

#### Module Names

<span class="Summary">The top level module for a design `[design]` must be named
`[design]_top`. Unit test module names end with `_test`.</span>

Module names must use `lower_snake_case` and contain only lowercase alphanumeric
characters and underscores. Use lowercase even when module-names contain proper
nouns, such as the project's name.

Top-level modules must be named `[design]_top`. For example, the top-level
module for Snout must be named `snout_top`. In this context, the "top level
module" is the highest possible level of a logic design's hierarchy, the
pin-level interface.

Unit test modules must end with the string "\_test". For example,
`dma_controller_test`.

<a id="parameterized-objects"></a>

<a id="parameterized-module-declaration"></a>

#### Parameterized Modules

<a id="when-to-parameterize"></a>

#### When to parameterize

Use module parameters to create customizable modules.

Examples of when to use parameterized modules:

-   When multiple instances of a module will be instantiated, and need to be
    differentiated by a parameter.
-   As a means of specializing a module for a specific bus width.
-   As a means of documenting which design-wide parameters are permitted to
    change within the module.

Do not use module parameters to transmit constants through a design hierarchy
(use [package constants](#constants)) or to declare a constant whose scope is
internal to the module (use [`localparam`](#constants)).

For additional reading, see
[New Verilog-2001 Techniques for Creating Parameterized Models](https://opencw.aprende.org/courses/electrical-engineering-and-computer-science/6-884-complex-digital-systems-spring-2005/related-resources/parameter_models.pdf).

<a id="naming-module-parameters"></a>

#### Naming module parameters

`UpperCamelCase` is the recommended style for module parameter names, except:

*   `ALL_CAPS` may be permitted for historic reasons, and
*   `lower_snake_case_t` is required for parameters that are types, for
    consistency with [naming of other types](#structs-unions).

<a id="parameter-port-lists"></a>

#### Use ANSI-style parameter port lists

Declare parameterized modules using a parameter port list, not with `defparam`.

<a id="parameter-defaults"></a>

#### Parameter defaults

Default values assigned to tunable parameters must be reasonable (in other
words, default values must represent a valid design).

Omitting a default value assignment to a parameter is permitted if it helps
mitigate potential integration bugs.

For example, a [reusable IP's](#reusable-ip) clock frequency parameter may be
reassigned in the majority of instantiations. In this case, the designer may
choose to omit the default value to eliminate the possibility of unintentionally
leaving a parameter unassigned.

Omitting default values for composite type parameters is not permitted due to
inconsistent tool support.

<a id="parameter-data-type"></a>

#### Specify parameter data types

Explicitly declare the type for parameters. Use type "int" (signed integer) for
all simple numeric parameters (for example, quantities). Always write assertions
to validate parameters (bounds checks, etc.). See the
[Assertion macros](#assertion-macros) section for a reference implementation.

For example:

### Module Instances

<a id="module-instance-names"></a>

#### Module Instance Names

<span class="Summary">All module instance names must start with the name of the
module being instantiated.</span>

All module instance names must be equal to the module name, plus an optional
unique suffix. This unique suffix may be a string or a number, as appropriate.
The intent of this naming convention is to make it easier to map from instance
names to module names, especially in contexts where the module name is not
readily available (for example, synthesis reports, assertions, etc.).

Exceptions can be made in instances where this style decreases the overall
legibility of the code (for example, when working with long, hard to read
library module names). In such cases, the module name must follow a project
specific pattern that readily identifies the original module.

Some examples of legal instance names:

<a id="module-instance-named-ports"></a>

#### Use named ports

<span class="Summary">Use named ports to fully specify all instantiations.
</span>

When connecting signals to ports for an instantiation, use the named port style,
like this:

If the port and the connecting signal have the same name, you can use the
`.port` syntax (without brackets) to indicate connectivity. For example:

All declared ports must be present in the instantiation blocks. Unused outputs
must be explicitly written as no-connects (for example: `.output_port()`), and
unused inputs must be explicitly tied to ground (for example:
`.unused_input_port(8'd0)`).

`.*` is not permitted.

Do not use positional arguments to connect signals to ports.

Instantiate ports in the same order as they are defined in the module.

<a id="port-connections-on-module-instances-must-always-match-widths-correctly"></a>

#### Instance connection widths

Port connections on module instances must always match widths correctly.

It is recommended to use explicit widths, rather than relying on Verilog's
implicit zero-extension and truncation operations, whenever practical.

Examples:

<a id="module-instantiation"></a>

#### Parameterized Module Instantiation

<span class="Summary">Use named parameters for all instantiations.</span>

Instances must be named as specified in
[Module Instance Names](#module-instance-names).

When parameterizing an instance, do not specify parameters positionally. Specify
parameters using the named parameter style, as follows:

Do not use `defparam`.

#### Recursive Instantiation

<span class="Summary">Do not instantiate recursively.</span>

Modules may not instantiate themselves recursively.

<a id="generate-constructs"></a>

### Generate Constructs

<span class="Summary">Always name generate construct blocks. The block name must
start with the "gen_" prefix.</span>

When using a generate construct, always explicitly name each block of generated
code. Name each possible outcome of the generating if statement, and name the
iterated block of a generating for statement.

All generate construct block names must start with the "gen_" prefix.

This ensures that generated hierarchical signal names are consistent across
different tools.

Example of a conditional generate construct:

Example of a loop generate construct:

Do not wrap a generate construct with an additional `begin` block.

Do not use generate regions {`generate`, `endgenerate`}.

<a id="problematic-floating-begin-end"></a>

#### Floating begin-end blocks

The use of generate blocks other than for `loop`, `if`, or `case` generate
constructs is not LRM compliant. While such usage might be accepted by some
tools, this guide prohibits such "bare" generate blocks. Note that the similar
"sequential block" construct is LRM compliant and allowed.

<a id="packages"></a>

## Packages

<a id="package-declaration"></a>

### Package Declaration

There is no special guidance for declaring packages.

<a id="package-names"></a>

#### Package Names

Package names must use `lower_snake_case` and contain only lowercase
alphanumeric characters and underscores. A package name must end with the suffix
`_pkg`.

<a id="package-dependencies"></a>

### Package Dependencies

<span class="Summary">Packages must not have cyclic dependencies.</span>

Package files may depend on constants and types in other package files, but
there must not be any cyclic dependencies. That is: if package A depends on a
constant from package B, package B must not depend on anything from package A.
While cyclic dependencies are permitted by the SystemVerilog language
specification, their use can break some tools.

For example:

<a id="package-imports"></a>

### Package imports

Package imports are permitted within a local scope, like a module or package.
Explicit imports are recommended because it is clear where everything comes
from. Wildcard imports are permitted if there is a reasonable argument that the
reduced verbosity enhances readability.

Packages must not be imported into the global scope, as this increases the risk
of conflicts.

<a id="interfaces"></a>

## Interfaces

<a id="interfaces-overview"></a>

### Overview

There is a general desire to adopt interfaces in synthesizable code (DV code can
and does use interfaces). However, in practice, projects have found that there
are several quirks and challenges when working with interfaces. These include:

-   Tool support (although this continues to get better).
-   Global scope (how does one fix just one block with an interface ECO).
-   Challenging interactions with top level Physical Design flows (for example,
    forced bit-blasting).
-   Large amount of "extra typing" to declare and instantiate.

Since many of the benefits of interfaces can be realized with structs, the cost
of allowing interfaces outweighs their benefits. There is likely a set of best
practices that can be defined that would realize the potential of interfaces.
Adoption of interfaces would require including such best practices in the style
guide.

<a id="declarations"></a>

<a id="ports-and-signals"></a>

## Ports, Signals, and Constants

### Overview

*   [Declare all signals](#declare-all-signals) and
    [use `logic`](#use-logic-for-synthesis): `logic foo;`
*   [Signals are named using lower_snake_case](#signal-naming).
*   [Avoid default port values](#port-defaults).
*   [How to declare constants](#constants).
*   [How to declare structs and unions](#structs-unions).
*   [How to declare enumerations](#enumerations).
*   [Use packed arrays and structs](#packed-unpacked).
*   [Packed arrays are little-endian](#packed-ordering): `logic [7:0] byte;`
*   [Unpacked arrays are big-endian](#unpacked-ordering): `byte_t arr[0:N-1];`

Additionally, the semantics of specific naming conventions are elaborated on in
the separate [Naming Conventions](#naming-conventions) section.

<a id="declare-all-signals"></a>

### Declare all signals

<span class="Summary">Signals must be declared before they are used. This means
that implicit net declarations must not be used.</span>

All signals must be explicitly declared before use. All declared signals must
specify a data type. A correct design contains no inferred nets.

Within modules, it is recommended that signals, types, enums, and localparams be
declared close to their first use. This makes it easier for the reader to find
the declaration and see the signal type.

<a id="use-logic-for-synthesis"></a>

### Use `logic` for synthesis

<span class="Summary">Use `logic` for synthesis. `wire` is allowed when
necessary.</span>

All signals in synthesizable RTL must be implemented in terms of 4-state data
types. This means that all signals must ultimately be constructed of nets with
the storage type of `logic`. While SystemVerilog does provide other data
primitives with 4-state storage (for example, `integer`), those primitives are
prone to misunderstandings and misuse.

For example:

It is permissible to use wire as a short-hand to both declare a net and perform
continuous assignment. Take care not to confuse continuous assignment with
initialization. For example:

There are exceptions for places where `logic` is inappropriate. For example,
nets that connect to bidirectional (`inout`) ports must be declared with `wire`.
These exceptions must be justified with a short comment.

It is permissible for DV to make use of 2-state logic, but all interfaces
between 4-state and 2-state signals must assert a check for `X` on the 4-state
net before resolving to a 2-state variable.

<a id="signal-conventions"></a>

<a id="signal-naming"></a>

### Signal Naming

<span class="Summary">Use `lower_snake_case` when naming signals.</span>

In this context, a **signal** is meant to mean a net, variable, or port within a
SystemVerilog design.

Signal names may contain lowercase alphanumeric characters and underscores.

Ports which connect **directly** to chip primary IO pads (for example, die IOs,
ASIC package IOs, or FPGA IO buffers) may use `UPPER_SNAKE_CASE`.

There are a number of naming conventions associated with naming signals, which
are complicated enough to warrant their own
[section of the style guide](#naming-conventions).

<a id="port-defaults"></a>

### Default Port Values

<span class="Summary">Do not use default port values.</span>

A default port value is a constant expression that is assigned to an input port
of a module. Output ports that are assigned constant expressions are not
considered default values and are permitted.

<a id="constants"></a>

### Constants

<span class="Summary">Declare design-wide constants using parameters in the
design package file. Declare local constants using `localparam`.</span>

In this context, **constants** are distinct from tunable parameters for objects
such as [parameterized modules](#parameterized-module-declaration), classes,
etc.

#### Declaring Constants

When declaring a constant:

*   Within a package, use `parameter`.
*   Within a module or class, use `localparam`.

The recommended method of defining constants is to declare a `package` and
declare all constants as a `parameter` within that package.

Define design-wide constants in the design's [package file](#standard-files).

Other packages may also be declared with their own `parameter` constants to
facilitate the creation of [reusable IP](#reusable-ip).

<a id="naming-constants"></a>

#### Naming Constants

`UpperCamelCase` is the recommended style for immutable constants. The
exceptions are:

*   When declaring an [enumerated type](#enumerations), use `kCamelCase` to
    declare enumeration constants.

<a id="constant-data-type"></a>

#### Specify constant data types

Explicitly declare the type for constants. Use type "int" (signed integer) for
all simple numeric parameters (for example, quantities).

<a id="magic-numbers"></a>

#### Avoid Magic Numbers

<span class="Summary">It is recommended to use symbolically named
[constants](#constants) instead of unnamed numerical constants (aka magic
numbers).</span>

Try to give commonly used constants symbolic names rather than repeatedly typing
magic numbers.

Unnamed numerical constants may be acceptable in cases where adding a symbolic
name adds no value. These type of constants are not considered magic numbers.

#### `localparam` in parameter port lists

Generally, module scoped constants, including those derived from
[module parameters](#parameterized-module-declaration) are declared as
localparam within the module body [close to first use](#declare-all-signals). It
can be useful to have module scoped constants (potentially derived from module
parameters) that control module port dimensions. Declare and define these
constants as `localparam` in the module port list to prevent them from being
overridden when the module is instantiated.

<a id="packed-unpacked"></a>

### Packed vs. Unpacked

Use packed arrays and structs for synthesizable signals. Unpacked arrays are
appropriate for behavioral models of SRAMs and DV code.

<a id="positive-array-bounds"></a>

### Positive Array Bounds

When declaring vectors and arrays, the msb and lsb must be non-negative.

<a id="packed-ordering"></a>

### Packed Ordering

<span class="Summary">Bit vectors and packed arrays must be little-endian.
</span>

When declaring bit vectors and packed arrays, the index of the most-significant
bound (left of the colon) must be greater than or equal to the least-significant
bound (right of the colon). This style of bit vector declaration keeps packed
variables little-endian.

For example:

<a id="unpacked-ordering"></a>

### Unpacked Ordering

<span class="Summary">Unpacked arrays must be big-endian.</span>

When declaring unpacked arrays, the index to the left of the colon must be less
than or equal to the index to the right of the colon.

Declare zero-based unpacked arrays using the shorter notation `[size]`. It is
understood that `[size]` is equivalent to the big-endian declaration
`[0:size-1]`.

Assigning directly to an unpacked array as a whole is acceptable, but not
recommended, because mixing big-endian unpacked arrays with little-endian packed
arrays is prone to reversed-ordering mistakes. Prefer assigning elements
individually by index when possible (for parameter arrays, where
element-by-element assignment is not possible without constant functions,
initializing the unpacked array directly is acceptable with caution).

*Rationale:* Big-endian ordering was selected for unpacked arrays over
little-endian because:

*   The C-like `[size]` declaration is preferred for unpacked arrays and is
    equivalent to `[0:size-1]`.
*   Big-endian is required for typical use of the `foreach` construct, which
    creates a loop variable with a positive increment.

This rule only applies to variables and parameters, not to other things such as
arrays of instances. Instance arrays must be declared so that the order of
instances is correct for the ordering of packed ports.

<a id="struct-union-conventions"></a>

<a id="structs-unions"></a>

### Structs and Unions

#### Declaring Structs and Unions

<span class="Summary">Name structs and unions with a typedef.</span>

Always name `struct` and `union` types using `typedef`. Anonymous types are not
allowed because they are not reusable. Struct type names must contain only
lowercase alphanumeric characters and underscores and end with `_t`.

#### Naming Union Members

<span class="Summary">Union member names must be prefixed with as_*.</span>

Always prefix union member names with `as_*`. A consistent naming convention
reduces the effort required to understand RTL with deeply nested struct or union
type hierarchies by making the type-cast like behavior of unions explicit.

<a id="enumerations"></a>

### Enumerations

<span class="Summary">Name enumeration types `snake_case_t` (or `snake_case_e`).
Name enumeration constants `kCamelCase`.</span>

Always name `enum` types using `typedef`. The storage type of any enumerated
type must be specified. For synthesizable enums, the storage type must be a
4-state data type (`logic` rather than `bit`).

Anonymous `enum` types are not allowed as they make it harder to use the type in
other places throughout the project and across projects.

Enumeration type names must contain only lowercase alphanumeric characters and
underscores. You can suffix enumeration type names with `_t` or `_e`, as long as
the suffix is consistent within the project.

Enumeration value names (constants) must be `kCamelCase`, for example,
`kReadyToSend`. This indicates that the values are neither overrideable nor
assignable.

<a id="vector-typedefs"></a>

### Vector Typedefs

<span class="Summary">Prefer no single vector typedefs unless they are broadly
used.</span>

Do not use `typedef` to define local or single-use vector types. Defining a new
type for a vector that is only used in a limited scope adds unnecessary
redirection. Instead, use the raw vector type directly.

For vectors that are used broadly across multiple modules or packages (for
example, a global address type), defining a named type using `typedef` is
recommended to ensure consistency.

An exception is made when defining signed packed arrays, where a `typedef` is
necessary to apply signedness to the elements of the array rather than the array
as a whole (see
[mixed-sign arithmetic operations](#mixed-sign-arithmetic-operations)).

<a id="functions-and-tasks"></a>

## Functions and Tasks

<a id="choosing-function-task-module"></a>

### Choosing Between Functions, Tasks, and Modules

<span class="Summary">In synthesizable RTL, use modules as the default construct
to encapsulate behavior. Tasks must not be used in synthesizable RTL. Functions
may be used for short, simple combinational logic with a single output.</span>

*   **Modules**: Use modules as the default mechanism to encapsulate design
    behavior.
*   **Tasks**: Do not use tasks in synthesizable RTL; use modules instead. Tasks
    are permitted in testbenches.
*   **Functions**: Functions are useful as a lightweight alternative to modules
    for simple combinational logic.
    *   Prefer functions over modules when there is a single output and the
        relationship between inputs and output can be expressed with a direct
        assignment (for example, `assign foo = check_foo(bar);`).
    *   Prefer modules over functions when there are multiple outputs.
    *   Functions can be defined in a package for wider reuse.

<a id="function-task-templates"></a>

### Templates

<span class="Summary">Function and task definitions must follow the template in
the following example.</span>

Some points about the function template to note in addition to the following
sections:

-   The function was declared with the formal arguments in parentheses (matching
    module style).
-   [No assignment in the function body to the input variables](#descriptive-names)
    .

<a id="function-latches"></a>

### Latches inside functions

Do not infer a latch inside a function, as this may cause a simulation-synthesis
mismatch.

<a id="function-task-explicit-lifetime"></a>

### Lifetime

<span class="Summary">Explicitly declare functions and tasks defined outside of
a class as static or automatic, preferring automatic. Functions must be
automatic in synthesizable RTL.</span>

Depending on their declaration context, functions and tasks have different
default lifetimes. Within a class, they are always automatic, whereas the
default is static in modules, interfaces, programs, and packages. To prevent
potential confusion, functions and tasks declared outside of a class must always
explicitly specify their lifetime. Automatic is generally the proper lifetime
because it allows a function or task to be independently called from different
contexts.

In synthesizable RTL, functions must always be declared as automatic.

<a id="function-data-types"></a>

### Function Data Types

<span class="Summary">Explicitly declare the data type for a function, or
declare the function as `void`.</span>

<a id="function-task-argument-types"></a>

### Argument Types

<span class="Summary">Explicitly declare storage types for all arguments in
function and task arguments lists.</span>

For example:

<a id="function-task-argument-directions"></a>

### Argument Directions

<span class="Summary">Argument directions for functions and tasks are optional
and considered inputs by default. If a direction is specified for *any*
argument, then it must be specified for *all* arguments.</span>

For example:

## Sequential Logic

<a id="always_ff-vs-always"></a>

### `always_ff` vs `always`

There is no preference between `always_ff` and `always` for clocked processes,
other than consistency within a project.

<a id="blocking-and-non-blocking-assignments"></a>

<a id="seq-logic-use-non-blocking"></a>

### Use Non-Blocking Assignments

<span class="Summary">Sequential logic must use non-blocking assignments.
</span>

Never mix assignment types within a block declaration.

A sequential block (a block that latches state on a clock edge) must exclusively
use non-blocking assignments, as shown in the section on declaring
[Registers](#sequential-logic-registers).

This stands in contrast to combinational logic, which
[must use blocking assignments in process blocks](#comb-logic-use-blocking-assignments).

This is one of Clifford Cummings's
[Golden Rules of Verilog](http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA.pdf).

<a id="sequential-logic-latches"></a>

### Sequential Logic (Latches)

<span class="Summary">The use of latches is not recommended - use flip-flops
when possible.</span>

Unless absolutely necessary, use flip-flops or registers instead of latches.

If you must use a latch, use `always_latch` over `always`, and use non-blocking
assignments (`<=`). Never use blocking assignments (`=`).

<a id="sequential-logic-registers"></a>

### Sequential Logic (Registers)

<span class="Summary">Use the standard format for declaring sequential blocks.
</span>

In a sequential always block, only use non-blocking assignments (`<=`). Never
use blocking assignments (`=`).

Designs that mix blocking and non-blocking assignments for registers simulate
incorrectly because simulators evaluate blocking assignments in a different
simulation event region than non-blocking assignments. This causes race
conditions where signals bypass pipeline stages, leading to simulation-synthesis
mismatches.

If your next-state generation logic requires blocking assignments to state
clearly, use a separate combinational-only block to generate that next-state
value.

For reusable IP, it is recommended that registers support all three forms of
reset so integrators can tie off unused resets:

-   Synchronous reset
-   Asynchronous reset
-   Initialization (configuration-time initial values for FPGA designs)

Initialization is commonly recommended for SRAM-based FPGAs, whereas synchronous
reset is recommended for ASICs.

A correctly implemented 8-bit register with an initial value of "0xAB" would be
implemented as follows:

Do not allow multiple non-blocking assignments to the same bit.

Example:

If both cond1 and cond2 are true, the Verilog standard says that the second
assignment will take effect, but this is a style violation.

Even if cond1 and cond2 are mutually exclusive, make the second "if" into an
"else if".

Exception: It is fine to set default values first, then specific values.
However, it is recommended to do this work in a separate combinational block
with explicit blocking assignments.

Example:

Keep work in sequential blocks simple. If a sequential block becomes
sufficiently complicated, consider splitting the combinational logic into a
separate combinational (`always_comb`) block. It's recommended for a sequential
block to contain only a register instantiation, with perhaps a load enable or an
increment.

<a id="resets"></a>

### Resets

[Reusable IP](#reusable-ip) must consistently implement all three varieties of
reset (synchronous reset, asynchronous reset, and configuration-time
initialization) so that the non-preferred reset schemes can be disabled at
implementation time. See [Sequential Logic](#sequential-logic-registers) for
more details.

<a id="delays"></a>

### Delay Modeling

<span class="Summary">Do not use `#delay` in synthesizable design modules.
</span>

Synthesizable design modules must be designed around a zero-delay simulation
methodology. All forms of `#delay`, including `#0`, are not permitted.

<a id="delay-units"></a>

#### Delays and Time Units

<span class="Summary">In non-synthesizable code always specify a time unit if
`#delay` is used, except for `#0`.</span>

Whenever using non-zero pound `#` delays, always specify a time unit in addition
to the raw number, to avoid timescale issues.

Note that specifying time units alone does not guarantee proper behavior. Use
project-wide `timeunit` and `timeprecision` settings in your module, package, or
interface to ensure the proper behavior (see section 3.14.2.2 of the 1800-2017
LRM for more details).

<a id="finite-state-machines"></a>

### Finite State Machines

<span class="Summary">State machines use an enum to define states, and are
implemented with two process blocks: a combinational block and a clocked block.
</span>

Every state machine description has three parts:

1.  An enum that declares and describes the states.
1.  A combinational process block that decodes state to produce next state and
    other combinational outputs.
1.  A clocked process block that updates state from next state.

*Enumerating States*

The enum statement for the state machine must list each state in the state
machine. Comments describing the states must be deferred to the case statement
in the combinational process block, as shown in the following example.

States must be named in `kCamelCase`, like other
[enumeration constants](#enumerations).

Barring special circumstances, the initial idle state of the state machines will
be named `kIdle`. (Alternate names are acceptable if they improve clarity.)

It's recommended for each module to only contain one state machine. If your
module needs more than one state machine, you will need to add a unique prefix
(or suffix) to the states of each state machine, to distinguish which state is
associated with which state machine. For example, a module with a "reader"
machine and a "writer" machine might have a `kRdIdle` state and a `kWrIdle`
state.

*Combinational Decode of State*

The combinational process block must contain:

-   A case statement that decodes state to produce next state and combinational
    outputs. For clarity, only cases where the output value deviates from the
    default must be coded.
-   Before the case statement must be a block of code that defines default
    values for every combinational output, including "next state."
-   The default value for the "next state" variable must be the current state.
    The case statement that decodes state will then only assign to "next state"
    when transitioning between states.
-   Within the case statement, each state alternative must be preceded with a
    comment that describes the function of that state within the state machine.

*The State Register*

No logic except for reset must be performed in this process. The state variable
must latch the value of the "next state" variable.

*Other Guidelines*

When possible, try to choose state names that differ near the beginning of their
name, to make them more readable when viewing waveform traces.

*Example*

<a id="combinational-logic"></a>

<a id="comb-logic"></a>

## Combinational Logic

<a id="comb-logic-use-always-comb"></a>

### Use `always_comb` or `assign`

<span class="Summary">Avoid sensitivity lists.</span>

Use either `always_comb` blocks or `assign` statements for combinational logic.

<a id="comb-logic-use-blocking-assignments"></a>

### Use blocking assignments

<span class="Summary">Synthesizable combinational process blocks must only use
blocking assignments.</span>

All assignments within a synthesizable
[`always_comb` block](#comb-logic-use-always-comb) must be blocking assignments.

Non-blocking assignments are used only in
[sequential logic blocks](#seq-logic-use-non-blocking).

<a id="x-propagation"></a>

### X Propagation

<span class="Summary">Either propagate `X`'s, or catch them via assertions. Do
not silently squash `X` in logic.</span>

Write logic that will either propagate `X` or assert when your inputs are `X`.
Avoid silently squashing `X` by writing logic that resolves an `X` input to a
non-`X` output. Instead, write logic that either explicitly propagates the `X`
or uses an assertion to raise an exception when an input is `X`.

<a id="logical-operations-and-if-statements"></a>

#### Logical operations and `if` statements

Note that logical operations involving `X` will propagate `X` in a way that
accurately represents silicon behavior.

Example:

However, when evaluated in a boolean context, `X` always evaluates to false. As
a result, typical `if`/`else` statements do not propagate `X` in a way that
accurately represents silicon behavior.

Example:

This can mask subtle problems in code and produce a mismatch between simulation
and synthesis.

Instead, use conditional operators, which will propagate an `X`. If that hurts
readability, an alternative is to use assertions to catch `X`.

Another alternative is to have explicit `if` and `else if` clauses for `0` and
`1`. However, this is verbose and more difficult to maintain.

<a id="x_prop_case_statements"></a>

<a id="x-prop-case-statements"></a>

#### X Propagation in Case Statements

See [Case Statements](#case-statements) for guidance and examples.

<a id="x_prop_array_indexing"></a>

<a id="x-prop-array-indexing"></a>

#### Array indexing

Writing into an array when the index is `X` does not propagate the `X` to the
array contents.

Instead, assertions must be used to catch `X` in the array index.

<a id="x_prop_clocks_and_resets"></a>

<a id="x-prop-clocks-and-resets"></a>

#### Clocks and Resets

The preceding X propagation guidelines do not apply to clocks and resets.
Instead, extra care must be taken at each clock-domain level in the hierarchy to
ensure clocks and resets are never driven to `X` along with `!$isunknown()`
assertions.

The reason for this is that the recommended coding styles for sequential logic
do not propagate `X` on clocks and resets. For example, `posedge clk` still
triggers on a `0` to `X` transition. Also, synthesis tools recommend using `if`
statements for asynchronous resets instead of conditional operators.

<a id="further-discussion"></a>

#### Further discussion

-   ["I'm Still In Love With My X!"](http://sutherland-hdl.com/papers/2013-DVCon_In-love-with-my-X_paper.pdf)
    by Stuart Sutherland
-   ["Being Assertive With Your X"](http://lcdm-eng.com/papers/snug04_assertiveX.pdf)
    by Don Mills

<a id="dont-care-assignments"></a>

### Don't-Care Assignments

<span class="Summary">Do not specify don't-care logic in synthesizable code.
</span>

For the purposes of this document, don't-care logic is defined as the explicit
or implicit assignment to `X` based on known (non-`X`) inputs. Don't-care logic
is a subset of unknown logic values, and not all assignments to `X` are
considered don't-care logic. For examples of allowed assignments to `X`, see
[X Propagation](#x-propagation).

Don't-care assignments are problematic for automated engineering change orders
(ECOs) and complicate Logic Equivalence Checking (LEC) between netlists because
synthesis can produce netlists that have chosen conflicting interpretations of
the don't-care states. If designers need to take advantage of don't-care space
for optimizations, there are external tools like [Espresso][espresso] that can
be used instead.

[espresso]: https://en.wikipedia.org/wiki/Espresso_heuristic_logic_minimizer

<a id="dont-care-explicit-assignments"></a>

##### Don't-Care in Explicit Assignments

Do not assign don't-care logic. A signal must be known if the signals driving it
are known.

<a id="dont-care-in-case-statements"></a>

##### Don't-Care in Case Statements

See [Case Statements](#case-statements) for guidance on how to avoid introducing
don't-care logic in case statements.

<a id="dont-care-in-array-indexing"></a>

##### Don't-Care in Array Indexing

Do not access an index that is outside the bounds of an array. This can happen
if the array size is not a power-of-two, or if the index contains superfluous
MSBs.

Instead, specify behavior for out-of-range indices or explicitly pad arrays up
to power-of-two sizes. Also, add an assertion to catch out-of-range indices.

Properly handling arbitrary array sizes is complex. It is recommended that
projects use the standard [`BOUNDED_LOOKUP` macro](#bounded-lookup-macro) for
the general case.

<a id="tri-state-logic"></a>

### Tri-State Logic

Do not use three-state logic (`Z` state) to accomplish on-chip logic such as
muxing.

<a id="case_statements"></a>

<a id="case-statements"></a>

### Case Statements

<span class="Summary">Use `unique case` in synthesizable RTL. Always define a
default case-item. Do not specify [don't-care](#dont-care-assignments) behavior.
Do not use case-modifying pragmas.</span>

Here is an example of a style-compliant case statement:

The `unique` prefix is recommended before all case statements, as it creates
simulation assertions that can catch certain mistakes. In some cases, `priority`
may be used instead of `unique`, though `if-else-if` structures are a more
readable representation for priority encoders. Code other than synthesizable RTL
can use `case` without `unique` or `priority` if necessary.

Be sure to use `unique case` correctly. In particular, outputs for any
unspecified case-items are treated as don't-care by the synthesis tools. This
can lead to a simulation-synthesis mismatch as described in
[Don Mills' paper][yalagp]. Including a `default` case-item ensures the case
statement is always fully defined, which helps avoid unintuitive don't-care
behavior.

The `default` case-item is also required to avoid accidental inference of
latches, even if all cases are covered. In simulation, a case expression that
evaluates to `X` will not match any case and will behave as a latch, leading to
different behavior than synthesis. Instead, in most scenarios, the best choice
is to propagate the `X` by assigning all output variables to `X` by default.

Note that the SystemVerilog-2009 `unique0` keyword is not currently supported by
all tools.

<a id="wildcards-in-case-items"></a>

#### Wildcards in case items

Use `case` instead of `casez` whenever wildcard operator behavior is not
required. When wildcard behavior is needed, use `casez`.

When expressing a wildcard in a case item, use the '?' character since it more
clearly expresses the intent.

Here is an example of a style-compliant `casez` statement:

`casex` must not be used. `casex` implements a symmetric wildcard operator such
that an `X` in the case expression may match one or more case items. `casez`
only treats high-impedance states (`Z` or `?`) as a wildcard, and performs exact
matches for undriven `X` inputs. While this does not completely fix the problems
with symmetric wildcard matching, it is harder to accidentally produce a `Z`
input than an `X` input, so this form is preferred.

<a id="dont-care-in-case-statements2"></a>

##### Don't-care in case statements

[Don’t-care](#dont-care-assignments) behavior is introduced anytime `X`
assignments are made from a don’t-care branch of a case statement.

To avoid don't-care behavior, specify non-`X` behavior for all outputs, across
the full range of values in the case-expression. If this prevents x-propagation,
assertions must be used to ensure `X`'s in the case-expression are not silently
squashed.

Note that assigning to `X` from the default case-item of an otherwise
fully-specified case statement does not introduce don’t-care logic. In this
case, using the default for x-propagation is the recommended style.

If assigning X to an enumerated type in the default case-item, then the
assignment must be typecast. It is recommended that projects use a
[macro](#x-of-type-macro) to safely contain this cast.

With multiple outputs, it can be convenient to specify default values outside of
the case statement. If this is done, the `unique case` statement must be fully
specified, otherwise these outputs are treated as don't-cares for any
unspecified case-items.

<a id="upside-down-unique-case-statements"></a>

##### Upside-down unique case statements

Upside-down unique case statements are another way of introducing don't-care
behavior. If multiple conditions of the upside-down case statement are true, the
output assignment is not explicitly provided in the code, effectively leading to
a don't-care assignment. This will cause the same LEC and ECO issues as if the
condition was explicitly coded as an X output. See
[Don't-Care Assignments](#dont-care-assignments). It is recommended to rewrite
the code as a non-upside-down case statement, or do manual logic reduction if
timing is a concern.

<a id="synthesis-pragmas-in-case"></a>

##### Synthesis Pragmas

Never use either the `full_case` or `parallel_case` pragmas. These pragmas can
easily cause synthesis-simulation mismatches. This is a subset of the
[general guidance to avoid synthesis pragmas](#synthesis-pragmas).

References:

*   Don Mills, [Yet Another Latch and Gotchas Paper][yalagp]
*   Clifford Cummings,
    [SystemVerilog-2009 Enhancements: ‘priority’, ‘unique’, ‘unique0’][priuniq]
*   Sutherland, Mills, and Spear,
    [Gotcha Again: More Subtleties in the Verilog and SystemVerilog Standards...][gotagain]

[yalagp]: http://lcdm-eng.com/papers/snug12_Paper_final.pdf
[priuniq]: https://dvcon-proceedings.org/wp-content/uploads/systemverilog-2009-enhancements-priority-unique-unique.pdf
[gotagain]: http://lcdm-eng.com/papers/snug07_Verilog%20Gotchas%20Part2.pdf

<a id="signed-arithmetic"></a>

### Signed Operations

<span class="Summary">Use the available signed operator constructs wherever
signed operations are used.</span>

Mixing signed and unsigned signals in an operation can result in unexpected
behavior and, in some cases, simulation-synthesis mismatches. For all operations
where signed and unsigned signals need to be used together, the unsigned signals
must first be explicitly cast to signed, using the `signed'` cast operator.

If any operand in a calculation is unsigned, Verilog implicitly casts all
operands to unsigned and generates a warning. There must not be any
signed-to-unsigned warnings from either the simulation or synthesis tools if all
unsigned variables are properly cast.

<a id="mixed-sign-arithmetic-operations"></a>

##### Mixed-Sign Arithmetic Operations

Explicitly cast unsigned values to signed before use in mixed-sign arithmetic
operations.

<a id="mixed-sign-comparison-operations"></a>

##### Mixed-Sign Comparison Operations

Explicitly cast unsigned values to signed before use in mixed-sign comparison
operations.

<a id="arithmetic-right-shift-operations"></a>

##### Arithmetic Right Shift Operations

Always use the `>>>` operator instead of the `>>` operator when arithmetically
right shifting signed values.

It is common practice to use right arithmetic shift operators to divide by
powers of 2. With signed operands, care must be taken that the correct shift
operator is used to preserve sign. The `>>` operator inserts a 0 at the most
significant bit location. If the argument is a negative value, this will flip
the sign. By using the `>>>` operator, the bit inserted at the most significant
bit location is determined by the sign of the argument and will not flip.

<a id="signal-widths"></a>

### Bit Widths

<span class="Summary">Be careful about signal and expression widths.</span>

<a id="number-literals"></a>

#### Always be explicit about the widths of number literals.

Always explicitly size number literals to match their final width. Verilog's
implicit zero-extension and truncation operations can lead to subtle bugs.

If the literal is specified in a binary format then all digits must be
explicitly written out to avoid unintentional zero-extension in the most
significant bits. This can catch subtle bugs if an intermediate bit is dropped.
Literals written in decimal and hexadecimal formats do not need to explicitly
include all significant digits because they tend not to be used for hard-to-read
patterns.

Exceptions:

*   When using literals in expressions with parameterized widths, it is
    acceptable to use integers without an explicit width (for example, `foo =
    bar + 1`) to avoid contrivances such as `{{(Bus_width-1){1'b0}},1'b1}`. The
    language will properly pad 0s if the literal is narrower than the expression
    width and lint tools typically raise an error if the literal is wider than
    the expression width.
*   It is acceptable to use the `'0` or `'1` literals to automatically create
    correctly sized (context-determined) zero or "all ones".
*   For literals assigned to integer variants (for example, `bit`, `byte`,
    `shortint`, `int`, `integer`, and `longint`) the explicit width is optional.

Examples:

<a id="do-not-use-multi-bit-signals-in-a-boolean-context"></a>

#### Do not use multi-bit signals in a boolean context

Rather than letting boolean operations and if expressions reduce a multi-bit
signal to a single bit, explicitly compare the multi-bit signal to 0. The
implicit conversion can hide subtle logic bugs.

Examples:

<a id="prefer-logical-operators-single-bit-signals"></a>

#### Prefer Logical Operators for Single-Bit Signals

<span class="Summary">When performing logical operations on single bit signals,
it is recommended to use the logical operators (for example, &&, ||, !) instead
of bitwise operators (for example, &, |, ~).</span>

<a id="handling-width-overflow"></a>

#### Handling Width Overflow

Beware of shift operations, which can produce a result wider than the operand.
Bit-selection and concatenation may be clearer than shifting by a constant
amount.

Addition and negation operations produce a result one bit wider than the
operands, due to carry. An allowable exception to the rule about matching widths
is to silently drop the carry on assignment.

Example:

<a id="bit-slicing"></a>

### Bit Slicing

Only use the bit slicing operator when the intent is to refer to a portion of a
bit vector.

Examples:

<a id="alias-statement"></a>

### Alias statement

<span class="Summary">Do not use `alias`, use port connection if possible or
`tran` if you must.</span>

`Alias` statement can be used to connect `inout` nets, but there is a history
for `alias` statement to not be supported by EDA tools (as of 2019). Hence do
not use `alias`. The recommended alternatives are using conventional port
connections, if possible, or `tran` (a bidirectional pass switch) to connect
ports.

<a id="implicitly-sized-expressions"></a>

### Implicitly Sized Expressions

<span class="Summary">Do not rely on the width of implicitly sized
sub-expressions.</span>

Instead, when requiring that a sub-expression produce a result of a specific
width, either:

*   Cast the sub-expressions to specific widths (note that this may cause a
    truncation).
*   Break compound expressions into separate partial result variables.

The bit lengths of self-determined expressions (summarized in Table 11-21 of the
[SystemVerilog-2017 standard]) are counter-intuitive (for example, `a * b`
produces a result of length `max($bits(a), $bits(b))`). To avoid these gotchas,
it is best to not rely on implicitly sized results at all.

For example, the following code is wrong:

The expression in the preceding example synthesizes to zero, because
(surprisingly) the length of the implicitly sized expression `en_a << 4` is 1
(`$bits(en_a)`).

A correct implementation would explicitly size each expression, either by adding
explicit sizes to the sub-expressions:

Or by decomposing the expression into explicitly sized partial results:

<a id="conventions"></a>

## Design Conventions

<a id="design-conventions-summary"></a>

### Summary

The key ideas in this section include:

*   Use a consistent [timescale](#timescale) for all RTL.
*   [Use flow control consistently](#flow-control).
*   [Use clock domain crossing consistently](#synchronization).
*   [Rules for top-level implementation](#top-level-implementation).
*   [Prefer to register module outputs](#registered-inputs-and-outputs).

<a id="timescale"></a>

### Timescale

<span class="Summary">Every project must define a consistent way of specifying
timescale.</span>

There are multiple ways to specify the timescale, each with pros and cons. Each
project must define a single way to specify the timescale for the entire
project. Individuals must not implement one-off timescale solutions.

<a id="bus-protocol-naming"></a>

### Bus Protocols

Bus protocols are commonly used to connect components of the chip. When using an
industry standard protocol, use the terminology established by that protocol.
When designing a new protocol, the agent that controls the bus or initiates
transactions is named the `requester` while the agent that services the
transaction is the `completer`.

*   Be sure to follow the
    [guidance on inclusive language in external IP](#non-inclusive-language-in-external-ip).
    Change non-inclusive industry standard names as appropriate.
*   If a communication protocol has a pattern that doesn't map to
    `requester/completer` it is ok to use more accurate names (for example,
    leader and follower). This guidance is intended to standardize the common
    case.

<a id="flow-control"></a>

### Flow Control

<span class="Summary">Standardize flow control using Ready/Valid semantics
wherever possible.</span>

Flow control is often used to facilitate back pressure as data moves through a
pipeline.

The recommended flow control semantic is the [Ready/Valid](#ready-valid)
semantic. Experience shows that connecting two modules with inconsistent flow
control semantics is a common source of hard-to-catch errors.

If an interface is defined without flow control, a comment must explain why flow
control and back pressure are unnecessary in that particular case.

<a id="struct-usage"></a>

#### Struct Usage

<span class="Summary">Do not group flow control and data signals in the same
struct. All data signals in a struct must share the same flow control.</span>

When grouping data signals, flow control signals must not be included in the
same structure as the data they are qualifying. Additionally, all data signals
in the structure must have the same flow control behavior and be qualified by
the same external flow control signals. Otherwise, use of the structure could
easily lead to data propagation bugs.

<a id="ready-valid"></a>

#### Ready/Valid

<span class="Summary">Ready/Valid semantics express the recommended method of
flow control.</span>

Ready/Valid semantics mimic the requirements of the AXI handshake process, as
defined in the
[AMBA AXI Protocol Specification](https://developer.arm.com/documentation/ihi0022/latest/).

With Ready/Valid semantics, the sender uses the Valid signal to advertise that a
data transfer is available. The receiver generates the Ready signal to indicate
that it can accept a data transfer. The transfer only occurs on any cycle where
Ready and Valid are both asserted.

The Ready signal must be identified with the "\_ready" suffix. The Valid signal
must be identified with the "\_valid" suffix. The other signals in the data
transfer must share a prefix with the Ready and Valid signals (for example:
"foo\_ready", "foo\_valid", "foo\_data1", "foo\_data2", etc.).

Once Valid is asserted it must remain asserted until the data transfer occurs.
For interfaces using `_valid_next`, once `_valid_next` is asserted in a given
cycle, the data transfer is scheduled for the next clock cycle; if `_ready` is
not asserted on that next cycle, the data transfer remains pending and the data
must remain held constant until the transfer completes.

Once Valid is asserted, the data bus must be held constant until the data
transfer occurs.

Once Ready is asserted, the receiver is permitted to deassert Ready at any time.

On the sender interface, there may be no combinational path between input and
output signals. The receiver, however, is permitted to produce `ready`
combinationally from inputs such as `valid` or data.

NOTE: This is at odds with the AXI4 specification, which forbids combinational
paths between inputs and outputs.

Some modules might have important reasons to change this protocol. If the
assumptions of this protocol are violated, use a different signal name
convention to clearly indicate that the standard Ready/Valid semantics are not
in force. For example, if your protocol permits a "skid" of an extra data
transfer after Valid gets de-asserted, consider documenting this in the signal
name (for example, "foo\_valid\_for\_two").

`wr_en` or `rd_en` are acceptable proxies for Valid, when appropriate.

<a id="credit-valid"></a>

#### Credit/Valid

Credit/Valid flow control decouples data transmission from flow-control feedback
using a credit counter, making it suitable for long-distance, wide, or
high-frequency pipelines where single-cycle Ready/Valid backpressure is
impractical.

<a id="req_ack"></a>

<a id="req-ack"></a>

#### Req/Ack

<span class="Summary">Req/Ack semantics express an alternate method of flow
control.</span>

Req/Ack semantics are functionally equivalent to
[Ready/valid semantics](#ready-valid). [Ready/Valid](#ready-valid) is the
recommended style for most new code. [Credit/Valid](#credit-valid) is
recommended to be considered for very long, very wide, or very high-speed buses.

A request and acknowledge interface is always defined by two signals:

-   foo\_req: the request signal, which is asserted to request an event, and is
    held active until the posedge of a clock cycle in which foo\_ack is
    asserted.
-   foo\_ack: the acknowledge signal, which is asserted on the cycle in which
    the request is acknowledged. It is possible (likely, even) for foo\_ack to
    be asserted within the same cycle that foo\_req is asserted.

Additional signals associated with this interface (in other words, information
that accompanies the request) must share a signal name prefix with the request
and acknowledge pair. These signals must be kept valid the entire time that
request is asserted.

If foo\_req is not asserted, no assumptions can be made about foo\_ack (the
receiver might choose to tie foo\_ack to 1'b1 if it can never stall) -- the
transmitter must only care about the state of foo\_ack on cycles where foo\_req
is valid.

For example:

<a id="synchronization"></a>

### Synchronization

<span class="Summary">Users must avoid implementing their own CDC synchronizers
and instead rely upon a proven library implementation.</span>

<span class="Summary">Any module that contains CDC synchronizers must separate
and encapsulate logic for each clock domain in separate sub-modules.</span>

It is not acceptable to have combinational or sequential code written in the
same level of hierarchy that includes a CDC instantiation. If there are multiple
clock domains in a module, then all logic that belongs to each domain must be
separated from the others and encapsulated within one or more sub-modules.

*Exception:* CDC implementations (for example, from a design library) are not
subject to this rule. By design, they are required to mix logic from multiple
clock domains within the same module (at some level of hierarchy).

*Rationale:* Mixing functional logic from multiple clock domains in the same
module results in poor readability of combinational and sequential logic (for
example, extra [clock name prefix](#clock-domains) on signals in logical
expressions) and can increase the risk of accidental CDC bugs (for example,
crossing clock domains without a synchronizer). This style rule enforces
structural separation of logic that belongs to different clock domains.

<a id="top-level-implementation"></a>

### Top-level Implementation

<span class="Summary">A set of guidelines that emphasize maintainability of the
top-level implementation.</span>

The top-level implementation is a pain point for many designs. The following
recommendations focus on keeping top-level implementations simple and
maintainable.

The following practices are recommended:

-   *No logic or registers* in the top-level instance. All logic is implemented
    within sub-modules. The top level instance contains nothing but instances of
    sub-modules.
-   *Simple mapping of ports to signals*. The goal is to make the mapping of
    ports onto signals as simple (and automatable) as possible. The best
    practice is to have top-level signal names that are identical to port names.
    When this is not practical, the following simple and consistent mapping
    schemes represent the next best thing:
    -   a consistent renaming that maps all ports with one prefix to signals
        with another prefix. For example, a set of "m\_axi\_\*" ports might be
        mapped consistently to a set of "s05\_axi\_\*" wires.
    -   mapping a port to a slice of a larger bus. For example, an
        `access_requestN` port might be connected to an `access_request[5]`
        wire.
    -   if interfaces are being used, it may be necessary to create a consistent
        instance name that is distinct from the interface name or modport name.
-   Consider *automating* the production of your top-level block, using
    automatic tools such as [verilogpp](https://github.com/google/verilogpp) .

<a id="registered-inputs-and-outputs"></a>

### Registered Inputs and Outputs

<span class="Summary">Strongly prefer to place module-boundary registers on
outputs.</span>

When placing module-boundary registers, it is strongly recommended that the
registers be placed on the module outputs, rather than the module inputs.

If the outputs of a non-trivial module aren't registered, this must be clearly
documented in the header comment of the module.

Top-level modules must have registered inputs and outputs for maximum top-level
routing flexibility.

It is assumed that inputs to all modules come from the output flops of a
previous module, so it is generally not required to register the inputs of a
module, with the following two exceptions:

-   Inputs from an external pin must be registered (retimed) before use.
-   Top-level blocks may register both inputs and outputs, to maximize routing
    flexibility.

<a id="verification"></a>

## Verification

<a id="verification-summary"></a>

### Summary

<span class="Summary">This section documents guidelines for writing Design
Verification (DV) code in Verilog.</span>

<a id="assertions"></a>

### Assertions

<span class="Summary">Assumptions and invariants in logic must be formally
expressed as runtime assertions.</span>

Assertions must represent behaviors that ALWAYS happen (and not be used to flag
error conditions that might be exercised in simulation).

Assertions must be placed within RTL files so that assertions and their related
logic are close together.

Assertions must be placed in a design according to these guidelines:

-   All input ports to a block (except clocks, resets, test, debug or
    unconstrained data ports) must be included in at least one assertion that
    describes the protocol.
-   All output ports of a block (except test and debug) must be included in at
    least one assertion that describes the functionality of the block and the
    protocol of the signals.
-   All synthesized functional registers in a block must be within the cone of
    influence of an assertion. Further, they must be within three static levels
    of logic from the assertion.
-   Important end-to-end behaviors of a block must be described with an
    assertion.
-   Any minimum levels of performance for a block must be described with an
    assertion. Some performance measuring debug logic may be needed to
    supplement the assertions.

Use [standardized assertion macros](#assertion-macros) whenever possible.

<a id="unit-tests"></a>

### Unit Tests and Designer Tests

<span class="Summary">Thorough unit tests are required for shared libraries and
[reusable IP](#reusable-ip) design blocks. All other design blocks require
designer tests.</span>

#### Naming Unit Tests

Unit test modules must end with the string "\_test". For example,
`dma_controller_test`.

<a id="minimum-testing-requirements"></a>

#### Minimum Testing Requirements

If the RTL is a [reusable IP](#reusable-ip), every feature must be exhaustively
tested.

Otherwise:

1.  The design block must elaborate and pass lint checks.
1.  The design block must come out of reset with no X's on the outputs.
1.  At least one transaction must be sent through the block and observed
    correctly.

The second category is also referred to as "designer tests".

<a id="constraints"></a>

### Constraints

<span class="Summary">Use `lower_snake_case` when naming constraints with an
`_c` suffix.</span>

<a id="plusargs"></a>

### Plusargs

<a id="plusarg-value-assignment"></a>

#### Plusarg Value Assignment

<span class="Summary">Plusargs must specify a value to be assigned to a variable
(for example, use +en_foo=1, not +en_foo). Do not use $test$plusargs.</span>

For example:

<a id="plusarg-naming"></a>

#### Plusarg Naming

<span class="Summary">The plusarg name must match the variable that stores the
passed plusarg, exclusive of any prefix or suffix of either the plusarg or the
variable.</span>

For example:

<a id="text-formatting"></a>

### Text Formatting

<a id="number-formatting"></a>

#### Displayed Number Format

<span class="Summary">Printed numbers must be prefixed with their radix as shown
in the following examples.</span>

When formatting text representations of numbers for log files, make it clear
what data you are including.

Make the base of a printed number clear. Print decimal numbers without the
radix.

Binary: `0b` or `'b`

Hexadecimal: `0x` or `'h`

Decode individual fields of large structures individually, instead of expecting
the user to manually decode raw values.

<a id="string-formatting"></a>

#### String Formatting

<span class="Summary">Use `$sformatf()` for string type formatting. Avoid using
`$display()` to format string types.</span>

The [SystemVerilog-2017 standard] is vague on how string type formatting must be
handled by `$display()`. Simulator implementation of this functionality varies.
`$sformatf()` has a more consistent interpretation and implementation.

<a id="forbid-line-continuations"></a>

#### Line Continuation of String Literals

Do not use a '\' (backslash) character to continue a long string literal to the
next line, use `{}` string concatenation operator instead.

<a id="loops"></a>

### Loop operators

<span class="Summary">Prefer foreach loops.</span>

Where possible, prefer foreach loops over equivalent loop operators. They are
concise and less prone to subtle errors.

### Code Within Asserts

Do not assert on calls to `randomize`. More broadly, do not place any expression
with side effects into an assert statement.

SystemVerilog has a couple ways to disable all assertions such as `$assertoff`
or `$assertkill`. When an assertion is disabled, future assertion attempts will
not evaluate the assertion expression, as per the LRM (not until the assertion
is re-enabled via `$asserton` or one of its alternatives). This is particularly
bad when randomize is used within the assertion expression, because disabled
assertions result in unrandomized objects.

### Wait and Fork

Always put `wait fork` or `disable fork` constructs inside of an isolation `fork
... join` block, or the environment can end up waiting on other, earlier forks
it was not intending to wait for.

<a id="void-casts"></a>

### Void Casts

Do not void cast calls that have useful or important return values. This
includes calls to `uvm_config_db::get`, `uvm_hdl_read`, `randomize`, etc.

For example, **do not do the following**:

Instead, check the return value of calls to `randomize` and similar calls in
order to handle the potential error.

<a id="associative-arrays"></a>

### Associative arrays

<span class="Summary">Do not use wildcard indexed [*] associative arrays.</span>

Associative arrays with wildcard index are hard to use because the item type
could be anything. Always specify a particular index type for associative
arrays:

### Bind Statements

`bind` statements may be used in verification. This is the preferred approach
for using assertion based monitors.

".\*" is allowed for making implicit port declarations when binding a module
whose ports are all inputs.

<a id="program-block"></a>

### Program block

<span class="Summary">Do not use `program` and `endprogram` blocks.</span>

It provides the false sense of security. Use `module` and clocking blocks to
avoid DUT race conditions instead.

<a id="simulator-specific"></a>

### Simulator-specific code

<span class="Summary">All simulator-specific code must be wrapped inside
preprocessor guards.</span>

The following macro names are always defined by each simulator. These names must
be used to wrap all simulator-specific code, so the code can be compiled for
every simulator.

-   `VCS` - for VCS
-   `INCA` - for Incisive/NCsim/Irun
-   `XCELIUM` - for Xcelium/xrun
-   `DSIM` - for DSim

<a id="forbidden-system-functions"></a>

### Forbidden System Tasks and Functions

Do not use the following functions.

*   `$psprintf`: `$psprintf` is supported by a number of tools because it was
    legal in older versions of the language. However, it is not in the language
    reference manual. Replace with SystemVerilog's `$sformatf`.

*   `$random` and `$dist_*`: these functions must not be used as they are not
    part of the SystemVerilog random stability model and may break simulation
    reproducibility. Use $urandom or randomize() instead.

*   `$srandom`: `$srandom` must not be used as it is not part of the
    SystemVerilog standard. Use `process::self().srandom()` instead.

*   `$display`, `$displayb/o/h`, `$write`, `$writeb/o/h`: Do not use `$display`
    or similar "display" system tasks to display messages in UVM environments,
    instead use standard [UVM logging](#uvm-logging) macros for a consistent and
    controllable way of message logging.

*   `$info`, `$fatal`, `$error`, `$warning`: Do not use "severity" system tasks
    in UVM environments, instead use corresponding [UVM logging](#uvm-logging)
    macros.

<a id="uvm"></a>

### UVM

<a id="uvm-phase-super-convention"></a>

#### Phase Methods

<span class="Summary">Always call `super.<phase_name>(phase)` when overriding
UVM phase methods in derived classes.</span>

When overriding UVM phase methods (such as `build_phase`, `connect_phase`,
`run_phase`, etc.) in a class derived from a UVM component, you must call the
parent class's implementation using `super.<phase_name>(phase)`. This ensures
that any setup or configuration performed by the parent class is executed.

Exceptions are allowed if the base class is a direct UVM library class (like
`uvm_component`, `uvm_test`, `uvm_env`, etc.) where the default implementation
is known to be empty, BUT it is still recommended to call it for consistency and
future-proofing. For user-defined base classes, it is mandatory.

<a id="uvm-logging"></a>

#### UVM Logging

<span class="Summary">Only use `` `uvm_info ``, `` `uvm_error ``, and ``
`uvm_fatal `` UVM messaging macros for message logging in UVM
environments.</span>

Only use the following UVM macros to display log messages in UVM environments:

-   `` `uvm_info(ID, message, verbosity) ``: For informational messages.
-   `` `uvm_error(ID, message) ``: For messages indicating a problem that needs
    to be addressed.
-   `` `uvm_fatal(ID, message) ``: For messages indicating a critical problem
    that stops the simulation.

Do not call underlying UVM functions like `uvm_report_*`. Macros provide better
control over verbosity, timestamping, and component identification.

Do not use the `` `uvm_warning `` macro. Categorize messages as informational
(info) or as conveying an issue that needs to be addressed (error or fatal).
Although forbidden, it's recommended to setup your infrastructure to treat ``
`uvm_warning `` as errors.

<a id="uvm-macro-semicolon"></a>

#### UVM Macro Semicolons

<span class="Summary">Do not append a semicolon to UVM macro calls.</span>

UVM macros (including messaging macros like `` `uvm_info `` and sequence action
macros like `` `uvm_do ``) must not be followed by a semicolon. Appending a
semicolon can result in an empty statement, which can cause syntax errors in
contexts like `if` statements without `begin` / `end` blocks.

<a id="sequences-and-sequence_items"></a>

#### Sequences and Sequence_items

Call the `randomize()` or `randomize() with {}` function of the sequence before
executing the sequence.

<a id="uvm-create"></a>

#### Creating Objects and Components

<span class="Summary">Use the `create()` API to create UVM objects and
components.</span>

Use the `type_id::create()` API to instantiate all UVM objects and components.
This is standard UVM programming practice and is necessary to take advantage of
UVM factory features, such as type and instance overrides.

Exceptions are permitted for objects or components that are not intended for
reuse (such as TLM ports, exports, and analysis ports) or when significant
performance gains can be achieved. In such exceptional cases, `new()` may be
used directly.

When creating classes derived from `uvm_component`, pass `this` as the `parent`
argument so that the component hierarchy is built properly.

<a id="uvm-naming"></a>

#### UVM Naming

<span class="Summary">When creating a UVM object or component using
`type_id::create()`, the string name argument must match the name of the
variable to which it is assigned.</span>

For array assignments, the string name must include the index in square brackets
(for example, `[<index>]`).

This ensures consistency and helps with debugging, as the hierarchical path in
UVM will match the variable names in the code.

<a id="uvm-class-constructor-default-values"></a>

#### Class Constructor Default Values

<span class="Summary">For classes derived from `uvm_object`, the constructor
parameter `name` must default to `""`. For classes derived from `uvm_component`,
the constructor must not specify default values.</span>

When defining a constructor for a UVM class:

-   Classes extending `uvm_object` must define the constructor parameter as
    `string name = ""` (empty string) and pass it to `super.new(name)`. Do not
    provide non-empty default object names.
-   Classes extending `uvm_component` must define the constructor parameters as
    `(string name, uvm_component parent)` without default argument values.

<a id="uvm-test-execution"></a>

#### Test Execution

<span class="Summary">Do not pass arguments to `run_test()`.</span>

Always call `run_test()` without arguments. Specify the test name on the command
line using `+UVM_TESTNAME=test_name` instead of hardcoding it in the code.

