"""
Strict Verilog-2001 & Cyclone V RTL Linter (Google Verilog Style Guide Aligned).

Helper Tools:
  - Icarus Verilog (iverilog): Compiler elaboration pre-flight check
    (iverilog -Wall -g2001 -tnull -y <dir> -I <dir> <file>)
  - Verilator: Static RTL analysis (verilator --lint-only -Wall +1364-2001ext+v)

Rules Summary:
  1. File Structure & Aesthetics:
     - FILE_EXT_SYSTEMVERILOG (ERROR): Rejects .sv / .svh extensions.
     - FILE_MULTIPLE_MODULES (ERROR): At most one module per file.
     - FILE_MODULE_NAME_MISMATCH (ERROR): Module name must match filename stem.
     - DIRECTIVE_DEFAULT_NETTYPE_NONE (ERROR): Mandatory `default_nettype none before module.
     - DIRECTIVE_DEFAULT_NETTYPE_WIRE (ERROR): Mandatory `default_nettype wire after endmodule.
     - HEADER_GUARD_MISSING (ERROR): .vh files must have `ifndef/`define/`endif include guards.
     - FILE_HEADER_COMMENT_MISSING (WARNING): Every file must start with a descriptive header comment.
     - TAB_CHARACTER (WARNING): Tabs are prohibited; use spaces.
     - TRAILING_WHITESPACE (WARNING): Trailing whitespace at end of lines.
     - LINE_TOO_LONG (WARNING): Wrap code at 100 characters per line.
     - INDENTATION_STEP (WARNING): Indentation must be in multiples of 2 spaces.
     - REDUNDANT_SEMICOLON (WARNING): Consecutive semicolons (;;).
     - BEGIN_END_STYLE (WARNING): begin on same line as keyword; end else begin together.
     - PREPROCESSOR_INDENT (WARNING): Branching preprocessor directives left-aligned at column 0.
     - SPACING_STYLE (WARNING): Space after control keywords; no space before function call parens.

  2. Naming & Port Conventions:
     - SV_KEYWORD_BANNED (ERROR): Prohibits SV keywords (logic, always_ff, always_comb, typedef, etc.).
     - CLOCK_RESET_NAMING (ERROR): Clock port must be 'clk' (or <domain>_clk); reset must be 'rst'/'arst'/'rst_n'.
     - PORT_ORDER_CLK_RST (WARNING): clk must be first in port list, followed by rst/arst.
     - PARAM_NAMING_STYLE (ERROR): parameter and localparam must use UpperCamelCase.
     - FSM_STATE_NAMING_STYLE (ERROR): FSM states must use localparam and kUpperCamelCase (e.g. kIdle).
     - SIGNAL_UNDERSCORE_NUMBER (ERROR): Signal/port names must not end in _[0-9]+ (use _d2, etc.).
     - MACRO_NAMING_AND_UNDEF (ERROR): `define must be ALL_CAPS; local .v macros must start with _ and be `undef'd.
     - INSTANCE_NAME_CONVENTION (ERROR): Submodule instances must start with <module_name> (or uut/dut in tests).

  3. Modules, Instantiations & Generate:
     - DEFAULT_PORT_VALUE_PROHIBITED (ERROR): Default input port values in module headers are banned.
     - POSITIONAL_INSTANTIATION (ERROR): Named port binding (.port(sig)) is required.
     - POSITIONAL_PARAM_INSTANTIATION (ERROR): Named parameter override (#(.Param(val))) is required.
     - FLOATING_INPUT_PORT (ERROR): Input ports must not be left floating (.port()).
     - DEFPARAM_PROHIBITED (ERROR): defparam is banned.
     - RECURSIVE_INSTANTIATION (ERROR): Recursive instantiation is prohibited.
     - GENERATE_BLOCK_LABEL (ERROR): generate begin blocks must be labeled with gen_ prefix.

  4. Procedural Logic, Synthesis & Widths:
     - MANUAL_SENSITIVITY_LIST (ERROR): Combinational blocks must use always @*.
     - SEQUENTIAL_BLOCKING_ASSIGNMENT (ERROR): Blocking (=) prohibited in clocked blocks.
     - COMBINATIONAL_NONBLOCKING_ASSIGNMENT (ERROR): Non-blocking (<=) prohibited in combinational blocks.
     - ANTI_PATTERN_REDUNDANT_CLOCK_CHECK (ERROR): Redundant 'else if (clk)' check in edge-triggered block.
     - DELAY_PROHIBITED (ERROR): #delay prohibited in synthesizable RTL.
     - CASEX_PROHIBITED (ERROR): casex is prohibited; use case or casez.
     - CASEZ_Z_LITERAL (ERROR): casez literals must use ? for wildcards, not z/Z.
     - SYNTHESIS_PRAGMA_PROHIBITED (ERROR): full_case, parallel_case, translate_off pragmas are prohibited.
     - TASK_IN_RTL_PROHIBITED (ERROR): Tasks prohibited in synthesizable RTL.
     - FUNCTION_NOT_AUTOMATIC (ERROR): RTL functions must be declared 'function automatic'.
     - PACKED_UNPACKED_ENDIANNESS (ERROR): Packed vectors little-endian [MSB:LSB]; unpacked big-endian [0:N-1].
     - BINARY_LITERAL_WIDTH_MISMATCH (ERROR): Sized binary literals must explicitly specify all N digits.
     - SIGNED_LOGICAL_RIGHT_SHIFT (ERROR): Signed variables must use >>> instead of >>.
     - NESTED_TERNARY_PARENS (WARNING): Nested ternaries must be parenthesized.
     - REDUCTION_OPERATOR_PARENS (WARNING): Reduction ops preceded by other ops must be parenthesized.
     - TESTBENCH_PLUSARG_TEST (WARNING): $test$plusargs prohibited; use $value$plusargs.

  5. Intel Cyclone V Hardware Invariants:
     - M10K_ASYNC_READ_PROHIBITED (ERROR): Synchronous reads required for M10K block RAM.
     - CLOCK_GATING_LOGIC_PROHIBITED (ERROR): Gated clocks (clk & en) prohibited; use clock enables.
     - INTERNAL_TRISTATE_PROHIBITED (ERROR): Internal 1'bz prohibited (allowed only in top-level inout pins).

Waivers:
  Any rule can be waived via an inline comment on the same or immediately preceding line:
    // lint_waive: RULE_NAME - Justification
"""

import argparse
from enum import Enum
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Dict, List, Optional, Pattern, Set, Tuple


class Severity(Enum):
  ERROR = "ERROR"
  WARNING = "WARNING"
  INFO = "INFO"


