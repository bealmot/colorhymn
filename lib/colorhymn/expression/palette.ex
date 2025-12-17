defmodule Colorhymn.Expression.Palette do
  @moduledoc """
  Dynamic color palette generation based on log perception.

  The palette adapts to the mood/temperature of the log and is modulated
  by perception dimensions like burstiness, stability, and complexity.
  """

  alias Colorhymn.Expression.Color

  defstruct [
    # Core semantic colors
    :background,
    :foreground,
    :muted,
    :accent,

    # Severity spectrum
    :success,
    :info,
    :warning,
    :error,
    :critical,

    # Semantic token colors
    :timestamp,
    :ip_address,
    :domain,
    :path,
    :number,
    :string,
    :keyword,
    :identifier,
    :operator,
    :bracket,
    :comment,
    :uuid,
    :log_level,

    # State colors
    :state_positive,
    :state_negative,
    :state_neutral,
    :state_transition,

    # Mood metadata
    :mood,
    :warmth,        # -1 (cool) to +1 (warm)
    :saturation,    # 0-1 overall saturation level
    :contrast       # 0-1 contrast level
  ]

  @type t :: %__MODULE__{}

  # ============================================================================
  # Base Palettes by Mood
  # ============================================================================

  @base_palettes %{
    calm: %{
      background: "#1a1e24",
      foreground: "#a8b5c4",
      muted: "#5a6a7a",
      accent: "#6b9fce",
      success: "#5a9e6b",
      info: "#6b8cae",
      warning: "#b09050",
      error: "#b06060",
      critical: "#a04545",
      warmth: -0.2,
      saturation: 0.4,
      contrast: 0.6
    },
    neutral: %{
      background: "#1e2127",
      foreground: "#b0b8c4",
      muted: "#6a7280",
      accent: "#7a9ab8",
      success: "#6a9e70",
      info: "#7a8fa8",
      warning: "#b8a060",
      error: "#b87070",
      critical: "#a85050",
      warmth: 0.0,
      saturation: 0.5,
      contrast: 0.65
    },
    uneasy: %{
      background: "#1f2024",
      foreground: "#b8b0a8",
      muted: "#7a7068",
      accent: "#c49a6a",
      success: "#7a9e68",
      info: "#8a9098",
      warning: "#c4a050",
      error: "#c07060",
      critical: "#b05045",
      warmth: 0.3,
      saturation: 0.55,
      contrast: 0.7
    },
    troubled: %{
      background: "#211e1c",
      foreground: "#c4b8a8",
      muted: "#8a7868",
      accent: "#d4904a",
      success: "#7a9a60",
      info: "#9a9088",
      warning: "#d49030",
      error: "#d06050",
      critical: "#c04040",
      warmth: 0.5,
      saturation: 0.65,
      contrast: 0.75
    },
    critical: %{
      background: "#241a1a",
      foreground: "#d4c0b8",
      muted: "#9a7a70",
      accent: "#e07040",
      success: "#6a9050",
      info: "#a08878",
      warning: "#e08020",
      error: "#e05040",
      critical: "#d03030",
      warmth: 0.7,
      saturation: 0.75,
      contrast: 0.85
    }
  }

  # ============================================================================
  # Palette Generation
  # ============================================================================

  @doc """
  Generate a palette based on mood and perception.
  """
  def generate(mood, perception \\ %{}) do
    base = Map.get(@base_palettes, mood, @base_palettes.neutral)

    # Extract perception modifiers with defaults
    burstiness = Map.get(perception, :burstiness, 0.5)
    _regularity = Map.get(perception, :regularity, 0.5)
    stability = Map.get(perception, :stability, 0.5)
    _complexity = Map.get(perception, :cognitive_load, 0.5)
    drift = Map.get(perception, :drift, 0.0)

    # Calculate derived values
    saturation_mod = (burstiness - 0.5) * 0.3  # Bursty = more saturated
    contrast_mod = (1 - stability) * 0.2       # Unstable = more contrast
    warmth_shift = drift * 0.2                 # Negative drift = cooler

    effective_saturation = clamp(base.saturation + saturation_mod, 0.2, 0.9)
    effective_contrast = clamp(base.contrast + contrast_mod, 0.4, 0.95)
    effective_warmth = clamp(base.warmth + warmth_shift, -0.8, 0.8)

    %__MODULE__{
      # Core colors
      background: Color.from_hex(base.background),
      foreground: apply_modifiers(Color.from_hex(base.foreground), effective_saturation, effective_warmth),
      muted: apply_modifiers(Color.from_hex(base.muted), effective_saturation * 0.5, effective_warmth),
      accent: apply_modifiers(Color.from_hex(base.accent), effective_saturation, effective_warmth),

      # Severity spectrum
      success: apply_modifiers(Color.from_hex(base.success), effective_saturation, effective_warmth * 0.5),
      info: apply_modifiers(Color.from_hex(base.info), effective_saturation, effective_warmth),
      warning: apply_modifiers(Color.from_hex(base.warning), effective_saturation * 1.1, effective_warmth),
      error: apply_modifiers(Color.from_hex(base.error), effective_saturation * 1.2, effective_warmth),
      critical: apply_modifiers(Color.from_hex(base.critical), effective_saturation * 1.3, effective_warmth),

      # Token colors (derived from base)
      timestamp: derive_token_color(base, :timestamp, effective_saturation, effective_warmth),
      ip_address: derive_token_color(base, :ip_address, effective_saturation, effective_warmth),
      domain: derive_token_color(base, :domain, effective_saturation, effective_warmth),
      path: derive_token_color(base, :path, effective_saturation, effective_warmth),
      number: derive_token_color(base, :number, effective_saturation, effective_warmth),
      string: derive_token_color(base, :string, effective_saturation, effective_warmth),
      keyword: derive_token_color(base, :keyword, effective_saturation, effective_warmth),
      identifier: derive_token_color(base, :identifier, effective_saturation, effective_warmth),
      operator: derive_token_color(base, :operator, effective_saturation, effective_warmth),
      bracket: derive_token_color(base, :bracket, effective_saturation, effective_warmth),
      comment: derive_token_color(base, :comment, effective_saturation * 0.3, effective_warmth),
      uuid: derive_token_color(base, :uuid, effective_saturation, effective_warmth),
      log_level: derive_token_color(base, :log_level, effective_saturation, effective_warmth),

      # State colors
      state_positive: apply_modifiers(Color.from_hex(base.success), effective_saturation, 0),
      state_negative: apply_modifiers(Color.from_hex(base.error), effective_saturation, 0),
      state_neutral: apply_modifiers(Color.from_hex(base.muted), effective_saturation * 0.5, 0),
      state_transition: apply_modifiers(Color.from_hex(base.accent), effective_saturation, 0),

      # Metadata
      mood: mood,
      warmth: effective_warmth,
      saturation: effective_saturation,
      contrast: effective_contrast
    }
  end

  # ============================================================================
  # Token Color Derivation
  # ============================================================================

  # Base hue offsets for different token types (from accent color)
  @token_hues %{
    timestamp: -30,      # Cooler, blue-ish
    ip_address: -15,     # Slightly cooler
    domain: 0,           # Accent color
    path: -45,           # More blue
    number: 30,          # Warmer, orange-ish
    string: 60,          # Yellow-green
    keyword: 15,         # Slightly warm
    identifier: -10,     # Near accent
    operator: 0,         # Neutral
    bracket: -20,        # Cool
    comment: 0,          # Muted accent
    uuid: -60,           # Purple-ish
    log_level: 20        # Warm
  }

  defp derive_token_color(base, token_type, saturation, warmth) do
    accent = Color.from_hex(base.accent)
    hue_offset = Map.get(@token_hues, token_type, 0)

    # Apply warmth as additional hue shift (warm = toward red/orange)
    warmth_hue = warmth * 15

    accent
    |> Color.rotate_hue(hue_offset + warmth_hue)
    |> Color.set_saturation(saturation * token_saturation_scale(token_type))
    |> adjust_token_lightness(token_type)
  end

  defp token_saturation_scale(:comment), do: 0.3
  defp token_saturation_scale(:bracket), do: 0.5
  defp token_saturation_scale(:operator), do: 0.6
  defp token_saturation_scale(:muted), do: 0.4
  defp token_saturation_scale(_), do: 1.0

  defp adjust_token_lightness(color, :comment), do: Color.set_lightness(color, 0.4)
  defp adjust_token_lightness(color, :bracket), do: Color.set_lightness(color, 0.5)
  defp adjust_token_lightness(color, _), do: color

  # ============================================================================
  # Color Modifiers
  # ============================================================================

  defp apply_modifiers(color, saturation, warmth) do
    color
    |> Color.set_saturation(color.s * saturation / 0.5)  # Scale relative to base 0.5
    |> apply_warmth(warmth)
  end

  defp apply_warmth(color, warmth) when warmth > 0 do
    # Shift toward warm (red/orange, hue 0-60)
    shift = warmth * 20
    Color.rotate_hue(color, -shift)  # Negative because we want toward 0
  end

  defp apply_warmth(color, warmth) when warmth < 0 do
    # Shift toward cool (blue, hue 200-240)
    shift = abs(warmth) * 20
    Color.rotate_hue(color, shift)  # Positive toward blue
  end

  defp apply_warmth(color, _), do: color

  # ============================================================================
  # Output Formats
  # ============================================================================

  @doc "Export palette as hex color map"
  def to_hex_map(%__MODULE__{} = palette) do
    palette
    |> Map.from_struct()
    |> Enum.filter(fn {_k, v} -> is_struct(v, Color) end)
    |> Enum.map(fn {k, v} -> {k, Color.to_hex(v)} end)
    |> Map.new()
  end

  @doc "Export palette as HSL map (for JS)"
  def to_hsl_map(%__MODULE__{} = palette) do
    palette
    |> Map.from_struct()
    |> Enum.filter(fn {_k, v} -> is_struct(v, Color) end)
    |> Enum.map(fn {k, v} -> {k, Color.to_hsl_map(v)} end)
    |> Map.new()
  end

  @doc "Export as CSS custom properties"
  def to_css_vars(%__MODULE__{} = palette) do
    palette
    |> Map.from_struct()
    |> Enum.filter(fn {_k, v} -> is_struct(v, Color) end)
    |> Enum.map(fn {k, v} ->
      name = k |> Atom.to_string() |> String.replace("_", "-")
      "  --color-#{name}: #{Color.to_hex(v)};"
    end)
    |> Enum.join("\n")
    |> then(&":root {\n#{&1}\n}")
  end

  @doc "Get color for a specific token type"
  def color_for(%__MODULE__{} = palette, token_type) do
    Map.get(palette, token_type, palette.foreground)
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
