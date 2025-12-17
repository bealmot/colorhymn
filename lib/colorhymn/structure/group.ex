defmodule Colorhymn.Structure.Group do
  @moduledoc """
  A multi-line group that should be analyzed as a unit.

  Groups represent related lines that should share styling or be analyzed
  together for temperature, such as:
  - Continuation lines (indented, starting with |, [-, etc.)
  - Table data (routing tables, formatted output)
  - Stack traces (exception + frames)
  """

  alias Colorhymn.Structure.Region

  @type group_type ::
          :single
          | :continuation
          | :table
          | :stack_trace
          | :block

  @type t :: %__MODULE__{
          type: group_type(),
          start_line: non_neg_integer(),
          end_line: non_neg_integer(),
          lines: [String.t()],
          regions: [[Region.t()]],
          temperature: {float(), atom()} | nil,
          metadata: map()
        }

  defstruct [
    :type,
    :start_line,
    :end_line,
    lines: [],
    regions: [],
    temperature: nil,
    metadata: %{}
  ]

  @doc """
  Create a single-line group (no grouping, standalone line).
  """
  def single(line, line_num, regions \\ []) do
    %__MODULE__{
      type: :single,
      start_line: line_num,
      end_line: line_num,
      lines: [line],
      regions: [regions],
      metadata: %{}
    }
  end

  @doc """
  Create a multi-line group.
  """
  def multi(type, lines, start_line, regions_list \\ []) do
    end_line = start_line + length(lines) - 1

    %__MODULE__{
      type: type,
      start_line: start_line,
      end_line: end_line,
      lines: lines,
      regions: regions_list,
      metadata: %{}
    }
  end

  @doc """
  Get the number of lines in a group.
  """
  def line_count(%__MODULE__{lines: lines}), do: length(lines)

  @doc """
  Check if a group spans multiple lines.
  """
  def multi_line?(%__MODULE__{start_line: s, end_line: e}), do: e > s

  @doc """
  Set the temperature for a group.
  """
  def with_temperature(%__MODULE__{} = group, {score, temp_atom}) do
    %{group | temperature: {score, temp_atom}}
  end

  @doc """
  Get all lines in the group as a single string (for collective analysis).
  """
  def combined_content(%__MODULE__{lines: lines}) do
    Enum.join(lines, "\n")
  end
end