class LintViolation:

  def __init__(
      self,
      rule_id: str,
      severity: Severity,
      file_path: Path,
      line_num: int,
      col_num: int,
      message: str,
      snippet: str = "",
  ):
    self.rule_id = rule_id
    self.severity = severity
    self.file_path = file_path
    self.line_num = line_num
    self.col_num = col_num
    self.message = message
    self.snippet = snippet

  def __str__(self) -> str:
    color_map = {
        Severity.ERROR: "\033[91m",
        Severity.WARNING: "\033[93m",
        Severity.INFO: "\033[94m",
    }
    sev = f"{color_map.get(self.severity, '')}{self.severity.value}\033[0m"
    loc = (
        f"{self.file_path}:{self.line_num}:{self.col_num}"
        if self.line_num > 0
        else str(self.file_path)
    )
    out = (
        f"\033[1m{loc}:\033[0m [{sev}] \033[1m({self.rule_id})\033[0m:"
        f" {self.message}"
    )
    if self.snippet:
      out += f"\n    \033[90m{self.line_num} | \033[0m{self.snippet.strip()}"
    return out


def mask_comments_and_strings(source: str) -> str:
  """Masks comments and strings with spaces, preserving line and column offsets."""

  def _repl(m):
    return re.sub(r"[^\r\n]", " ", m.group(0))

  return re.sub(
      r"//[^\r\n]*|/\*[\s\S]*?\*/|\"(?:\\.|[^\"\\\r\n])*\"", _repl, source
  )


def parse_waivers(raw_source: str) -> Dict[int, Set[str]]:
  """Extracts line-level waivers: // lint_waive: RULE_ID [optional notes]."""
  waivers: Dict[int, Set[str]] = {}
  pattern = re.compile(
      r"(?://|/\*)\s*lint_waive:\s*([A-Za-z0-9_]+)", re.IGNORECASE
  )
  for idx, line in enumerate(raw_source.splitlines()):
    line_num = idx + 1
    matches = pattern.findall(line)
    if matches:
      rule_set = {m.strip() for m in matches}
      waivers.setdefault(line_num, set()).update(rule_set)
      # Also grant waiver to the immediately following line
      waivers.setdefault(line_num + 1, set()).update(rule_set)
  return waivers


# Regex Patterns
RE_MODULE = re.compile(r"\bmodule\s+([a-zA-Z_0-9]+)\b")
RE_ENDMODULE = re.compile(r"\bendmodule\b")
RE_ALWAYS = re.compile(r"\balways\s*@\s*(\([^)]*\)|\*)")
RE_MEM_DECL = re.compile(
    r"\breg\s+(?:\[[^\]]+\]\s+)?([a-zA-Z_0-9]+)\s*\[[^\]]+\]\s*;"
)
RE_INST = re.compile(
    r"\b([a-zA-Z_0-9]+)\s*(?:#\s*\((.*?)\)\s*)?([a-zA-Z_0-9]+)\s*\(([^;]*)\)\s*;",
    re.DOTALL,
)
RE_GATED_CLK = re.compile(
    r"\b(?:assign\s+|wire\s+)[a-zA-Z_0-9]*clk[a-zA-Z_0-9]*\s*=\s*[^;]*(?:\b(?:clk|clock)\b\s*&|&\s*\b(?:clk|clock)\b)",
    re.IGNORECASE,
)
RE_ASSIGN = re.compile(r"^\s*assign\b")
RE_DELAY = re.compile(r"#[0-9]+")
RE_REDUNDANT_CLK = re.compile(r"\belse\s+if\s*\(\s*(?:clk|clock)\s*\)")
RE_BLOCKING = re.compile(r"(?<![=!<>])=(?![=])")
RE_NONBLOCKING = re.compile(r"<=")
RE_TRISTATE = re.compile(r"1'[bB][zZ]")
RE_UPPER_CAMEL = re.compile(r"^[A-Z][a-zA-Z0-9]*$")
RE_K_CAMEL = re.compile(r"^k[A-Z][a-zA-Z0-9]*$")
RE_SIGNAL_UNDERSCORE_NUM = re.compile(
    r"\b([a-zA-Z][a-zA-Z0-9_]*?_([0-9]+))\b"
)
RE_BINARY_LITERAL = re.compile(r"\b(\d+)'[bB]([01_]+)\b")

SV_KEYWORDS: Tuple[Tuple[str, Pattern], ...] = (
    ("logic", re.compile(r"\blogic\b")),
    ("always_ff", re.compile(r"\balways_ff\b")),
    ("always_comb", re.compile(r"\balways_comb\b")),
    ("always_latch", re.compile(r"\balways_latch\b")),
    ("typedef", re.compile(r"\btypedef\b")),
    ("enum", re.compile(r"\benum\b")),
    ("package", re.compile(r"\bpackage\b")),
    ("interface", re.compile(r"\binterface\b")),
    ("struct", re.compile(r"\bstruct\b")),
    ("union", re.compile(r"\bunion\b")),
    ("unique case", re.compile(r"\bunique\s+case\b")),
    ("priority case", re.compile(r"\bpriority\s+case\b")),
    ("wildcard port (.*)", re.compile(r"\(\s*\.\*\s*\)")),
    ("'0 or '1", re.compile(r"(?<!\d)'[01]\b")),
)

SYNTHESIS_PRAGMAS = (
    "full_case",
    "parallel_case",
    "translate_off",
    "translate_on",
    "synthesis_off",
    "synthesis_on",
)

RESERVED_KEYWORDS = {
    "module",
    "always",
    "initial",
    "case",
    "casex",
    "casez",
    "if",
    "else",
    "assign",
    "begin",
    "end",
    "generate",
    "endgenerate",
    "function",
    "task",
    "for",
    "while",
}

PRIMITIVE_GATES = {
    "and",
    "nand",
    "or",
    "nor",
    "xor",
    "xnor",
    "buf",
    "not",
    "bufif0",
    "bufif1",
    "notif0",
    "notif1",
}

FATAL_VERILATOR_RULES = {
    "LATCH",
    "WIDTH",
    "CASEINCOMPLETE",
    "COMBDLY",
    "UNDRIVEN",
    "MULTIDRIVEN",
    "ALWCOMBORDER",
}


