# Colorhymn

A perception-driven log visualization system that transforms logs into dynamically colored output based on their semantic "temperature" — from calm blue to critical red.

## Overview

Colorhymn analyzes logs across multiple dimensions to understand their mood, then generates contextually appropriate color palettes that reflect the emotional and semantic content. It goes beyond simple syntax highlighting by understanding logs semantically and expressing that understanding through adaptive color schemes.

**Core Philosophy:** Logs tell stories about system state and behavior. Colors should communicate the mood and severity of that story intuitively, making patterns and anomalies visually apparent.

## Installation

```bash
# Clone the repository
git clone https://github.com/yourorg/colorhymn.git
cd colorhymn

# Build the escript binary
mix escript.build

# Optional: move to PATH
sudo mv colorhymn /usr/local/bin/
```

**Requirements:** Elixir 1.19+ (no external dependencies)

## Quick Start

```bash
# Basic usage - colorize a log file
colorhymn app.log

# Read from stdin
cat app.log | colorhymn --stdin

# Show temperature flow through the file
colorhymn --flow app.log

# Export to HTML
colorhymn --format=html app.log > output.html
```

## Usage

```
colorhymn [OPTIONS] <file>
colorhymn --stdin [OPTIONS]
```

### Output Formats

| Option | Description |
|--------|-------------|
| `--format=ansi` | Terminal output with ANSI colors (default) |
| `--format=json` | Structured JSON with tokens and colors |
| `--format=html` | HTML with inline CSS styling |

### Analysis Modes

| Option | Description |
|--------|-------------|
| `--flow` | Per-line temperature analysis showing mood evolution |
| `--regions` | Structural region analysis (requires `--flow`) |

### Color Customization

| Option | Range | Description |
|--------|-------|-------------|
| `--tint=N` | -180 to 180 | Hue offset in degrees |
| `--sat=N` | 0.0+ | Saturation multiplier |
| `--contrast=N` | 0.0+ | Contrast multiplier |
| `--intensity=N` | 0.5 to 3.0 | Dither intensity |
| `--dither` | — | Enable error-diffusion dithering for organic color flow |

### Themes

| Theme | Description |
|-------|-------------|
| `rainbow` | Full spectrum (default) |
| `monochrome` | Single hue, varying lightness/saturation |
| `temp_lock_warm` | Warm spectrum only (reds/oranges/yellows) |
| `temp_lock_cool` | Cool spectrum only (blues/cyans/greens) |
| `terminal` | ANSI 16-color palette |
| `high_contrast` | 2-3 colors, stark differentiation |
| `semantic` | Only errors/warnings/success colored |

```bash
colorhymn --theme=terminal app.log
colorhymn --theme=high_contrast --dither error.log
```

### Other Options

| Option | Description |
|--------|-------------|
| `--no-line-nums` | Hide line numbers |

## Examples

### Basic Visualization

```bash
# Terminal output with default settings
colorhymn /var/log/syslog

# Warmer color palette with increased saturation
colorhymn --tint=30 --sat=1.3 app.log
```

### Flow Analysis

```bash
# See how log temperature changes over time
colorhymn --flow app.log

# With structural region breakdown
colorhymn --flow --regions vpn.log
```

### Export and Processing

```bash
# Generate HTML report
colorhymn --format=html --flow app.log > report.html

# JSON output for programmatic analysis
colorhymn --format=json app.log | jq '.lines[] | select(.temperature > 0.7)'
```

### Terminal Compatibility

```bash
# Safe for all terminals (16 colors)
colorhymn --theme=terminal legacy.log

# High contrast for accessibility
colorhymn --theme=high_contrast --contrast=1.5 app.log
```

## How It Works

### Pipeline Architecture

```
Input → Perception → Tokenization → Structure → Expression → Output
```

1. **Perception (FirstSight)** — Rapidly analyzes log type, format, and temperature
2. **Tokenization** — Breaks lines into 40+ semantic token types
3. **Structure** — Identifies regions (timestamp, log level, message) and groups (stack traces, tables)
4. **Expression** — Transforms perception into colors via palette generation
5. **Output** — Renders in ANSI, JSON, or HTML format

### Temperature Model

Temperature is a continuous score from 0.0 (calm) to 1.0 (critical):

| Score | Mood | Visual Character |
|-------|------|------------------|
| 0.0–0.15 | Calm | Cool blues, low saturation |
| 0.15–0.30 | Cool | Neutral cyans |
| 0.30–0.45 | Neutral | Teal tones |
| 0.45–0.60 | Uneasy | Yellow-greens, rising warmth |
| 0.60–0.80 | Troubled | Oranges, high saturation |
| 0.80–1.0 | Critical | Reds, maximum contrast |

Temperature is calculated from:
- Error signals (ERROR, FATAL, HTTP 5xx, exceptions)
- Warning signals (WARNING, deprecated, slow, timeout)
- Success signals (INFO, SUCCESS, HTTP 2xx, connected)

### Multi-Dimensional Perception

Beyond temperature, Colorhymn analyzes 25+ dimensions across 8 categories:

- **Temporal** — burstiness, regularity, acceleration
- **Structural** — line variance, nesting depth, whitespace ratio
- **Density** — token density, information density, noise ratio
- **Repetition** — uniqueness, template ratio, pattern recurrence
- **Dialogue** — request/response balance, turn frequency
- **Volatility** — field variance, state churn, drift, stability
- **Complexity** — bracket depth, parse difficulty, cognitive load
- **Network** — session coherence, connection success, handshake completeness

These dimensions modulate color generation: burstiness affects saturation, stability affects contrast, drift affects warmth.

### Token Types

Colorhymn recognizes 40+ semantic token types:

| Category | Types |
|----------|-------|
| Temporal | timestamp |
| Network | ip_address, ipv6_address, domain, url, cidr, port, mac_address, protocol, interface, http_method, http_status |
| Identifiers | uuid, email, path |
| Values | number, hex_number, string |
| Structure | keyword, key, identifier, operator, bracket |
| Log-specific | log_level, event_id, sid, registry_key, hresult |
| VPN | vpn_keyword, spi |

### Supported Log Types

Colorhymn automatically detects:

- VPN/IPSec logs
- Authentication logs
- Network logs and packet captures
- Windows event logs
- Application logs (general)
- Structured formats (JSON, key-value, CSV)

## Architecture

```
lib/colorhymn/
├── cli.ex                    # CLI entry point
├── first_sight.ex            # Initial perception & type detection
├── perception.ex             # Multi-dimensional analysis
│   ├── temporal.ex
│   ├── structural.ex
│   ├── density.ex
│   ├── repetition.ex
│   ├── dialogue.ex
│   ├── volatility.ex
│   ├── complexity.ex
│   └── network.ex
├── tokenizer.ex              # Semantic tokenization
├── structure.ex              # Region & group detection
│   ├── region_detector.ex
│   └── group_detector.ex
├── flow.ex                   # Windowed temperature analysis
├── region_temperature.ex     # Per-region temperature
└── expression/
    ├── palette.ex            # Color palette generation
    ├── color.ex              # HSL color model
    ├── theme.ex              # Theme constraints
    └── dither.ex             # Error-diffusion dithering
```

## License

MIT
