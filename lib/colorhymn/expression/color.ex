defmodule Colorhymn.Expression.Color do
  @moduledoc """
  Color representation and manipulation using HSL color space.

  HSL (Hue, Saturation, Lightness) allows intuitive color modifications:
  - Hue: 0-360 (color wheel position)
  - Saturation: 0-1 (gray to vivid)
  - Lightness: 0-1 (black to white)
  """

  defstruct [:h, :s, :l, :a]

  @type t :: %__MODULE__{
    h: float(),  # 0-360
    s: float(),  # 0-1
    l: float(),  # 0-1
    a: float()   # 0-1 (alpha/opacity)
  }

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc "Create a new HSL color"
  def new(h, s, l, a \\ 1.0) do
    %__MODULE__{
      h: normalize_hue(h),
      s: clamp(s, 0, 1),
      l: clamp(l, 0, 1),
      a: clamp(a, 0, 1)
    }
  end

  @doc "Create color from hex string"
  def from_hex(hex) do
    hex = String.trim_leading(hex, "#")

    {r, g, b} = case hex do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> ->
        {hex_to_int(r), hex_to_int(g), hex_to_int(b)}
      <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> ->
        {hex_to_int(r <> r), hex_to_int(g <> g), hex_to_int(b <> b)}
      _ ->
        {128, 128, 128}  # Default gray
    end

    from_rgb(r, g, b)
  end

  @doc "Create color from RGB values (0-255)"
  def from_rgb(r, g, b) do
    r = r / 255
    g = g / 255
    b = b / 255

    max = Enum.max([r, g, b])
    min = Enum.min([r, g, b])
    l = (max + min) / 2

    if max == min do
      new(0, 0, l)
    else
      d = max - min
      s = if l > 0.5, do: d / (2 - max - min), else: d / (max + min)

      h = cond do
        max == r -> (g - b) / d + (if g < b, do: 6, else: 0)
        max == g -> (b - r) / d + 2
        max == b -> (r - g) / d + 4
      end

      new(h * 60, s, l)
    end
  end

  # ============================================================================
  # Output Formats
  # ============================================================================

  @doc "Convert to hex string (#rrggbb)"
  def to_hex(%__MODULE__{} = color) do
    {r, g, b} = to_rgb(color)
    "#" <> int_to_hex(r) <> int_to_hex(g) <> int_to_hex(b)
  end

  @doc "Convert to RGB tuple (0-255)"
  def to_rgb(%__MODULE__{h: h, s: s, l: l}) do
    if s == 0 do
      v = round(l * 255)
      {v, v, v}
    else
      q = if l < 0.5, do: l * (1 + s), else: l + s - l * s
      p = 2 * l - q

      r = hue_to_rgb(p, q, h + 120)
      g = hue_to_rgb(p, q, h)
      b = hue_to_rgb(p, q, h - 120)

      {round(r * 255), round(g * 255), round(b * 255)}
    end
  end

  @doc "Convert to HSL map for JSON serialization"
  def to_hsl_map(%__MODULE__{h: h, s: s, l: l, a: a}) do
    %{
      h: round(h),
      s: Float.round(s * 1.0, 3),
      l: Float.round(l * 1.0, 3),
      a: Float.round(a * 1.0, 3)
    }
  end

  @doc "Convert to CSS hsl() string"
  def to_css(%__MODULE__{h: h, s: s, l: l, a: a}) do
    if a == 1.0 do
      "hsl(#{round(h)}, #{round(s * 100)}%, #{round(l * 100)}%)"
    else
      "hsla(#{round(h)}, #{round(s * 100)}%, #{round(l * 100)}%, #{Float.round(a, 2)})"
    end
  end

  @doc "Convert to ANSI 256-color code"
  def to_ansi(%__MODULE__{} = color) do
    {r, g, b} = to_rgb(color)

    # Convert to 6x6x6 color cube (codes 16-231)
    # Or grayscale ramp (codes 232-255)

    # Check if it's close to grayscale
    if abs(r - g) < 10 and abs(g - b) < 10 do
      # Use grayscale ramp (24 shades)
      gray = round((r + g + b) / 3)
      if gray < 8 do
        0  # Black
      else
        if gray > 248 do
          15  # White
        else
          232 + round((gray - 8) / 10)
        end
      end
    else
      # Use 6x6x6 color cube
      r_idx = round(r / 255 * 5)
      g_idx = round(g / 255 * 5)
      b_idx = round(b / 255 * 5)
      16 + (36 * r_idx) + (6 * g_idx) + b_idx
    end
  end

  @doc "Generate ANSI escape sequence for foreground color"
  def to_ansi_fg(%__MODULE__{} = color) do
    "\e[38;5;#{to_ansi(color)}m"
  end

  @doc "Generate ANSI escape sequence for background color"
  def to_ansi_bg(%__MODULE__{} = color) do
    "\e[48;5;#{to_ansi(color)}m"
  end

  @doc "ANSI reset sequence"
  def ansi_reset, do: "\e[0m"

  # ============================================================================
  # Color Manipulation
  # ============================================================================

  @doc "Adjust hue by degrees"
  def rotate_hue(%__MODULE__{} = color, degrees) do
    %{color | h: normalize_hue(color.h + degrees)}
  end

  @doc "Adjust saturation (additive, clamped)"
  def saturate(%__MODULE__{} = color, amount) do
    %{color | s: clamp(color.s + amount, 0, 1)}
  end

  @doc "Adjust lightness (additive, clamped)"
  def lighten(%__MODULE__{} = color, amount) do
    %{color | l: clamp(color.l + amount, 0, 1)}
  end

  @doc "Set saturation directly"
  def set_saturation(%__MODULE__{} = color, s) do
    %{color | s: clamp(s, 0, 1)}
  end

  @doc "Set lightness directly"
  def set_lightness(%__MODULE__{} = color, l) do
    %{color | l: clamp(l, 0, 1)}
  end

  @doc "Mix two colors (weighted average in HSL space)"
  def mix(%__MODULE__{} = c1, %__MODULE__{} = c2, weight \\ 0.5) do
    # Handle hue interpolation across the 0/360 boundary
    h_diff = c2.h - c1.h
    h_diff = cond do
      h_diff > 180 -> h_diff - 360
      h_diff < -180 -> h_diff + 360
      true -> h_diff
    end

    new(
      normalize_hue(c1.h + h_diff * weight),
      c1.s + (c2.s - c1.s) * weight,
      c1.l + (c2.l - c1.l) * weight,
      c1.a + (c2.a - c1.a) * weight
    )
  end

  @doc "Create a complementary color (180 degree rotation)"
  def complement(%__MODULE__{} = color) do
    rotate_hue(color, 180)
  end

  @doc "Desaturate to grayscale"
  def grayscale(%__MODULE__{} = color) do
    %{color | s: 0}
  end

  @doc "Increase contrast (move lightness away from 0.5)"
  def contrast(%__MODULE__{} = color, amount) do
    new_l = if color.l > 0.5 do
      color.l + (1 - color.l) * amount
    else
      color.l - color.l * amount
    end
    %{color | l: clamp(new_l, 0, 1)}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp normalize_hue(h) do
    h = :math.fmod(h, 360)
    if h < 0, do: h + 360, else: h
  end

  defp clamp(val, min_v, max_v) do
    val |> max(min_v) |> min(max_v)
  end

  defp hue_to_rgb(p, q, h) do
    h = normalize_hue(h) / 360
    cond do
      h < 1/6 -> p + (q - p) * 6 * h
      h < 1/2 -> q
      h < 2/3 -> p + (q - p) * (2/3 - h) * 6
      true -> p
    end
  end

  defp hex_to_int(hex) do
    {val, _} = Integer.parse(hex, 16)
    val
  end

  defp int_to_hex(int) do
    int
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
    |> String.downcase()
  end
end