class VerilogLinter:
  """Linter for Verilog-2001 and Cyclone V, incorporating Google Style Guide."""

  def __init__(self, run_iverilog: bool = True, run_verilator: bool = True):
    self.run_iverilog = run_iverilog and (shutil.which("iverilog") is not None)
    self.run_verilator = run_verilator and (
        shutil.which("verilator") is not None
    )

  def _add(
      self,
      violations: List[LintViolation],
      waivers: Dict[int, Set[str]],
      rule_id: str,
      path: Path,
      line: int,
      col: int,
      msg: str,
      snippet: str = "",
      severity: Severity = Severity.ERROR,
  ) -> None:
    if line in waivers and rule_id in waivers[line]:
      return
    violations.append(
        LintViolation(rule_id, severity, path, line, col, msg, snippet)
    )

  def lint_file(self, file_path: Path) -> List[LintViolation]:
    violations: List[LintViolation] = []

    if file_path.suffix in [".sv", ".svh"]:
      violations.append(
          LintViolation(
              "FILE_EXT_SYSTEMVERILOG",
              Severity.ERROR,
              file_path,
              1,
              1,
              f"SystemVerilog extension ({file_path.suffix}) prohibited. Use"
              " .v or .vh for Verilog-2001.",
          )
      )
      return violations

    if file_path.suffix not in [".v", ".vh"]:
      return violations

    try:
      raw_source = file_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
      violations.append(
          LintViolation(
              "FILE_READ_ERROR",
              Severity.ERROR,
              file_path,
              0,
              0,
              f"Failed to read file: {e}",
          )
      )
      return violations

    waivers = parse_waivers(raw_source)
    lines = raw_source.splitlines()
    masked_source = mask_comments_and_strings(raw_source)
    masked_lines = masked_source.splitlines()
    is_tb = (
        file_path.stem.lower().startswith("tb_")
        or file_path.stem.lower().endswith("_tb")
        or file_path.stem.lower().endswith("_test")
    )

    self._check_file_structure(
        file_path, masked_lines, lines, waivers, violations
    )
    self._check_formatting_and_style(
        file_path, masked_lines, lines, waivers, violations
    )
    self._check_sv_keywords(file_path, masked_lines, lines, waivers, violations)
    self._check_naming_and_types(
        file_path, masked_lines, lines, waivers, violations, is_tb
    )
    self._check_procedural_blocks(
        file_path, masked_lines, lines, waivers, violations, is_tb
    )
    self._check_instantiations_and_generate(
        file_path, masked_lines, lines, waivers, violations, is_tb
    )
    self._check_cyclone_v_invariants(
        file_path, masked_lines, lines, waivers, violations
    )

    if file_path.suffix == ".v":
      if self.run_iverilog:
        self._run_iverilog_check(file_path, waivers, violations)
      if self.run_verilator and not is_tb:
        self._run_verilator_check(file_path, waivers, violations)

    return violations

  def _check_file_structure(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
  ) -> None:
    # Header comment check
    first_non_empty = next((l for l in raw_lines if l.strip()), "")
    if not (
        first_non_empty.startswith("//") or first_non_empty.startswith("/*")
    ):
      self._add(
          violations,
          waivers,
          "FILE_HEADER_COMMENT_MISSING",
          file_path,
          1,
          1,
          "Missing file header comment describing module and theory of"
          " operation.",
          first_non_empty,
          severity=Severity.WARNING,
      )

    has_nettype_none = False
    nettype_none_line = None
    has_nettype_wire = False
    nettype_wire_line = None
    module_lines: List[Tuple[int, str]] = []
    last_endmodule_line = None

    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      if "`default_nettype" in line:
        if "none" in line:
          has_nettype_none = True
          if nettype_none_line is None:
            nettype_none_line = line_num
        elif "wire" in line:
          has_nettype_wire = True
          nettype_wire_line = line_num

      match = RE_MODULE.search(line)
      if match:
        module_lines.append((line_num, match.group(1)))

      if "endmodule" in line:
        last_endmodule_line = line_num

    first_mod_line = (
        module_lines[0][0] if module_lines else (len(raw_lines) + 1)
    )

    if not has_nettype_none or (
        nettype_none_line and nettype_none_line > first_mod_line
    ):
      self._add(
          violations,
          waivers,
          "DIRECTIVE_DEFAULT_NETTYPE_NONE",
          file_path,
          nettype_none_line or 1,
          1,
          "Missing `default_nettype none at top of file (must precede module"
          " declarations).",
      )

    if file_path.suffix == ".v":
      if not has_nettype_wire or (
          last_endmodule_line
          and nettype_wire_line
          and nettype_wire_line < last_endmodule_line
      ):
        last_line = len(raw_lines) or 1
        self._add(
          violations,
          waivers,
          "DIRECTIVE_DEFAULT_NETTYPE_WIRE",
          file_path,
          nettype_wire_line or last_line,
          1,
          "Missing `default_nettype wire after endmodule.",
        )

      if len(module_lines) > 1:
        mod_names = ", ".join(f"'{m[1]}'" for m in module_lines)
        self._add(
            violations,
            waivers,
            "FILE_MULTIPLE_MODULES",
            file_path,
            module_lines[1][0],
            1,
            f"File contains multiple modules ({mod_names}). Exactly one module"
            " per file required.",
            raw_lines[module_lines[1][0] - 1],
        )
      elif len(module_lines) == 1:
        mod_line, mod_name = module_lines[0]
        if mod_name != file_path.stem:
          self._add(
              violations,
              waivers,
              "FILE_MODULE_NAME_MISMATCH",
              file_path,
              mod_line,
              1,
              f"Module name '{mod_name}' does not match filename stem"
              f" '{file_path.stem}'.",
              raw_lines[mod_line - 1],
          )

    elif file_path.suffix == ".vh":
      has_ifndef = any(
          re.match(r"^\s*`ifndef\s+", l) for l in masked_lines
      )
      has_def = any(re.match(r"^\s*`define\s+", l) for l in masked_lines)
      if not (has_ifndef and has_def):
        self._add(
            violations,
            waivers,
            "HEADER_GUARD_MISSING",
            file_path,
            1,
            1,
            "Header file (.vh) must contain standard `ifndef / `define include"
            " guards.",
        )

  def _check_formatting_and_style(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
  ) -> None:
    for idx, raw_line in enumerate(raw_lines):
      line_num = idx + 1
      m_line = masked_lines[idx] if idx < len(masked_lines) else ""

      # Tabs
      if "\t" in raw_line:
        self._add(
            violations,
            waivers,
            "TAB_CHARACTER",
            file_path,
            line_num,
            raw_line.find("\t") + 1,
            "Tab character found. Use spaces (2 spaces per indent level).",
            raw_line,
            severity=Severity.WARNING,
        )

      # Trailing whitespace
      if raw_line.rstrip("\r\n") != raw_line.rstrip():
        self._add(
            violations,
            waivers,
            "TRAILING_WHITESPACE",
            file_path,
            line_num,
            len(raw_line.rstrip()) + 1,
            "Trailing whitespace at end of line.",
            raw_line,
            severity=Severity.WARNING,
        )

      # Line length (100 char limit)
      clean_line = raw_line.rstrip("\r\n")
      if len(clean_line) > 100 and not (
          "`include" in clean_line or "http://" in clean_line or "https://" in clean_line
      ):
        self._add(
            violations,
            waivers,
            "LINE_TOO_LONG",
            file_path,
            line_num,
            101,
            f"Line exceeds 100 characters ({len(clean_line)} chars).",
            clean_line[:105] + "...",
            severity=Severity.WARNING,
        )

      # Indentation check (multiples of 2 spaces)
      stripped = raw_line.lstrip()
      if (
          stripped
          and not stripped.startswith("//")
          and not stripped.startswith("/*")
          and not stripped.startswith("*")
      ):
        if not stripped.startswith("`"):  # Preprocessor left-aligned checked separately
          indent = len(raw_line) - len(stripped)
          if indent % 2 != 0:
            self._add(
                violations,
                waivers,
                "INDENTATION_STEP",
                file_path,
                line_num,
                1,
                f"Indentation is {indent} spaces (must be a multiple of 2).",
                raw_line,
                severity=Severity.WARNING,
            )

      # Redundant semicolons
      if ";;" in m_line:
        self._add(
            violations,
            waivers,
            "REDUNDANT_SEMICOLON",
            file_path,
            line_num,
            m_line.find(";;") + 1,
            "Redundant semicolon (;;).",
            raw_line,
            severity=Severity.WARNING,
        )

      # Preprocessor directive column 0 alignment
      if re.match(r"^\s+`(?:ifdef|ifndef|else|elsif|endif)\b", m_line):
        self._add(
            violations,
            waivers,
            "PREPROCESSOR_INDENT",
            file_path,
            line_num,
            1,
            "Branching preprocessor directives (`ifdef, `else, `endif) must be"
            " left-aligned at column 0.",
            raw_line,
            severity=Severity.WARNING,
        )

      # Spacing after keywords (if, for, case, while)
      kw_spacing_match = re.search(r"\b(if|for|while|case)\(", m_line)
      if kw_spacing_match:
        self._add(
            violations,
            waivers,
            "SPACING_STYLE",
            file_path,
            line_num,
            kw_spacing_match.start() + 1,
            f"Missing space after keyword '{kw_spacing_match.group(1)}' before"
            " '('.",
            raw_line,
            severity=Severity.WARNING,
        )

      # Begin / End placement: 'begin' must be on the same line as preceding keyword
      if re.match(r"^\s*begin\b", m_line) and idx > 0:
        prev_m = masked_lines[idx - 1].strip()
        if re.search(
            r"\b(if|else|for|while|case|casex|casez|always)\s*(\([^)]*\))?$",
            prev_m,
        ):
          self._add(
              violations,
              waivers,
              "BEGIN_END_STYLE",
              file_path,
              line_num,
              1,
              "'begin' should be placed on the same line as the preceding"
              " keyword.",
              raw_line,
              severity=Severity.WARNING,
          )

      # 'end else begin' must be on one line
      if (
          re.match(r"^\s*else\s+begin\b", m_line)
          and idx > 0
          and masked_lines[idx - 1].strip() == "end"
      ):
        self._add(
            violations,
            waivers,
            "BEGIN_END_STYLE",
            file_path,
            line_num,
            1,
            "Use 'end else begin' on a single line instead of 'end' followed by"
            " 'else begin'.",
            raw_line,
            severity=Severity.WARNING,
        )

      # Synthesis pragmas
      for pragma in SYNTHESIS_PRAGMAS:
        if pragma in raw_line.lower():
          self._add(
              violations,
              waivers,
              "SYNTHESIS_PRAGMA_PROHIBITED",
              file_path,
              line_num,
              1,
              f"Synthesis pragma '{pragma}' is prohibited (causes"
              " simulation-synthesis mismatches).",
              raw_line,
          )

  def _check_sv_keywords(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
  ) -> None:
    for idx, line in enumerate(masked_lines):
      for name, pattern in SV_KEYWORDS:
        match = pattern.search(line)
        if match:
          self._add(
              violations,
              waivers,
              "SV_KEYWORD_BANNED",
              file_path,
              idx + 1,
              match.start() + 1,
              f"SystemVerilog construct '{name}' is not allowed in"
              " Verilog-2001 RTL.",
              raw_lines[idx],
          )

  def _check_naming_and_types(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
      is_tb: bool,
  ) -> None:
    source_text = "\n".join(masked_lines)

    # Macro naming and local macro undef
    defined_local_macros: Dict[str, int] = {}
    undefed_macros: Set[str] = set()

    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      m_def = re.match(r"^\s*`define\s+([A-Za-z0-9_]+)", line)
      if m_def:
        m_name = m_def.group(1)
        if not m_name.isupper():
          self._add(
              violations,
              waivers,
              "MACRO_NAMING_AND_UNDEF",
              file_path,
              line_num,
              1,
              f"Macro name '{m_name}' must be ALL_CAPS.",
              raw_lines[idx],
          )
        if file_path.suffix == ".v" and not is_tb:
          if not m_name.startswith("_"):
            self._add(
                violations,
                waivers,
                "MACRO_NAMING_AND_UNDEF",
                file_path,
                line_num,
                1,
                f"File-local macro '{m_name}' in .v file must start with a"
                " single underscore (e.g. '_{m_name}').",
                raw_lines[idx],
            )
          defined_local_macros[m_name] = line_num

      m_undef = re.match(r"^\s*`undef\s+([A-Za-z0-9_]+)", line)
      if m_undef:
        undefed_macros.add(m_undef.group(1))

    for m_name, l_num in defined_local_macros.items():
      if m_name not in undefed_macros:
        self._add(
            violations,
            waivers,
            "MACRO_NAMING_AND_UNDEF",
            file_path,
            l_num,
            1,
            f"Local macro '{m_name}' must be explicitly `undef'd before end of"
            " file.",
            raw_lines[l_num - 1],
        )

    # Parameters & Localparams casing
    re_param = re.compile(
        r"\b(?:parameter|localparam)\s+(?:(?:signed\s+)?\[[^\]]+\]\s+)?([A-Za-z0-9_]+)\s*="
    )
    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      for m in re_param.finditer(line):
        p_name = m.group(1)
        is_fsm_candidate = any(
            s in p_name.upper()
            for s in ("STATE", "IDLE", "WAIT", "READ", "WRITE", "DONE", "INIT")
        )
        if is_fsm_candidate:
          if "parameter" in line and "localparam" not in line:
            self._add(
                violations,
                waivers,
                "FSM_STATE_NAMING_STYLE",
                file_path,
                line_num,
                m.start(1) + 1,
                f"FSM state constant '{p_name}' declared with 'parameter'. Use"
                " 'localparam [WIDTH-1:0]'.",
                raw_lines[idx],
            )
          if not RE_K_CAMEL.match(p_name):
            self._add(
                violations,
                waivers,
                "FSM_STATE_NAMING_STYLE",
                file_path,
                line_num,
                m.start(1) + 1,
                f"FSM state constant '{p_name}' must use kUpperCamelCase"
                f" (e.g. 'k{p_name.capitalize()}').",
                raw_lines[idx],
            )
        else:
          if not RE_UPPER_CAMEL.match(p_name):
            self._add(
                violations,
                waivers,
                "PARAM_NAMING_STYLE",
                file_path,
                line_num,
                m.start(1) + 1,
                f"Parameter/localparam '{p_name}' must use UpperCamelCase.",
                raw_lines[idx],
            )

    # Signal names ending with underscore-number (e.g. data_1, foo_2)
    re_sig_decl = re.compile(
        r"\b(?:wire|reg|input|output|inout)(?:\s+(?:wire|reg))?\s+(?:signed\s+)?(?:\[[^\]]+\]\s+)?([A-Za-z0-9_,\s]+?)(?:;|,|\)|$)"
    )
    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      for m_decl in re_sig_decl.finditer(line):
        sig_list = m_decl.group(1).split(",")
        for sig in sig_list:
          sig_clean = sig.strip()
          m_num = RE_SIGNAL_UNDERSCORE_NUM.match(sig_clean)
          if m_num:
            # Exception: delayed signals _d[0-9]+
            if not re.search(r"_d\d+$", sig_clean):
              self._add(
                  violations,
                  waivers,
                  "SIGNAL_UNDERSCORE_NUMBER",
                  file_path,
                  line_num,
                  line.find(sig_clean) + 1,
                  f"Signal '{sig_clean}' ends with '_<number>'. Use '_d<N>',"
                  " '_ch<N>' or array indexing instead.",
                  raw_lines[idx],
              )

    # Module port list checks (clk, rst naming and default port values)
    re_port_list = re.compile(r"\bmodule\s+\w+\s*(?:#\([^)]*\)\s*)?\((.*?)\);", re.DOTALL)
    m_ports = re_port_list.search(source_text)
    if m_ports and not is_tb:
      ports_str = m_ports.group(1)
      ports_start_line = source_text[: m_ports.start(1)].count("\n") + 1
      port_entries = [p.strip() for p in ports_str.split(",") if p.strip()]

      for p_idx, p_entry in enumerate(port_entries):
        # Default port value in header
        if re.search(r"\binput\b.*=", p_entry):
          self._add(
              violations,
              waivers,
              "DEFAULT_PORT_VALUE_PROHIBITED",
              file_path,
              ports_start_line,
              1,
              f"Default input port value prohibited: '{p_entry}'.",
          )

        # Clock & reset naming
        m_clk_rst = re.search(
            r"\binput\s+(?:wire\s+)?([A-Za-z0-9_]+)", p_entry
        )
        if m_clk_rst:
          name = m_clk_rst.group(1)
          if name in ("clock", "clk_in"):
            self._add(
                violations,
                waivers,
                "CLOCK_RESET_NAMING",
                file_path,
                ports_start_line,
                1,
                f"Clock port '{name}' must be named 'clk' (or '<domain>_clk').",
            )
          if name in ("reset", "rst_in"):
            self._add(
                violations,
                waivers,
                "CLOCK_RESET_NAMING",
                file_path,
                ports_start_line,
                1,
                f"Reset port '{name}' must be named 'rst' (sync) or 'arst'"
                " (async).",
            )

        # Port ordering (clk must be first)
        if p_idx == 0 and "clk" not in p_entry.lower() and len(port_entries) > 1:
          if any("clk" in p.lower() for p in port_entries):
            self._add(
                violations,
                waivers,
                "PORT_ORDER_CLK_RST",
                file_path,
                ports_start_line,
                1,
                "Clock port ('clk') must be the first port in the module port"
                " list.",
                severity=Severity.WARNING,
            )

    # Binary literals full-digit sizing
    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      for m_bin in RE_BINARY_LITERAL.finditer(line):
        declared_w = int(m_bin.group(1))
        digits = m_bin.group(2).replace("_", "")
        if declared_w != len(digits):
          self._add(
              violations,
              waivers,
              "BINARY_LITERAL_WIDTH_MISMATCH",
              file_path,
              line_num,
              m_bin.start() + 1,
              f"Binary literal '{m_bin.group(0)}' width mismatch: declared"
              f" {declared_w} bits, but specified {len(digits)} digits."
              " Explicitly write all bits.",
              raw_lines[idx],
          )

    # Endianness: packed little-endian [MSB:LSB] (MSB >= LSB >= 0), unpacked big-endian [0:N-1]
    re_range = re.compile(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]")
    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      # Check packed dimension on wire/reg
      m_decl = re.search(r"\b(?:wire|reg|input|output)\s+(?:signed\s+)?\[\s*(\d+)\s*:\s*(\d+)\s*\]", line)
      if m_decl:
        left, right = int(m_decl.group(1)), int(m_decl.group(2))
        if left < right:
          self._add(
              violations,
              waivers,
              "PACKED_UNPACKED_ENDIANNESS",
              file_path,
              line_num,
              m_decl.start() + 1,
              f"Packed vector range '[{left}:{right}]' must be little-endian"
              f" '[{right}:{left}]'.",
              raw_lines[idx],
          )
      # Check unpacked dimension
      m_unp = re.search(r"\b(?:reg|wire)\s+.*?\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*;", line)
      if m_unp:
        left, right = int(m_unp.group(1)), int(m_unp.group(2))
        if left > right:
          self._add(
              violations,
              waivers,
              "PACKED_UNPACKED_ENDIANNESS",
              file_path,
              line_num,
              m_unp.start() + 1,
              f"Unpacked array range '[{left}:{right}]' must be big-endian"
              f" '[{right}:{left}]'.",
              raw_lines[idx],
          )

  def _check_procedural_blocks(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
      is_tb: bool,
  ) -> None:
    current_block: Optional[str] = None
    block_depth = 0
    in_always = False
    in_always_header = False
    always_header_buf = ""
    always_header_line = 1

    signed_signals: Set[str] = set()
    for l in masked_lines:
      m_sig = re.findall(r"\bsigned\b\s+(?:\[[^\]]+\]\s+)?([A-Za-z0-9_]+)", l)
      signed_signals.update(m_sig)

    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      is_assign = bool(RE_ASSIGN.search(line))

      # casex prohibited
      if re.search(r"\bcasex\b", line):
        self._add(
            violations,
            waivers,
            "CASEX_PROHIBITED",
            file_path,
            line_num,
            line.find("casex") + 1,
            "'casex' is strictly prohibited. Use 'case' or 'casez'.",
            raw_lines[idx],
        )

      # casez using 'z' or 'Z' in literal
      if re.search(r"\b\d+'[bB][01_]*[zZ][01_zZ]*\b", line):
        self._add(
            violations,
            waivers,
            "CASEZ_Z_LITERAL",
            file_path,
            line_num,
            1,
            "Wildcard literal uses 'z'/'Z'. Use '?' instead (e.g. 4'b??01).",
            raw_lines[idx],
        )

      # Task in RTL prohibited
      if not is_tb and re.match(r"^\s*task\b", line):
        self._add(
            violations,
            waivers,
            "TASK_IN_RTL_PROHIBITED",
            file_path,
            line_num,
            1,
            "Tasks are prohibited in synthesizable RTL. Use submodules instead.",
            raw_lines[idx],
        )

      # Function automatic in RTL
      if not is_tb and re.match(r"^\s*function\b", line):
        if not re.search(r"\bfunction\s+automatic\b", line):
          self._add(
              violations,
              waivers,
              "FUNCTION_NOT_AUTOMATIC",
              file_path,
              line_num,
              1,
              "Functions in synthesizable RTL must be declared 'function"
              " automatic'.",
              raw_lines[idx],
          )

      # Delay prohibited in RTL
      if not is_tb:
        delay_match = RE_DELAY.search(line)
        if delay_match:
          self._add(
              violations,
              waivers,
              "DELAY_PROHIBITED",
              file_path,
              line_num,
              delay_match.start() + 1,
              "#delay statements are prohibited in synthesizable RTL.",
              raw_lines[idx],
          )

      # Testbench plusarg test check
      if is_tb and "$test$plusargs" in line:
        self._add(
            violations,
            waivers,
            "TESTBENCH_PLUSARG_TEST",
            file_path,
            line_num,
            line.find("$test$plusargs") + 1,
            "$test$plusargs is prohibited; use $value$plusargs.",
            raw_lines[idx],
            severity=Severity.WARNING,
        )

      # Logical shift >> on signed signal
      if ">>" in line and ">>>" not in line:
        for s in signed_signals:
          if re.search(rf"\b{s}\s*>>", line):
            self._add(
                violations,
                waivers,
                "SIGNED_LOGICAL_RIGHT_SHIFT",
                file_path,
                line_num,
                line.find(">>") + 1,
                f"Logical right shift '>>' used on signed signal '{s}'. Use"
                " '>>>' to preserve sign.",
                raw_lines[idx],
            )

      # Parentheses around reduction operators preceded by another operator: e.g. ~&foo, !|bar
      m_red = re.search(r"(?:[~!&|^])\s*([&|^]|~[&|^])\s*[a-zA-Z_]", line)
      if m_red:
        self._add(
            violations,
            waivers,
            "REDUCTION_OPERATOR_PARENS",
            file_path,
            line_num,
            m_red.start() + 1,
            "Parentheses are required to isolate reduction operations preceded"
            " by another operator (e.g. '~(&foo)').",
            raw_lines[idx],
            severity=Severity.WARNING,
        )

      # Nested ternary without parentheses: ? ... : ... ? ... :
      if re.search(r"\?[^:]+:\s*[^;?]+?\?", line):
        self._add(
            violations,
            waivers,
            "NESTED_TERNARY_PARENS",
            file_path,
            line_num,
            1,
            "Nested ternary expressions must be enclosed in parentheses.",
            raw_lines[idx],
            severity=Severity.WARNING,
        )

      # Always header detection
      if not in_always_header:
        always_match = RE_ALWAYS.search(line)
        if always_match:
          sens = always_match.group(1).strip()
          in_always = True
          if "*" in sens:
            current_block = "combinational"
          elif "posedge" in sens or "negedge" in sens:
            current_block = "sequential"
          else:
            current_block = "combinational"
            self._add(
                violations,
                waivers,
                "MANUAL_SENSITIVITY_LIST",
                file_path,
                line_num,
                always_match.start() + 1,
                "Manual sensitivity list in combinational block. Use 'always"
                " @*'.",
                raw_lines[idx],
            )
        elif re.search(r"\balways\s*@", line):
          in_always_header = True
          always_header_buf = line
          always_header_line = line_num
      else:
        always_header_buf += " " + line
        if ")" in line:
          in_always_header = False
          in_always = True
          m_sens = re.search(
              r"\balways\s*@\s*(\([^)]*\)|\*)", always_header_buf
          )
          if m_sens:
            sens = m_sens.group(1).strip()
            if "*" in sens:
              current_block = "combinational"
            elif "posedge" in sens or "negedge" in sens:
              current_block = "sequential"
            else:
              current_block = "combinational"
              self._add(
                  violations,
                  waivers,
                  "MANUAL_SENSITIVITY_LIST",
                  file_path,
                  always_header_line,
                  1,
                  "Manual sensitivity list in combinational block. Use 'always"
                  " @*'.",
                  raw_lines[always_header_line - 1],
              )

      begins = len(re.findall(r"\bbegin\b", line))
      ends = len(re.findall(r"\bend\b", line))
      if in_always:
        block_depth += begins - ends

      if current_block == "sequential" and not is_assign:
        red_clk = RE_REDUNDANT_CLK.search(line)
        if red_clk:
          self._add(
              violations,
              waivers,
              "ANTI_PATTERN_REDUNDANT_CLOCK_CHECK",
              file_path,
              line_num,
              red_clk.start() + 1,
              "Redundant 'else if (clk)' check inside edge-triggered always"
              " block.",
              raw_lines[idx],
          )

        if not re.search(r"\bfor\s*\(", line):
          blk = RE_BLOCKING.search(line)
          if blk and not re.search(r"\b(?:if|while)\s*\(.*=", line):
            if re.search(
                r"(?:^\s*|\b(?:begin|else)\s+)(?:[a-zA-Z_0-9]+(?:\s*\[[^\]]+\])?|\{[^}]+\})\s*=(?![=])",
                line,
            ):
              self._add(
                  violations,
                  waivers,
                  "SEQUENTIAL_BLOCKING_ASSIGNMENT",
                  file_path,
                  line_num,
                  blk.start() + 1,
                  "Blocking assignment (=) inside sequential always block. Use"
                  " non-blocking (<=).",
                  raw_lines[idx],
              )

      elif current_block == "combinational" and not is_assign:
        if not re.search(r"\b(?:if|while)\s*\(.*<=", line):
          nonblk = re.search(
              r"(?:^\s*|\b(?:begin|else)\s+)(?:[a-zA-Z_0-9]+(?:\s*\[[^\]]+\])?|\{[^}]+\})\s*<=(?![=])",
              line,
          )
          if nonblk:
            self._add(
                violations,
                waivers,
                "COMBINATIONAL_NONBLOCKING_ASSIGNMENT",
                file_path,
                line_num,
                nonblk.start() + 1,
                "Non-blocking assignment (<=) inside combinational always"
                " block. Use blocking (=).",
                raw_lines[idx],
            )

      if in_always:
        if block_depth <= 0 and (
            ends > 0 or (block_depth == 0 and begins == 0 and ";" in line)
        ):
          in_always = False
          current_block = None
          block_depth = 0

      if "endmodule" in line:
        current_block = None
        in_always = False
        in_always_header = False
        block_depth = 0

  def _check_instantiations_and_generate(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
      is_tb: bool,
  ) -> None:
    source_text = "\n".join(masked_lines)

    # Defparam prohibited
    for idx, line in enumerate(masked_lines):
      if re.search(r"\bdefparam\b", line):
        self._add(
            violations,
            waivers,
            "DEFPARAM_PROHIBITED",
            file_path,
            idx + 1,
            line.find("defparam") + 1,
            "'defparam' is prohibited. Use ANSI parameter port overrides"
            " #(.Param(val)).",
            raw_lines[idx],
        )

    # Generate block labels (must start with gen_)
    for idx, line in enumerate(masked_lines):
      line_num = idx + 1
      # Check generate begin blocks
      m_gen_begin = re.search(r"\bbegin\s*(?::\s*([a-zA-Z0-9_]+))?", line)
      if "generate" in source_text:
        # Check if line is within a generate block
        if re.search(r"\b(?:for|if|else)\b.*?\bbegin\b", line) or (
            m_gen_begin and idx > 0 and re.search(r"\b(?:for|if|else)\b", masked_lines[idx - 1])
        ):
          # Look for label
          m_label = re.search(r"\bbegin\s*:\s*([a-zA-Z0-9_]+)", line)
          if not m_label and idx < len(masked_lines) - 1:
            m_label = re.search(r"^\s*:\s*([a-zA-Z0-9_]+)", masked_lines[idx + 1])
          if m_label:
            lbl = m_label.group(1)
            if not lbl.startswith("gen_"):
              self._add(
                  violations,
                  waivers,
                  "GENERATE_BLOCK_LABEL",
                  file_path,
                  line_num,
                  1,
                  f"Generate block label '{lbl}' must start with 'gen_'"
                  f" (e.g. 'gen_{lbl}').",
                  raw_lines[idx],
              )

    # Submodule instantiations
    for match in RE_INST.finditer(source_text):
      mod_type = match.group(1)
      param_overrides = (match.group(2) or "").strip()
      inst_name = match.group(3)
      port_list = match.group(4).strip()

      if mod_type in RESERVED_KEYWORDS or inst_name in RESERVED_KEYWORDS:
        continue

      line_num = source_text[: match.start()].count("\n") + 1
      snippet = raw_lines[line_num - 1] if line_num <= len(raw_lines) else ""

      # Recursive instantiation check
      if mod_type == file_path.stem and not is_tb:
        self._add(
            violations,
            waivers,
            "RECURSIVE_INSTANTIATION",
            file_path,
            line_num,
            1,
            f"Module '{mod_type}' instantiates itself recursively.",
            snippet,
        )

      # Instance naming convention: must start with module name, or dut/uut in TB
      valid_name = inst_name.startswith(mod_type) or inst_name.startswith("u_")
      if is_tb:
        valid_name = valid_name or inst_name in (
            "dut",
            "uut",
            f"{mod_type}_dut",
            f"{mod_type}_uut",
        )

      if not valid_name and mod_type not in PRIMITIVE_GATES:
        self._add(
            violations,
            waivers,
            "INSTANCE_NAME_CONVENTION",
            file_path,
            line_num,
            1,
            f"Instance name '{inst_name}' must start with module name"
            f" '{mod_type}' (e.g. '{mod_type}_0' or '{mod_type}_dut').",
            snippet,
        )

      # Positional parameter overrides
      if param_overrides and not re.search(r"\.\s*[a-zA-Z0-9_]+\s*\(", param_overrides):
        self._add(
            violations,
            waivers,
            "POSITIONAL_PARAM_INSTANTIATION",
            file_path,
            line_num,
            1,
            f"Positional parameter override '#({param_overrides})' in"
            f" '{inst_name}'. Named parameter binding (#(.Param(val))) is"
            " required.",
            snippet,
        )

      # Positional port binding
      if (
          mod_type not in PRIMITIVE_GATES
          and port_list
          and not re.search(r"\.\s*[a-zA-Z_0-9]+\s*\(", port_list)
      ):
        self._add(
            violations,
            waivers,
            "POSITIONAL_INSTANTIATION",
            file_path,
            line_num,
            1,
            f"Positional port instantiation in '{inst_name}'. Named port"
            " binding (.port(sig)) is required.",
            snippet,
        )

      # Floating input ports: .in_port()
      for m_conn in re.finditer(r"\.\s*([a-zA-Z0-9_]+)\s*\(\s*\)", port_list):
        p_name = m_conn.group(1)
        if any(
            p_name.startswith(p)
            for p in ("in", "data_in", "clk", "rst", "enable", "req", "valid")
        ):
          self._add(
              violations,
              waivers,
              "FLOATING_INPUT_PORT",
              file_path,
              line_num,
              1,
              f"Input port '.{p_name}()' left floating in instance"
              f" '{inst_name}'. Tie off explicitly.",
              snippet,
          )

  def _check_cyclone_v_invariants(
      self,
      file_path: Path,
      masked_lines: List[str],
      raw_lines: List[str],
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
  ) -> None:
    mem_arrays = {
        m.group(1)
        for line in masked_lines
        for m in [RE_MEM_DECL.search(line)]
        if m
    }
    stem_lower = file_path.stem.lower()
    is_top = (
        stem_lower == "top"
        or stem_lower.endswith("_top")
        or stem_lower.startswith("top_")
        or any(re.search(r"\binout\b", l) for l in masked_lines)
    )

    in_comb = False
    for idx, line in enumerate(masked_lines):
      line_num = idx + 1

      if re.search(r"\balways\s*@\s*(\*|\(\s*\*\s*\))", line):
        in_comb = True
      elif re.search(r"\balways\s*@\s*\(", line):
        in_comb = False
      if "endmodule" in line:
        in_comb = False

      for mem in mem_arrays:
        is_async_assign = bool(
            re.search(rf"\bassign\s+[^=]+=\s*{mem}\s*\[", line)
        )
        is_async_comb = in_comb and bool(
            re.search(rf"\b\w+\s*=\s*{mem}\s*\[", line)
        )
        if is_async_assign or is_async_comb:
          self._add(
              violations,
              waivers,
              "M10K_ASYNC_READ_PROHIBITED",
              file_path,
              line_num,
              1,
              f"Asynchronous read on memory array '{mem}'. Cyclone V M10K"
              " blocks require synchronous read ('always @(posedge clk) q <="
              f" {mem}[addr]').",
              raw_lines[idx],
          )

      gated_clk = RE_GATED_CLK.search(line)
      if gated_clk:
        self._add(
            violations,
            waivers,
            "CLOCK_GATING_LOGIC_PROHIBITED",
            file_path,
            line_num,
            gated_clk.start() + 1,
            "Logic-gated clock detected (clk & en). Use dedicated register"
            " clock enables.",
            raw_lines[idx],
        )

      tristate = RE_TRISTATE.search(line)
      if tristate and not is_top:
        self._add(
            violations,
            waivers,
            "INTERNAL_TRISTATE_PROHIBITED",
            file_path,
            line_num,
            tristate.start() + 1,
            "Internal tri-state (1'bz) prohibited in Cyclone V core logic. Use"
            " multiplexers.",
            raw_lines[idx],
        )

  def _run_iverilog_check(
      self,
      file_path: Path,
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
  ) -> None:
    file_dir = str(file_path.parent)
    cmd = [
        "iverilog",
        "-Wall",
        "-g2001",
        "-tnull",
        "-y",
        file_dir,
        "-I",
        file_dir,
        str(file_path),
    ]
    try:
      res = subprocess.run(
          cmd,
          stdout=subprocess.PIPE,
          stderr=subprocess.PIPE,
          text=True,
          timeout=10,
      )
      if res.returncode != 0 or res.stderr:
        for err_line in res.stderr.splitlines():
          err_line = err_line.strip()
          if not err_line:
            continue
          m = re.match(
              r"^([^:]+):(\d+):\s*(error|warning)?\s*(.*)$",
              err_line,
              re.IGNORECASE,
          )
          if m:
            _, line_str, err_type, msg = m.groups()
            is_note = msg.startswith("...") or (err_type or "").startswith("...")
            is_warn = (err_type or "").lower() == "warning" or is_note
            self._add(
                violations,
                waivers,
                (
                    "IVERILOG_COMPILER_WARNING"
                    if is_warn
                    else "IVERILOG_COMPILER_ERROR"
                ),
                file_path,
                int(line_str),
                1,
                f"[iverilog] {msg or err_line}",
                severity=Severity.WARNING if is_warn else Severity.ERROR,
            )
          else:
            is_note = (
                err_line.startswith("...") or "timescale" in err_line.lower()
            )
            self._add(
                violations,
                waivers,
                (
                    "IVERILOG_COMPILER_WARNING"
                    if is_note
                    else "IVERILOG_COMPILER_ERROR"
                ),
                file_path,
                0,
                0,
                f"[iverilog] {err_line}",
                severity=Severity.WARNING if is_note else Severity.ERROR,
            )
    except Exception as e:
      self._add(
          violations,
          waivers,
          "IVERILOG_EXEC_ERROR",
          file_path,
          0,
          0,
          f"Could not execute iverilog: {e}",
          severity=Severity.WARNING,
      )

  def _run_verilator_check(
      self,
      file_path: Path,
      waivers: Dict[int, Set[str]],
      violations: List[LintViolation],
  ) -> None:
    file_dir = str(file_path.parent)
    cmd = [
        "verilator",
        "--lint-only",
        "-Wall",
        "+1364-2001ext+v",
        "-I" + file_dir,
        "-y",
        file_dir,
        "-Wno-PINCONNECTEMPTY",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-EOFNEWLINE",
        "-Werror-LATCH",
        "-Werror-CASEINCOMPLETE",
        "-Werror-COMBDLY",
        str(file_path),
    ]
    try:
      res = subprocess.run(
          cmd,
          stdout=subprocess.PIPE,
          stderr=subprocess.PIPE,
          text=True,
          timeout=10,
      )
      if res.stderr:
        for line in res.stderr.splitlines():
          line = line.strip()
          if not line or line.startswith("%"):
            m = re.match(
                r"^%(Error|Warning)(?:-([A-Z0-9_]+))?:\s*([^:]+):(\d+):(?:\d+:)?\s*(.*)$",
                line,
            )
            if m:
              sev, rule, _, line_no, msg = m.groups()
              rule_name = rule or "LINT"
              is_err = sev == "Error" or rule_name in FATAL_VERILATOR_RULES
              self._add(
                  violations,
                  waivers,
                  f"VERILATOR_{rule_name}",
                  file_path,
                  int(line_no),
                  1,
                  f"[verilator] {msg}",
                  severity=Severity.ERROR if is_err else Severity.WARNING,
              )
    except Exception:
      pass


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
      description=(
          "Strict Verilog-2001 & Cyclone V RTL Linter (Google Style Guide"
          " Aligned)"
      ),
      formatter_class=argparse.ArgumentDefaultsHelpFormatter,
  )
  parser.add_argument(
      "targets", nargs="*", default=["."], help="Files or directories to lint"
  )
  parser.add_argument(
      "--exclude",
      action="append",
      default=[],
      help="Patterns or directory names to exclude",
  )
  parser.add_argument(
      "--no-iverilog",
      action="store_true",
      help="Disable Icarus Verilog elaboration check",
  )
  parser.add_argument(
      "--no-verilator",
      action="store_true",
      help="Disable Verilator static analysis check",
  )
  parser.add_argument(
      "--strict",
      action="store_true",
      default=True,
      help="Fail (exit 1) on errors",
  )
  return parser.parse_args()


