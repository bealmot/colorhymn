defmodule Colorhymn.Expression.Theme do
  @moduledoc """
  Theme system for constraining color space in palette generation.

  Themes transform colors after palette generation, allowing the same
  temperature/perception-based palette to be expressed within different
  aesthetic constraints (monochrome, terminal-safe, high-contrast, etc.).

  ## Available Themes

  - `rainbow` - Full spectrum (default behavior)
  - `monochrome` - Single hue, vary only lightness/saturation
  - `temp_lock_warm` - Locked to warm spectrum (reds/oranges/yellows, 0-60°)
  - `temp_lock_cool` - Locked to cool spectrum (blues/cyans/greens, 150-270°)
  - `terminal` - ANSI 16-color palette only
  - `high_contrast` - 2-3 colors maximum, stark differentiation
  - `semantic` - Color only errors/warnings/success, everything else neutral
  """

  alias Colorhymn.Expression.{Color, Palette}

  @type theme_name ::
          :rainbow
          | :monochrome
          | :temp_lock_warm
          | :temp_lock_cool
          | :terminal
          | :high_contrast
          | :semantic

  # ANSI 16-color palette in HSL
  @ansi_colors [
    # Standard colors
    {0, 0.0, 0.0},       # 0: Black
    {0, 0.8, 0.35},      # 1: Red
    {120, 0.8, 0.35},    # 2: Green
    {60, 0.8, 0.35},     # 3: Yellow
    {240, 0.8, 0.35},    # 4: Blue
    {300, 0.8, 0.35},    # 5: Magenta
    {180, 0.8, 0.35},    # 6: Cyan
    {0, 0.0, 0.75},      # 7: White (light gray)
    # Bright colors
    {0, 0.0, 0.50},      # 8: Bright Black (dark gray)
    {0, 1.0, 0.50},      # 9: Bright Red
    {120, 1.0, 0.50},    # 10: Bright Green
    {60, 1.0, 0.50},     # 11: Bright Yellow
    {240, 1.0, 0.50},    # 12: Bright Blue
    {300, 1.0, 0.50},    # 13: Bright Magenta
    {180, 1.0, 0.50},    # 14: Bright Cyan
    {0, 0.0, 1.0}        # 15: Bright White
  ]

  # Semantic token types that should retain color in semantic theme
  @semantic_colored_types [
    :error,
    :critical,
    :warning,
    :success,
    :log_level,
    :state_positive,
    :state_negative
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  List all available theme names.
  """
  def list_names do
    [:rainbow, :monochrome, :temp_lock_warm, :temp_lock_cool, :terminal, :high_contrast, :semantic]
  end

  @doc """
  Check if a theme name is valid.
  """
  def valid?(name) when is_atom(name), do: name in list_names()
  def valid?(_), do: false

  @doc """
  Parse a theme name from a string, handling hyphens.
  """
  def parse(name) when is_binary(name) do
    normalized = name
      |> String.downcase()
      |> String.replace("-", "_")

    try do
      atom = String.to_existing_atom(normalized)
      if valid?(atom), do: {:ok, atom}, else: {:error, "Unknown theme: #{name}"}
    rescue
      ArgumentError -> {:error, "Unknown theme: #{name}"}
    end
  end

  @doc """
  Apply a theme transformation to a palette.

  The theme constrains/transforms colors while preserving the palette structure.
  Pass the original temperature_score for themes that need it (high_contrast).
  """
  def apply(palette, theme_name, opts \\ [])

  def apply(%Palette{} = palette, :rainbow, _opts) do
    # Identity - no transformation
    palette
  end

  def apply(%Palette{} = palette, :monochrome, _opts) do
    # Lock all colors to the base hue derived from warmth
    base_hue = warmth_to_hue(palette.warmth)
    transform_palette_colors(palette, &monochrome_transform(&1, base_hue))
  end

  def apply(%Palette{} = palette, :temp_lock_warm, _opts) do
    # Remap all hues to warm spectrum (0-60°)
    transform_palette_colors(palette, &warm_spectrum_transform/1)
  end

  def apply(%Palette{} = palette, :temp_lock_cool, _opts) do
    # Remap all hues to cool spectrum (150-270°)
    transform_palette_colors(palette, &cool_spectrum_transform/1)
  end

  def apply(%Palette{} = palette, :terminal, _opts) do
    # Quantize all colors to nearest ANSI 16 color
    transform_palette_colors(palette, &terminal_transform/1)
  end

  def apply(%Palette{} = palette, :high_contrast, opts) do
    # Snap colors to primary/accent/gray (2-3 colors max)
    temp_score = Keyword.get(opts, :temperature_score, 0.5)
    {primary_hue, accent_hue} = high_contrast_hues(temp_score)
    transform_palette_colors(palette, &high_contrast_transform(&1, primary_hue, accent_hue))
  end

  def apply(%Palette{} = palette, :semantic, _opts) do
    # Desaturate non-semantic colors
    transform_palette_with_keys(palette, &semantic_transform/2)
  end

  # ============================================================================
  # Transform Functions
  # ============================================================================

  defp monochrome_transform(%Color{} = color, base_hue) do
    # Lock hue to base, keep saturation and lightness
    Color.new(base_hue, color.s, color.l, color.a)
  end

  defp warm_spectrum_transform(%Color{} = color) do
    # Map any hue to 0-60° range (red to yellow)
    new_hue = remap_hue_to_range(color.h, 0, 60)
    Color.new(new_hue, color.s, color.l, color.a)
  end

  defp cool_spectrum_transform(%Color{} = color) do
    # Map any hue to 150-270° range (green to blue-purple)
    new_hue = remap_hue_to_range(color.h, 150, 270)
    Color.new(new_hue, color.s, color.l, color.a)
  end

  defp terminal_transform(%Color{} = color) do
    # Find nearest ANSI 16 color
    find_nearest_ansi(color)
  end

  defp high_contrast_transform(%Color{} = color, primary_hue, accent_hue) do
    cond do
      # Low saturation -> pure gray
      color.s < 0.15 ->
        Color.new(0, 0.0, quantize_lightness(color.l, 3), color.a)

      # Near primary hue -> snap to primary with high saturation
      hue_distance(color.h, primary_hue) < 90 ->
        Color.new(primary_hue, 0.85, quantize_lightness(color.l, 3), color.a)

      # Everything else -> accent
      true ->
        Color.new(accent_hue, 0.85, quantize_lightness(color.l, 3), color.a)
    end
  end

  defp semantic_transform(%Color{} = color, palette_key) do
    if palette_key in @semantic_colored_types do
      # Keep original color for semantic types
      color
    else
      # Desaturate to gray
      Color.new(color.h, 0.0, color.l, color.a)
    end
  end

  # ============================================================================
  # Palette Transformation Helpers
  # ============================================================================

  defp transform_palette_colors(%Palette{} = palette, transform_fn) do
    palette
    |> Map.from_struct()
    |> Enum.map(fn
      {key, %Color{} = color} -> {key, transform_fn.(color)}
      {key, value} -> {key, value}
    end)
    |> Map.new()
    |> then(&struct(Palette, &1))
  end

  defp transform_palette_with_keys(%Palette{} = palette, transform_fn) do
    palette
    |> Map.from_struct()
    |> Enum.map(fn
      {key, %Color{} = color} -> {key, transform_fn.(color, key)}
      {key, value} -> {key, value}
    end)
    |> Map.new()
    |> then(&struct(Palette, &1))
  end

  # ============================================================================
  # Color Math Helpers
  # ============================================================================

  # Convert warmth (-0.5 to 0.9) to a representative hue
  defp warmth_to_hue(warmth) do
    # Warm (positive) -> red/orange (0-30°)
    # Cool (negative) -> blue/cyan (180-210°)
    # Neutral -> teal (160°)
    cond do
      warmth > 0.3 -> 20 + (1 - warmth) * 20  # 20-40° (orange-yellow)
      warmth < -0.1 -> 180 + abs(warmth) * 40  # 180-200° (cyan-blue)
      true -> 160 + warmth * 30  # 150-170° (teal range)
    end
  end

  # Remap a hue to a target range
  defp remap_hue_to_range(hue, min_hue, max_hue) do
    # Normalize input hue to 0-360
    normalized = :math.fmod(hue, 360)
    normalized = if normalized < 0, do: normalized + 360, else: normalized

    # Map 0-360 to target range
    range = max_hue - min_hue
    min_hue + (normalized / 360) * range
  end

  # Calculate distance between two hues (accounting for wraparound)
  defp hue_distance(h1, h2) do
    diff = abs(h1 - h2)
    min(diff, 360 - diff)
  end

  # Quantize lightness to N levels
  defp quantize_lightness(lightness, levels) do
    step = 1.0 / (levels - 1)
    round(lightness / step) * step
    |> max(0.15)  # Don't go too dark
    |> min(0.85)  # Don't go too bright
  end

  # Find nearest ANSI 16 color
  defp find_nearest_ansi(%Color{} = color) do
    {h, s, l} = {color.h, color.s, color.l}

    # Find closest match
    {best_h, best_s, best_l} =
      @ansi_colors
      |> Enum.min_by(fn {ah, as, al} ->
        # Weight hue distance higher for saturated colors
        hue_weight = if s > 0.2 and as > 0.2, do: 2.0, else: 0.5
        sat_weight = 1.0
        light_weight = 1.5

        hue_diff = hue_distance(h, ah) / 180  # Normalize to 0-1
        sat_diff = abs(s - as)
        light_diff = abs(l - al)

        hue_weight * hue_diff + sat_weight * sat_diff + light_weight * light_diff
      end)

    Color.new(best_h, best_s, best_l, color.a)
  end

  # Determine primary/accent hues based on temperature
  defp high_contrast_hues(temp_score) do
    cond do
      # Hot -> Red primary, Cyan accent
      temp_score > 0.6 -> {10, 180}
      # Cool -> Blue primary, Orange accent
      temp_score < 0.4 -> {220, 30}
      # Neutral -> Teal primary, Magenta accent
      true -> {180, 300}
    end
  end
end
