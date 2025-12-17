defmodule Colorhymn.Perception.Complexity do
  @moduledoc """
  Complexity dimension analysis - cognitive load and structure depth.
  """

  def analyze(lines, _content) when length(lines) < 1 do
    %{
      bracket_depth: 0.0,
      clause_chains: 0.5,
      parse_difficulty: 0.5,
      cognitive_load: 0.5
    }
  end

  def analyze(lines, content) do
    %{
      bracket_depth: compute_bracket_depth(lines),
      clause_chains: compute_clause_chains(lines),
      parse_difficulty: compute_parse_difficulty(lines, content),
      cognitive_load: compute_cognitive_load(lines, content)
    }
  end

  defp compute_bracket_depth(lines) do
    depths = Enum.map(lines, &max_bracket_depth/1)

    if length(depths) == 0 do
      0.0
    else
      max_depth = Enum.max(depths)
      # Normalize: depth 5+ = 1.0
      clamp(max_depth / 5, 0.0, 1.0)
    end
  end

  defp max_bracket_depth(line) do
    openers = ["[", "{", "(", "<"]
    closers = ["]", "}", ")", ">"]

    {max_d, _} = line
    |> String.graphemes()
    |> Enum.reduce({0, 0}, fn char, {max_depth, current} ->
      cond do
        char in openers ->
          new = current + 1
          {max(max_depth, new), new}
        char in closers ->
          {max_depth, max(0, current - 1)}
        true ->
          {max_depth, current}
      end
    end)

    max_d
  end

  defp compute_clause_chains(lines) do
    # Detect chained/compound statements: AND, OR, &&, ||, pipes, etc.
    chain_patterns = ~r/(\band\b|\bor\b|\&\&|\|\||->|=>|\|>|;.*;)/i

    chained_lines = Enum.count(lines, &Regex.match?(chain_patterns, &1))

    clamp(chained_lines / max(length(lines), 1), 0.0, 1.0)
  end

  defp compute_parse_difficulty(lines, _content) do
    # Heuristics for parse difficulty:
    # 1. Mixed formats (JSON inside text, etc.)
    # 2. Nested quotes
    # 3. Escape sequences
    # 4. Multiple encodings

    signals = []

    # Check for nested quotes
    nested_quotes = Enum.count(lines, fn line ->
      Regex.match?(~r/"[^"]*'[^']*'[^"]*"|'[^']*"[^"]*"[^']*'/, line)
    end)
    signals = [nested_quotes / max(length(lines), 1) | signals]

    # Check for escape sequences
    escapes = Enum.count(lines, &Regex.match?(~r/\\[nrtbf"'\\]|\\x[0-9a-fA-F]{2}|\\u[0-9a-fA-F]{4}/, &1))
    signals = [escapes / max(length(lines), 1) | signals]

    # Check for embedded JSON/XML in text
    embedded = Enum.count(lines, fn line ->
      has_json = Regex.match?(~r/\{[^{}]*"[^"]*"[^{}]*:/, line)
      has_xml = Regex.match?(~r/<[a-zA-Z][^>]*>.*<\/[a-zA-Z]/, line)
      has_json or has_xml
    end)
    signals = [embedded / max(length(lines), 1) | signals]

    if length(signals) == 0 do
      0.5
    else
      clamp(Enum.sum(signals) / length(signals), 0.0, 1.0)
    end
  end

  defp compute_cognitive_load(lines, content) do
    # Combine multiple complexity factors into overall cognitive load

    # 1. Average line length (longer = harder)
    avg_length = if length(lines) > 0 do
      total_length = lines |> Enum.map(&String.length/1) |> Enum.sum()
      total_length / length(lines)
    else
      0
    end
    length_factor = clamp(avg_length / 200, 0.0, 1.0)

    # 2. Vocabulary size (more unique terms = harder)
    tokens = content
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    vocab_size = tokens |> Enum.uniq() |> length()
    vocab_factor = clamp(vocab_size / 500, 0.0, 1.0)

    # 3. Nesting depth
    depth_factor = compute_bracket_depth(lines)

    # 4. Information density (from unique token ratio)
    total_tokens = length(tokens)
    info_density = if total_tokens > 0, do: vocab_size / total_tokens, else: 0.5

    # Weighted combination
    load = (length_factor * 0.2) + (vocab_factor * 0.3) + (depth_factor * 0.25) + (info_density * 0.25)

    clamp(load, 0.0, 1.0)
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
