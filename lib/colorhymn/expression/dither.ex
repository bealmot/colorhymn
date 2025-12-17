defmodule Colorhymn.Expression.Dither do
  @moduledoc """
  Error-diffusion dithering for organic color flow.

  Instead of flat, uniform colors, this module adds organic variation
  by propagating "error" from one token to the next. Similar to
  Floyd-Steinberg dithering but applied to log colorization.

  The effect is subtle: colors gently drift and flow through the line,
  creating a more natural, less synthetic appearance.
  """

  alias Colorhymn.Expression.Color

  defstruct [
    # Accumulated error in HSL space
    hue_error: 0.0,
    saturation_error: 0.0,
    lightness_error: 0.0,

    # Parameters
    decay: 0.7,           # How much error decays per token (0-1)
    intensity: 1.0,       # Overall dithering strength
    content_influence: 0.3 # How much token content affects variance
  ]

  @type t :: %__MODULE__{}

  @doc """
  Create a new dither state with default parameters.
  """
  def new(opts \\ []) do
    %__MODULE__{
      decay: Keyword.get(opts, :decay, 0.7),
      intensity: Keyword.get(opts, :intensity, 1.0),
      content_influence: Keyword.get(opts, :content_influence, 0.3)
    }
  end

  @doc """
  Apply dithering to a color and update state.

  Takes the ideal color from the palette and the token content,
  returns {dithered_color, new_state}.

  The token content is used to add deterministic variation -
  the same content will always produce the same perturbation,
  giving visual "identity" to repeated values.
  """
  def dither(%__MODULE__{} = state, %Color{} = ideal_color, token_content) do
    # 1. Calculate content-based perturbation (deterministic noise from content)
    content_perturb = content_perturbation(token_content, state.content_influence)

    # 2. Apply accumulated error + content perturbation to ideal color
    shifted = shift_color(ideal_color, state, content_perturb)

    # 3. Calculate the "error" - difference between ideal and what we rendered
    #    This creates the organic flow as error propagates forward
    new_error = calculate_error(ideal_color, shifted, state.intensity)

    # 4. Update state with decayed old error + new error
    new_state = propagate_error(state, new_error)

    {shifted, new_state}
  end

  @doc """
  Apply dithering to a list of tokens, threading state through.
  Returns {list_of_dithered_colors, final_state}.
  """
  def dither_tokens(%__MODULE__{} = state, tokens, palette, color_fn) do
    {colors, final_state} =
      Enum.map_reduce(tokens, state, fn token, acc_state ->
        ideal_color = color_fn.(palette, token)
        {dithered, new_state} = dither(acc_state, ideal_color, token_value(token))
        {{token, dithered}, new_state}
      end)

    {colors, final_state}
  end

  @doc """
  Carry some error between lines for continuity.
  Call this at the end of each line to prepare state for next line.
  """
  def next_line(%__MODULE__{} = state) do
    # Carry forward a portion of the error for inter-line flow
    line_carry = 0.4

    %{state |
      hue_error: state.hue_error * line_carry,
      saturation_error: state.saturation_error * line_carry,
      lightness_error: state.lightness_error * line_carry
    }
  end

  @doc """
  Reset dither state (e.g., at start of new file).
  """
  def reset(%__MODULE__{} = state) do
    %{state | hue_error: 0.0, saturation_error: 0.0, lightness_error: 0.0}
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  # Generate deterministic perturbation from token content
  defp content_perturbation(content, influence) when is_binary(content) do
    # Hash the content to get deterministic "randomness"
    hash = :erlang.phash2(content, 1_000_000)

    # Convert hash to small HSL offsets
    # Range: hue ±8°, sat ±0.05, light ±0.03
    hue_offset = (rem(hash, 1000) / 1000 - 0.5) * 16 * influence
    sat_offset = (rem(div(hash, 1000), 1000) / 1000 - 0.5) * 0.10 * influence
    light_offset = (rem(div(hash, 1_000_000), 1000) / 1000 - 0.5) * 0.06 * influence

    {hue_offset, sat_offset, light_offset}
  end

  defp content_perturbation(_, _), do: {0.0, 0.0, 0.0}

  # Apply error and perturbation to shift the ideal color
  defp shift_color(%Color{} = color, %__MODULE__{} = state, {h_perturb, s_perturb, l_perturb}) do
    # Combine accumulated error with content perturbation
    total_h = state.hue_error + h_perturb
    total_s = state.saturation_error + s_perturb
    total_l = state.lightness_error + l_perturb

    # Apply shifts with clamping
    Color.new(
      color.h + total_h,
      clamp(color.s + total_s, 0.1, 0.95),
      clamp(color.l + total_l, 0.25, 0.85),
      color.a
    )
  end

  # Calculate error between ideal and rendered color
  # This is what creates the organic "flow"
  defp calculate_error(%Color{} = ideal, %Color{} = rendered, intensity) do
    # The "error" is the difference, scaled by intensity
    # Positive values mean we rendered brighter/more saturated than ideal
    h_err = (ideal.h - rendered.h) * 0.3 * intensity
    s_err = (ideal.s - rendered.s) * 0.5 * intensity
    l_err = (ideal.l - rendered.l) * 0.4 * intensity

    {h_err, s_err, l_err}
  end

  # Propagate error to next token with decay
  defp propagate_error(%__MODULE__{} = state, {h_err, s_err, l_err}) do
    # Floyd-Steinberg style: current error decays, new error adds
    %{state |
      hue_error: state.hue_error * state.decay + h_err,
      saturation_error: state.saturation_error * state.decay + s_err,
      lightness_error: state.lightness_error * state.decay + l_err
    }
  end

  # Extract value from token (handles both raw strings and Token structs)
  defp token_value(%{value: value}), do: value
  defp token_value(value) when is_binary(value), do: value
  defp token_value(_), do: ""

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