def main() -> int:
  args = parse_args()
  linter = VerilogLinter(
      run_iverilog=not args.no_iverilog,
      run_verilator=not args.no_verilator,
  )

  targets: List[Path] = []
  excludes = [re.compile(re.escape(exc)) for exc in args.exclude]
  valid_extensions = {".v", ".vh", ".sv", ".svh"}

  for target in args.targets:
    t_path = Path(target).resolve()
    if t_path.is_file() and t_path.suffix in valid_extensions:
      targets.append(t_path)
    elif t_path.is_dir():
      targets.extend(
          p for p in t_path.rglob("*") if p.suffix in valid_extensions
      )

  filtered_files = sorted(
      {f for f in targets if not any(exc.search(str(f)) for exc in excludes)}
  )

  if not filtered_files:
    print("No Verilog files found to lint.")
    return 0

  print(
      f"\033[1mScanning {len(filtered_files)} file(s) for Verilog-2001 &"
      " Cyclone V compliance...\033[0m\n"
  )

  total_errors = 0
  total_warnings = 0

  for file_path in filtered_files:
    violations = linter.lint_file(file_path)
    errors = [v for v in violations if v.severity == Severity.ERROR]
    warnings = [v for v in violations if v.severity == Severity.WARNING]
    total_errors += len(errors)
    total_warnings += len(warnings)

    for v in violations:
      print(v)
    if violations:
      print()

  print("-" * 60)
  status_color = "\033[92m" if total_errors == 0 else "\033[91m"
  status_text = "PASS" if total_errors == 0 else "FAIL"
  print(
      f"Result: {status_color}\033[1m{status_text}\033[0m ({total_errors}"
      f" errors, {total_warnings} warnings)"
  )

  return 1 if total_errors > 0 and args.strict else 0


if __name__ == "__main__":
  sys.exit(main())
