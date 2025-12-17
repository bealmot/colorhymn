defmodule Colorhymn.Perception.Repetition do
  @moduledoc """
  Repetition dimension analysis - patterns and uniqueness.
  """

  def analyze(lines) when length(lines) < 2 do
    %{
      uniqueness: 0.5,
      template_ratio: 0.5,
      pattern_recurrence: 0.5,
      motif_strength: 0.5
    }
  end

  def analyze(lines) do
    %{
      uniqueness: compute_uniqueness(lines),
      template_ratio: compute_template_ratio(lines),
      pattern_recurrence: compute_pattern_recurrence(lines),
      motif_strength: compute_motif_strength(lines)
    }
  end

  defp compute_uniqueness(lines) do
    unique_count = lines |> Enum.uniq() |> length()
    total_count = length(lines)

    clamp(unique_count / total_count, 0.0, 1.0)
  end

  defp compute_template_ratio(lines) do
    # Extract templates by replacing variable parts with placeholders
    templates = Enum.map(lines, &extract_template/1)
    template_frequencies = Enum.frequencies(templates)

    if map_size(template_frequencies) == 0 do
      0.5
    else
      # Count lines that match a template used more than once
      repeated_templates = template_frequencies
      |> Enum.filter(fn {_template, count} -> count > 1 end)
      |> Enum.map(fn {_template, count} -> count end)
      |> Enum.sum()

      clamp(repeated_templates / length(lines), 0.0, 1.0)
    end
  end

  defp extract_template(line) do
    line
    |> String.replace(~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, "<IP>")
    |> String.replace(~r/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/, "<UUID>")
    |> String.replace(~r/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/, "<TIMESTAMP>")
    |> String.replace(~r/\b\d+\b/, "<NUM>")
    |> String.replace(~r/\b[0-9a-fA-F]{32,}\b/, "<HASH>")
  end

  defp compute_pattern_recurrence(lines) do
    # Look for recurring n-grams (sequences of tokens)
    ngrams = lines
    |> Enum.flat_map(fn line ->
      tokens = String.split(line, ~r/\s+/, trim: true)
      extract_ngrams(tokens, 3)
    end)
    |> Enum.frequencies()

    if map_size(ngrams) == 0 do
      0.5
    else
      # Count recurring ngrams (appearing 2+ times)
      recurring = ngrams |> Enum.count(fn {_ngram, count} -> count > 1 end)
      total = map_size(ngrams)

      clamp(recurring / max(total, 1), 0.0, 1.0)
    end
  end

  defp extract_ngrams(tokens, n) when length(tokens) < n, do: []
  defp extract_ngrams(tokens, n) do
    tokens
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.map(&Enum.join(&1, " "))
  end

  defp compute_motif_strength(lines) do
    # Find the most common structural motif
    templates = Enum.map(lines, &extract_template/1)
    frequencies = Enum.frequencies(templates)

    if map_size(frequencies) == 0 do
      0.5
    else
      max_freq = frequencies |> Map.values() |> Enum.max()
      # How dominant is the most common pattern?
      clamp(max_freq / length(lines), 0.0, 1.0)
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
