defmodule Colorhymn.Perception.Density do
  @moduledoc """
  Density dimension analysis - information concentration.
  """

  # Common entities we want to detect
  @ip_pattern ~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/
  @domain_pattern ~r/\b[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}\b/
  @email_pattern ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/
  @uuid_pattern ~r/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/
  @mac_pattern ~r/\b([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})\b/
  @path_pattern ~r/[\/\\][\w\-\.\/\\]+/

  def analyze(lines, _content) when length(lines) < 1 do
    %{
      token_density: 0.5,
      entity_density: 0.5,
      information_density: 0.5,
      noise_ratio: 0.5
    }
  end

  def analyze(lines, content) do
    %{
      token_density: compute_token_density(lines),
      entity_density: compute_entity_density(lines),
      information_density: compute_information_density(lines),
      noise_ratio: compute_noise_ratio(lines, content)
    }
  end

  defp compute_token_density(lines) do
    tokens_per_line = Enum.map(lines, fn line ->
      line |> String.split(~r/[\s,;:=\[\]{}()"']+/, trim: true) |> length()
    end)

    if length(tokens_per_line) == 0 do
      0.5
    else
      avg_tokens = Enum.sum(tokens_per_line) / length(tokens_per_line)
      # Normalize: 5 tokens = 0.5, 20+ tokens = 1.0, 1 token = 0.1
      clamp(avg_tokens / 20, 0.0, 1.0)
    end
  end

  defp compute_entity_density(lines) do
    entities_per_line = Enum.map(lines, &count_entities/1)

    if length(entities_per_line) == 0 do
      0.5
    else
      avg_entities = Enum.sum(entities_per_line) / length(entities_per_line)
      # Normalize: 0 = 0.0, 5+ entities per line = 1.0
      clamp(avg_entities / 5, 0.0, 1.0)
    end
  end

  defp count_entities(line) do
    patterns = [@ip_pattern, @domain_pattern, @email_pattern,
                @uuid_pattern, @mac_pattern, @path_pattern]

    Enum.sum(Enum.map(patterns, fn pattern ->
      case Regex.scan(pattern, line) do
        matches -> length(matches)
      end
    end))
  end

  defp compute_information_density(lines) do
    all_tokens = lines
    |> Enum.flat_map(fn line ->
      String.split(line, ~r/[\s,;:=\[\]{}()"']+/, trim: true)
    end)

    if length(all_tokens) == 0 do
      0.5
    else
      unique_tokens = all_tokens |> Enum.uniq() |> length()
      total_tokens = length(all_tokens)

      # Ratio of unique to total
      clamp(unique_tokens / total_tokens, 0.0, 1.0)
    end
  end

  defp compute_noise_ratio(lines, _content) do
    # Detect common "noise" patterns: boilerplate, repeated prefixes, etc.
    noise_indicators = [
      ~r/^[\s\-=_*#]+$/,           # Separator lines
      ~r/^\s*$/,                    # Empty/whitespace only
      ~r/^[\s]*[#\/]{2,}/,         # Comment markers
      ~r/^\s*\.\.\.\s*$/,          # Continuation markers
      ~r/^[-]+$/,                   # Dashes
    ]

    noise_lines = Enum.count(lines, fn line ->
      Enum.any?(noise_indicators, &Regex.match?(&1, line))
    end)

    if length(lines) == 0 do
      0.5
    else
      clamp(noise_lines / length(lines), 0.0, 1.0)
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
