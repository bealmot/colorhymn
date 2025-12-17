defmodule Colorhymn.Structure.Region do
  @moduledoc """
  A semantic region within a log line - a higher-level grouping of tokens.

  Regions represent structural components of a log line like timestamps,
  log levels, component names, key-value pairs, and message content.
  Each region can have its own temperature for per-region colorization.
  """

  alias Colorhymn.Tokenizer.Token

  @type region_type ::
          :timestamp
          | :log_level
          | :component
          | :key_value
          | :bracket
          | :message
          | :whitespace

  @type t :: %__MODULE__{
          type: region_type(),
          start: non_neg_integer(),
          length: non_neg_integer(),
          value: String.t(),
          tokens: [Token.t()],
          metadata: map()
        }

  defstruct [
    :type,
    :start,
    :length,
    :value,
    tokens: [],
    metadata: %{}
  ]

  @doc """
  Create a new region from a token.
  """
  def from_token(%Token{} = token, type, metadata \\ %{}) do
    %__MODULE__{
      type: type,
      start: token.start,
      length: token.length,
      value: token.value,
      tokens: [token],
      metadata: metadata
    }
  end

  @doc """
  Create a region spanning multiple tokens.
  """
  def from_tokens(tokens, type, metadata \\ %{}) when is_list(tokens) and length(tokens) > 0 do
    sorted = Enum.sort_by(tokens, & &1.start)
    first = hd(sorted)
    last = List.last(sorted)

    %__MODULE__{
      type: type,
      start: first.start,
      length: last.start + last.length - first.start,
      value: Enum.map_join(sorted, "", & &1.value),
      tokens: sorted,
      metadata: metadata
    }
  end

  @doc """
  Create a region from raw position data (when content doesn't align with tokens).
  """
  def from_span(line, start, length, type, metadata \\ %{}) do
    %__MODULE__{
      type: type,
      start: start,
      length: length,
      value: binary_part(line, start, length),
      tokens: [],
      metadata: metadata
    }
  end

  @doc """
  Get the end position (exclusive) of a region.
  """
  def end_pos(%__MODULE__{start: start, length: length}), do: start + length

  @doc """
  Check if two regions overlap.
  """
  def overlaps?(%__MODULE__{} = r1, %__MODULE__{} = r2) do
    r1.start < end_pos(r2) and r2.start < end_pos(r1)
  end

  @doc """
  Check if a region contains a position.
  """
  def contains?(%__MODULE__{start: start, length: length}, pos) do
    pos >= start and pos < start + length
  end
end
