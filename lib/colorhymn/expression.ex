defmodule Colorhymn.Expression do
  @moduledoc """
  Expression layer - transforms perception into visual language.

  This is the main public API for converting log perception into colors.
  Takes FirstSight output and produces a complete color palette that can
  be exported in various formats (hex, HSL, ANSI, CSS).
  """

  alias Colorhymn.Expression.{Color, Palette, Dither}
  alias Colorhymn.Perception
  alias Colorhymn.Tokenizer
  alias Colorhymn.Tokenizer.Token

  # ============================================================================
  # Main API
  # ============================================================================

  @doc """
  Generate a complete expression from FirstSight analysis.

  Takes the output of `FirstSight.perceive/2` and returns a palette
  with all semantic colors modulated by the perception dimensions.

  Options:
    - tint: Hue offset in degrees (-180 to 180) to shift the entire palette
    - sat: Saturation multiplier (0.5 = muted, 1.5 = vivid)
    - contrast: Contrast multiplier (0.5 = flat, 1.5 = punchy)
  """
  def from_perception(sight, opts \\ [])

  def from_perception(%{temperature: temperature, perception: perception} = sight, opts) do
    # Use continuous temperature_score if available, otherwise fall back to discrete
    temperature_score = Map.get(sight, :temperature_score, temperature_to_default_score(temperature))
    perception_map = perception_to_map(perception)

    # Apply style modifiers if provided
    perception_map = perception_map
    |> maybe_put(:hue_offset, Keyword.get(opts, :tint))
    |> maybe_put(:sat_mult, Keyword.get(opts, :sat))
    |> maybe_put(:contrast_mult, Keyword.get(opts, :contrast))

    Palette.generate(temperature_score, perception_map)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, 1.0), do: map  # Skip default values
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Fallback scores for discrete temperatures (backward compatibility)
  defp temperature_to_default_score(:calm), do: 0.15
  defp temperature_to_default_score(:cool), do: 0.2
  defp temperature_to_default_score(:normal), do: 0.4
  defp temperature_to_default_score(:neutral), do: 0.4
  defp temperature_to_default_score(:elevated), do: 0.55
  defp temperature_to_default_score(:uneasy), do: 0.55
  defp temperature_to_default_score(:warm), do: 0.7
  defp temperature_to_default_score(:troubled), do: 0.7
  defp temperature_to_default_score(:critical), do: 0.9
  defp temperature_to_default_score(_), do: 0.4

  @doc """
  Quick palette generation from just a mood.
  Useful for testing or when you want a specific feel.
  """
  def from_mood(mood) when mood in [:calm, :neutral, :uneasy, :troubled, :critical] do
    Palette.generate(temperature_to_default_score(mood), %{})
  end

  @doc """
  Quick palette generation from a temperature score (0.0 to 1.0).
  """
  def from_temperature(score) when is_number(score) do
    Palette.generate(score, %{})
  end

  @doc """
  Colorize a token with the appropriate color from the palette.
  Returns the color struct for the given token type.
  """
  def colorize(palette, token_type) do
    Palette.color_for(palette, token_type)
  end

  @doc """
  Wrap text in ANSI color codes using palette colors.
  """
  def ansi_colorize(palette, text, token_type) do
    color = colorize(palette, token_type)
    "#{Color.to_ansi_fg(color)}#{text}#{Color.ansi_reset()}"
  end

  @doc """
  Generate a span with inline CSS styling.
  """
  def html_colorize(palette, text, token_type) do
    color = colorize(palette, token_type)
    "<span style=\"color: #{Color.to_hex(color)}\">#{html_escape(text)}</span>"
  end

  # ============================================================================
  # Export Formats
  # ============================================================================

  @doc "Export palette as hex color map"
  defdelegate to_hex_map(palette), to: Palette

  @doc "Export palette as HSL map (for JS)"
  defdelegate to_hsl_map(palette), to: Palette

  @doc "Export palette as CSS custom properties"
  defdelegate to_css_vars(palette), to: Palette

  @doc """
  Export palette as JSON-ready map with all formats.
  Includes hex, HSL, and metadata.
  """
  def to_json_map(palette) do
    %{
      mood: palette.mood,
      warmth: palette.warmth,
      saturation: palette.saturation,
      contrast: palette.contrast,
      colors: %{
        hex: to_hex_map(palette),
        hsl: to_hsl_map(palette)
      }
    }
  end

  @doc """
  Export as ANSI color reference (for terminal themes).
  Returns a map of token types to ANSI codes.
  """
  def to_ansi_map(palette) do
    palette
    |> Map.from_struct()
    |> Enum.filter(fn {_k, v} -> is_struct(v, Color) end)
    |> Enum.map(fn {k, v} -> {k, Color.to_ansi(v)} end)
    |> Map.new()
  end


  # ============================================================================
  # Perception Struct → Map
  # ============================================================================

  defp perception_to_map(%Perception{} = p) do
    %{
      burstiness: p.burstiness,
      regularity: p.regularity,
      stability: p.stability,
      cognitive_load: p.cognitive_load,
      drift: p.drift
    }
  end

  defp perception_to_map(_), do: %{}

  # ============================================================================
  # Helpers
  # ============================================================================

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # ============================================================================
  # Line Rendering
  # ============================================================================

  @doc """
  Tokenize and render a line with ANSI colors.
  """
  def render_line_ansi(palette, line) do
    line
    |> Tokenizer.tokenize()
    |> Enum.map(&render_token_ansi(palette, &1))
    |> Enum.join()
  end

  @doc """
  Tokenize and render a line with HTML spans.
  """
  def render_line_html(palette, line) do
    line
    |> Tokenizer.tokenize()
    |> Enum.map(&render_token_html(palette, &1))
    |> Enum.join()
  end

  @doc """
  Tokenize and render multiple lines with ANSI colors.
  """
  def render_lines_ansi(palette, lines) when is_list(lines) do
    Enum.map(lines, &render_line_ansi(palette, &1))
  end

  @doc """
  Tokenize and return structured output for custom rendering.
  Returns list of {token_type, value, hex_color} tuples.
  """
  def render_line_data(palette, line) do
    line
    |> Tokenizer.tokenize()
    |> Enum.map(fn %Token{type: type, value: value} ->
      palette_key = token_to_palette_key(type)
      color = Palette.color_for(palette, palette_key)
      {type, value, Color.to_hex(color)}
    end)
  end

  # ============================================================================
  # Dithered Rendering (organic color flow)
  # ============================================================================

  @doc """
  Render a line with error-diffusion dithering for organic color flow.
  Returns {rendered_string, new_dither_state}.

  Pass the dither state between lines to create inter-line flow.
  """
  def render_line_dithered(palette, line, dither_state \\ nil) do
    dither = dither_state || Dither.new()
    tokens = Tokenizer.tokenize(line)

    {rendered_tokens, final_dither} =
      Enum.map_reduce(tokens, dither, fn %Token{type: type, value: value}, acc_dither ->
        palette_key = token_to_palette_key(type)
        ideal_color = Palette.color_for(palette, palette_key)

        {dithered_color, new_dither} = Dither.dither(acc_dither, ideal_color, value)

        rendered = "#{Color.to_ansi_fg(dithered_color)}#{value}#{Color.ansi_reset()}"
        {rendered, new_dither}
      end)

    # Prepare dither state for next line
    next_dither = Dither.next_line(final_dither)

    {Enum.join(rendered_tokens), next_dither}
  end

  @doc """
  Render a line with dithering, returning structured data.
  Returns {list_of_tuples, new_dither_state}.
  """
  def render_line_data_dithered(palette, line, dither_state \\ nil) do
    dither = dither_state || Dither.new()
    tokens = Tokenizer.tokenize(line)

    {data, final_dither} =
      Enum.map_reduce(tokens, dither, fn %Token{type: type, value: value}, acc_dither ->
        palette_key = token_to_palette_key(type)
        ideal_color = Palette.color_for(palette, palette_key)

        {dithered_color, new_dither} = Dither.dither(acc_dither, ideal_color, value)

        {{type, value, Color.to_hex(dithered_color)}, new_dither}
      end)

    {data, Dither.next_line(final_dither)}
  end

  @doc """
  Render multiple lines with dithering, maintaining flow between lines.
  """
  def render_lines_dithered(palette, lines, dither_opts \\ []) do
    initial_dither = Dither.new(dither_opts)

    {rendered_lines, _final_dither} =
      Enum.map_reduce(lines, initial_dither, fn line, dither ->
        render_line_dithered(palette, line, dither)
      end)

    rendered_lines
  end

  @doc """
  Render multiple lines with dithering, returning structured data.
  """
  def render_lines_data_dithered(palette, lines, dither_opts \\ []) do
    initial_dither = Dither.new(dither_opts)

    {data_lines, _final_dither} =
      Enum.map_reduce(lines, initial_dither, fn line, dither ->
        render_line_data_dithered(palette, line, dither)
      end)

    data_lines
  end

  # ============================================================================
  # Token Rendering Helpers
  # ============================================================================

  defp render_token_ansi(palette, %Token{type: type, value: value}) do
    palette_key = token_to_palette_key(type)
    color = Palette.color_for(palette, palette_key)
    "#{Color.to_ansi_fg(color)}#{value}#{Color.ansi_reset()}"
  end

  defp render_token_html(palette, %Token{type: type, value: value}) do
    palette_key = token_to_palette_key(type)
    color = Palette.color_for(palette, palette_key)
    "<span class=\"token-#{type}\" style=\"color: #{Color.to_hex(color)}\">#{html_escape(value)}</span>"
  end

  @doc false
  # Map tokenizer types to palette keys
  def token_to_palette_key(:timestamp), do: :timestamp
  def token_to_palette_key(:ip_address), do: :ip_address
  def token_to_palette_key(:ipv6_address), do: :ip_address
  def token_to_palette_key(:domain), do: :domain
  def token_to_palette_key(:url), do: :domain
  def token_to_palette_key(:path), do: :path
  def token_to_palette_key(:uuid), do: :uuid
  def token_to_palette_key(:mac_address), do: :identifier
  def token_to_palette_key(:email), do: :domain
  def token_to_palette_key(:number), do: :number
  def token_to_palette_key(:hex_number), do: :number
  def token_to_palette_key(:port), do: :number
  def token_to_palette_key(:string), do: :string
  def token_to_palette_key(:keyword), do: :keyword
  def token_to_palette_key(:log_level), do: :log_level
  def token_to_palette_key(:identifier), do: :identifier
  def token_to_palette_key(:operator), do: :operator
  def token_to_palette_key(:bracket), do: :bracket
  def token_to_palette_key(:key), do: :keyword
  def token_to_palette_key(:equals), do: :operator
  def token_to_palette_key(:text), do: :foreground
  def token_to_palette_key(_), do: :foreground
end
