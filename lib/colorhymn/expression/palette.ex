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
  # Temperature Color Stops (continuous interpolation)
  # ============================================================================
  #
  # Instead of 5 discrete palettes, we define color stops at specific
  # temperature values. Colors are interpolated between stops for any
  # temperature_score in 0.0 to 1.0 range.
  #
  # Each stop defines the base hue, saturation, warmth for that temperature.

  @temperature_stops [
    # temp    hue     sat   contrast  warmth   description
    {0.0,   200,    0.35,   0.55,    -0.3},   # Icy blue - very calm
    {0.15,  195,    0.40,   0.60,    -0.2},   # Cool cyan
    {0.30,  190,    0.45,   0.63,    -0.1},   # Neutral blue
    {0.40,  180,    0.50,   0.65,     0.0},   # True neutral (teal)
    {0.50,  160,    0.55,   0.68,     0.15},  # Shifting warm (yellow-green)
    {0.60,  120,    0.60,   0.72,     0.30},  # Uneasy (yellow)
    {0.70,   60,    0.68,   0.78,     0.50},  # Troubled (orange)
    {0.80,   30,    0.75,   0.82,     0.65},  # Hot (red-orange)
    {0.90,   10,    0.82,   0.88,     0.75},  # Critical (red)
    {1.0,    0,    0.90,   0.95,     0.85}   # Maximum heat (pure red)
  ]

  # Background colors shift from cool blue-gray to warm red-gray
  @background_stops [
    {0.0,  "#181c22"},  # Cool dark blue
    {0.3,  "#1a1e24"},  # Neutral dark
    {0.5,  "#1e2020"},  # Transitional
    {0.7,  "#211e1c"},  # Warm dark
    {1.0,  "#261818"}   # Hot dark red
  ]

  # Legacy palettes kept for reference/backward compatibility
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
  Generate a palette based on temperature score and perception.

  temperature_score: 0.0 (icy calm) to 1.0 (critical hot)
  perception: map of perception dimensions for modulation
  """
  def generate(temperature_score, perception \\ %{})

  # Handle legacy atom-based mood (for backward compatibility)
  def generate(mood, perception) when is_atom(mood) do
    score = case mood do
      :calm -> 0.15
      :neutral -> 0.40
      :uneasy -> 0.55
      :troubled -> 0.70
      :critical -> 0.90
      _ -> 0.40
    end
    generate(score, perception)
  end

  # Main generation from continuous temperature score
  def generate(temperature_score, perception) when is_number(temperature_score) do
    # Clamp to valid range
    temp = clamp(temperature_score, 0.0, 1.0)

    # Interpolate base parameters from temperature stops
    {base_hue, base_sat, base_contrast, base_warmth} = interpolate_temperature(temp)

    # Extract perception modifiers with defaults
    burstiness = Map.get(perception, :burstiness, 0.5)
    stability = Map.get(perception, :stability, 0.5)
    drift = Map.get(perception, :drift, 0.0)
    hue_offset = Map.get(perception, :hue_offset, 0.0)  # Tint: shift all hues
    sat_mult = Map.get(perception, :sat_mult, 1.0)      # Saturation multiplier
    contrast_mult = Map.get(perception, :contrast_mult, 1.0)  # Contrast multiplier

    # Calculate derived values
    saturation_mod = (burstiness - 0.5) * 0.3  # Bursty = more saturated
    contrast_mod = (1 - stability) * 0.2       # Unstable = more contrast
    warmth_shift = drift * 0.2                 # Negative drift = cooler

    # Apply base modifiers then user multipliers
    effective_saturation = clamp((base_sat + saturation_mod) * sat_mult, 0.1, 0.98)
    effective_contrast = clamp((base_contrast + contrast_mod) * contrast_mult, 0.3, 0.99)
    effective_warmth = clamp(base_warmth + warmth_shift, -0.5, 0.9)

    # Apply hue offset (tint) to base hue
    tinted_hue = normalize_hue(base_hue + hue_offset)

    # Interpolate background color (also tinted)
    background = interpolate_background(temp, hue_offset)

    # Generate base accent color from tinted hue
    accent = Color.new(tinted_hue, effective_saturation, 0.55)

    # Derive mood label from score
    mood = score_to_mood(temp)

    %__MODULE__{
      # Core colors
      background: background,
      foreground: derive_foreground(temp, effective_saturation, effective_warmth),
      muted: derive_muted(temp, effective_saturation, effective_warmth),
      accent: accent,

      # Severity spectrum - these shift with tint
      success: Color.new(normalize_hue(120 + hue_offset), effective_saturation * 0.7, 0.45),
      info: Color.new(normalize_hue(tinted_hue + 20), effective_saturation * 0.8, 0.50),
      warning: Color.new(normalize_hue(45 + hue_offset), effective_saturation * 1.1, 0.52),
      error: Color.new(normalize_hue(10 + hue_offset), effective_saturation * 1.1, 0.50),
      critical: Color.new(normalize_hue(0 + hue_offset), effective_saturation * 1.2, 0.45),

      # Token colors (derived from tinted base with contrast)
      timestamp: derive_token_color_v2(tinted_hue, :timestamp, effective_saturation, effective_warmth, effective_contrast),
      ip_address: derive_token_color_v2(tinted_hue, :ip_address, effective_saturation, effective_warmth, effective_contrast),
      domain: derive_token_color_v2(tinted_hue, :domain, effective_saturation, effective_warmth, effective_contrast),
      path: derive_token_color_v2(tinted_hue, :path, effective_saturation, effective_warmth, effective_contrast),
      number: derive_token_color_v2(tinted_hue, :number, effective_saturation, effective_warmth, effective_contrast),
      string: derive_token_color_v2(tinted_hue, :string, effective_saturation, effective_warmth, effective_contrast),
      keyword: derive_token_color_v2(tinted_hue, :keyword, effective_saturation, effective_warmth, effective_contrast),
      identifier: derive_token_color_v2(tinted_hue, :identifier, effective_saturation, effective_warmth, effective_contrast),
      operator: derive_token_color_v2(tinted_hue, :operator, effective_saturation * 0.7, effective_warmth, effective_contrast),
      bracket: derive_token_color_v2(tinted_hue, :bracket, effective_saturation * 0.6, effective_warmth, effective_contrast),
      comment: derive_token_color_v2(tinted_hue, :comment, effective_saturation * 0.3, effective_warmth, effective_contrast),
      uuid: derive_token_color_v2(tinted_hue, :uuid, effective_saturation, effective_warmth, effective_contrast),
      log_level: derive_token_color_v2(tinted_hue, :log_level, effective_saturation, effective_warmth, effective_contrast),

      # State colors
      state_positive: Color.new(normalize_hue(120 + hue_offset), effective_saturation * 0.7, 0.45),
      state_negative: Color.new(normalize_hue(10 + hue_offset), effective_saturation, 0.50),
      state_neutral: Color.new(tinted_hue, effective_saturation * 0.3, 0.45),
      state_transition: accent,

      # Metadata
      mood: mood,
      warmth: effective_warmth,
      saturation: effective_saturation,
      contrast: effective_contrast
    }
  end

  defp score_to_mood(score) do
    cond do
      score < 0.25 -> :calm
      score < 0.45 -> :neutral
      score < 0.60 -> :uneasy
      score < 0.80 -> :troubled
      true -> :critical
    end
  end

  # ============================================================================
  # Temperature Interpolation
  # ============================================================================

  defp interpolate_temperature(temp) do
    # Find the two stops to interpolate between
    {lower, upper} = find_bounding_stops(@temperature_stops, temp)

    {t1, h1, s1, c1, w1} = lower
    {t2, h2, s2, c2, w2} = upper

    # Calculate interpolation factor
    t = if t2 == t1, do: 0.0, else: (temp - t1) / (t2 - t1)

    # Linear interpolation (could use easing functions here)
    hue = lerp(h1, h2, t)
    sat = lerp(s1, s2, t)
    contrast = lerp(c1, c2, t)
    warmth = lerp(w1, w2, t)

    {hue, sat, contrast, warmth}
  end

  defp find_bounding_stops([stop | []], _temp), do: {stop, stop}
  defp find_bounding_stops([{t1, _, _, _, _} = s1, {t2, _, _, _, _} = s2 | rest], temp) do
    cond do
      temp <= t1 -> {s1, s1}
      temp <= t2 -> {s1, s2}
      true -> find_bounding_stops([s2 | rest], temp)
    end
  end

  defp interpolate_background(temp, hue_offset \\ 0.0) do
    {lower, upper} = find_bg_stops(@background_stops, temp)

    {t1, hex1} = lower
    {t2, hex2} = upper

    t = if t2 == t1, do: 0.0, else: (temp - t1) / (t2 - t1)

    c1 = Color.from_hex(hex1)
    c2 = Color.from_hex(hex2)

    mixed = Color.mix(c1, c2, t)

    # Apply hue offset to background (subtle shift)
    if hue_offset != 0.0 do
      Color.new(normalize_hue(mixed.h + hue_offset * 0.3), mixed.s, mixed.l, mixed.a)
    else
      mixed
    end
  end

  defp find_bg_stops([stop | []], _temp), do: {stop, stop}
  defp find_bg_stops([{t1, _} = s1, {t2, _} = s2 | rest], temp) do
    cond do
      temp <= t1 -> {s1, s1}
      temp <= t2 -> {s1, s2}
      true -> find_bg_stops([s2 | rest], temp)
    end
  end

  defp lerp(a, b, t), do: a + (b - a) * t

  # Normalize hue to 0-360 range
  defp normalize_hue(hue) do
    hue = :math.fmod(hue, 360.0)
    if hue < 0, do: hue + 360.0, else: hue
  end

  # ============================================================================
  # Derived Colors
  # ============================================================================

  defp derive_foreground(temp, saturation, _warmth) do
    # Foreground shifts from cool gray to warm gray
    base_hue = lerp(210, 30, temp)
    Color.new(base_hue, saturation * 0.15, 0.75)
  end

  defp derive_muted(temp, saturation, _warmth) do
    base_hue = lerp(210, 30, temp)
    Color.new(base_hue, saturation * 0.25, 0.45)
  end

  # ============================================================================
  # Token Color Derivation
  # ============================================================================

  # Hue offsets for different token types (relative to base temperature hue)
  @token_hue_offsets %{
    timestamp: -10,      # Slightly cooler than base
    ip_address: 5,       # Slightly warmer
    domain: 15,          # Warmer
    path: -25,           # Cooler
    number: 50,          # Much warmer (yellow direction)
    string: 80,          # Green direction
    keyword: 25,         # Warm
    identifier: 10,      # Near base
    operator: 0,         # Base hue, desaturated
    bracket: -15,        # Cool
    comment: 0,          # Base hue, very desaturated
    uuid: -50,           # Purple direction
    log_level: 35        # Warm (gold)
  }

  @token_lightness %{
    timestamp: 0.58,
    ip_address: 0.55,
    domain: 0.55,
    path: 0.58,
    number: 0.58,
    string: 0.55,
    keyword: 0.55,
    identifier: 0.58,
    operator: 0.55,
    bracket: 0.50,
    comment: 0.42,
    uuid: 0.55,
    log_level: 0.58
  }

  defp derive_token_color_v2(base_hue, token_type, saturation, warmth, contrast \\ 1.0) do
    hue_offset = Map.get(@token_hue_offsets, token_type, 0)
    base_lightness = Map.get(@token_lightness, token_type, 0.55)

    # Apply contrast - spread lightness away from midpoint (0.55)
    # contrast > 1 = more spread, contrast < 1 = flatter
    midpoint = 0.55
    lightness = midpoint + (base_lightness - midpoint) * contrast
    lightness = clamp(lightness, 0.25, 0.85)

    # Apply warmth as additional hue shift (positive warmth = toward red/orange)
    warmth_hue_shift = warmth * 20

    final_hue = base_hue + hue_offset + warmth_hue_shift

    Color.new(final_hue, saturation, lightness)
  end

  # Legacy function for backward compatibility
  defp derive_token_color(base, token_type, saturation, warmth) do
    accent = Color.from_hex(base.accent)
    hue_offset = Map.get(@token_hue_offsets, token_type, 0)

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
