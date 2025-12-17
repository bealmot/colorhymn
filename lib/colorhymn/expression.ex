defmodule Colorhymn.Expression do
  @moduledoc """
  Expression layer - transforms perception into visual language.

  This is the main public API for converting log perception into colors.
  Takes FirstSight output and produces a complete color palette that can
  be exported in various formats (hex, HSL, ANSI, CSS).
  """

  alias Colorhymn.Expression.{Color, Palette}
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
  """
  def from_perception(%{temperature: temperature, perception: perception}) do
    mood = temperature_to_mood(temperature)
    perception_map = perception_to_map(perception)

    Palette.generate(mood, perception_map)
  end

  @doc """
  Quick palette generation from just a mood.
  Useful for testing or when you want a specific feel.
  """
  def from_mood(mood) when mood in [:calm, :neutral, :uneasy, :troubled, :critical] do
    Palette.generate(mood, %{})
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
  # Temperature → Mood Mapping
  # ============================================================================

  defp temperature_to_mood(:cool), do: :calm
  defp temperature_to_mood(:normal), do: :neutral
  defp temperature_to_mood(:elevated), do: :uneasy
  defp temperature_to_mood(:warm), do: :troubled
  defp temperature_to_mood(:troubled), do: :troubled
  defp temperature_to_mood(:critical), do: :critical
  defp temperature_to_mood(_), do: :neutral

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

  # Map tokenizer types to palette keys
  defp token_to_palette_key(:timestamp), do: :timestamp
  defp token_to_palette_key(:ip_address), do: :ip_address
  defp token_to_palette_key(:ipv6_address), do: :ip_address
  defp token_to_palette_key(:domain), do: :domain
  defp token_to_palette_key(:url), do: :domain
  defp token_to_palette_key(:path), do: :path
  defp token_to_palette_key(:uuid), do: :uuid
  defp token_to_palette_key(:mac_address), do: :identifier
  defp token_to_palette_key(:email), do: :domain
  defp token_to_palette_key(:number), do: :number
  defp token_to_palette_key(:hex_number), do: :number
  defp token_to_palette_key(:port), do: :number
  defp token_to_palette_key(:string), do: :string
  defp token_to_palette_key(:keyword), do: :keyword
  defp token_to_palette_key(:log_level), do: :log_level
  defp token_to_palette_key(:identifier), do: :identifier
  defp token_to_palette_key(:operator), do: :operator
  defp token_to_palette_key(:bracket), do: :bracket
  defp token_to_palette_key(:key), do: :keyword
  defp token_to_palette_key(:equals), do: :operator
  defp token_to_palette_key(:text), do: :foreground
  defp token_to_palette_key(_), do: :foreground
end
